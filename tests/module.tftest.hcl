# Plan-only tests of the module against mocked providers: no Azure account, no credentials.
# tests/run.sh refuses a run block that does not plan, and a file that does not mock azurerm and
# azapi. Every id and name below is synthetic.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }

  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example"
    }
  }
}

mock_provider "azapi" {}

variables {
  name                = "pw-example"
  resource_group_name = "rg-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = "registry.example.com/integration/project:1a2b3c4@sha256:0000000000000000000000000000000000000000000000000000000000000000"
      infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-blue"
    }
  }

  mllp_ports = [2575]

  postgres = {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/example.postgres.database.azure.com"
  }

  key_vault = {
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
    private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }
}

run "defaults_are_private_and_encrypted_in_transit" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "The Key Vault must have no public network access by default."
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled && azurerm_key_vault.this.rbac_authorization_enabled
    error_message = "The Key Vault must have purge protection and RBAC authorization."
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny"
    error_message = "The Key Vault network rules must deny by default."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.public_network_access_enabled == false
    error_message = "The PostgreSQL server must have no public network access."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.authentication[0].active_directory_auth_enabled
    error_message = "Microsoft Entra authentication must be on for the PostgreSQL server."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_configuration.require_secure_transport.value == "on"
    error_message = "The PostgreSQL server must require TLS."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_configuration.ssl_min_protocol_version.value == "TLSv1.2"
    error_message = "The PostgreSQL server must refuse TLS below 1.2."
  }

  assert {
    condition     = azurerm_container_app_environment.this["blue"].internal_load_balancer_enabled
    error_message = "The environment must be internal to its virtual network by default."
  }

  assert {
    condition     = length(azurerm_postgresql_flexible_server_active_directory_administrator.this) == 0
    error_message = "No Entra administrator is created unless one is named."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.configuration.ingress.ipSecurityRestrictions == []
    error_message = "An internal environment with no allowed ranges adds no address restriction."
  }
}

run "app_has_tcp_ingress_probes_secrets_and_grace_period" {
  command = plan

  variables {
    mllp_ports    = [2575, 2576, 2577]
    drain_seconds = 120
    encryption_key_secrets = {
      PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
    }
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.configuration.ingress.transport == "tcp"
    error_message = "The app's ingress must be TCP for MLLP."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.configuration.ingress.exposedPort == 2575 && azapi_resource.app["blue"].body.properties.configuration.ingress.targetPort == 2575
    error_message = "The first MLLP port must be the main exposed and target port."
  }

  assert {
    condition     = [for m in azapi_resource.app["blue"].body.properties.configuration.ingress.additionalPortMappings : m.exposedPort] == [2576, 2577]
    error_message = "The other MLLP ports must be additional port mappings, in order."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.template.terminationGracePeriodSeconds == 120
    error_message = "The termination grace period must come from drain_seconds."
  }

  assert {
    condition = (
      [for p in azapi_resource.app["blue"].body.properties.template.containers[0].probes : p.httpGet.path if p.type == "Liveness"] == ["/livez"] &&
      [for p in azapi_resource.app["blue"].body.properties.template.containers[0].probes : p.httpGet.path if p.type == "Readiness"] == ["/readyz"]
    )
    error_message = "Liveness must probe /livez and readiness /readyz."
  }

  assert {
    condition     = sort([for p in azapi_resource.app["blue"].body.properties.template.containers[0].probes : p.type]) == tolist(["Liveness", "Readiness", "Startup"])
    error_message = "All three probes must be declared: the platform's defaults are TCP checks on the MLLP port."
  }

  assert {
    condition     = [for p in azapi_resource.app["blue"].body.properties.template.containers[0].probes : p.httpGet.path if p.type == "Startup"] == ["/livez"]
    error_message = "The startup probe must ask /livez, which answers live while the engine starts."
  }

  assert {
    condition     = alltrue([for p in azapi_resource.app["blue"].body.properties.template.containers[0].probes : p.httpGet.port == 9091 && p.httpGet.scheme == "HTTP"])
    error_message = "Every probe must ask the probe listener's port over HTTP."
  }

  assert {
    condition     = [for s in azapi_resource.app["blue"].body.properties.configuration.secrets : s.name] == ["database-url", "key-pathways-key-2026-11"]
    error_message = "The app's secrets must be the database URL and each named master key, all from Key Vault."
  }

  assert {
    condition = (
      [for e in azapi_resource.app["blue"].body.properties.template.containers[0].env : e.secretRef if e.name == "PATHWAYS_DATABASE_URL"] == ["database-url"] &&
      [for e in azapi_resource.app["blue"].body.properties.template.containers[0].env : e.secretRef if e.name == "PATHWAYS_KEY_2026_11"] == ["key-pathways-key-2026-11"]
    )
    error_message = "The database URL and the master keys must reach the engine through secretRef."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.template.scale.maxReplicas == 1
    error_message = "One engine per database: the app must run one replica."
  }

  assert {
    condition     = azapi_resource.app["blue"].identity[0].type == "UserAssigned"
    error_message = "The app must run as the user-assigned managed identity."
  }
}

run "migrate_job_runs_pathways_migrate" {
  command = plan

  assert {
    condition     = azurerm_container_app_job.migrate["blue"].template[0].container[0].args == tolist(["migrate", "-C", "/project"])
    error_message = "The migrate job must run pathways migrate."
  }

  assert {
    condition     = azurerm_container_app_job.migrate["blue"].template[0].container[0].env[0].secret_name == "database-url"
    error_message = "The migrate job must read the database URL from its Key Vault secret."
  }

  assert {
    condition     = azurerm_container_app_job.migrate["blue"].replica_retry_limit == 0
    error_message = "A failed migration must not be retried on its own."
  }
}

run "log_retention_comes_from_the_input" {
  command = plan

  variables {
    log_retention_days = 365
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 365
    error_message = "The workspace must keep logs for log_retention_days."
  }

  assert {
    condition     = azurerm_container_app_environment.this["blue"].logs_destination == "log-analytics"
    error_message = "The environment must send its logs to Log Analytics."
  }
}

run "blue_and_green_get_an_environment_each" {
  command = plan

  variables {
    slots = {
      blue = {
        image                    = "registry.example.com/integration/project:1a2b3c4@sha256:0000000000000000000000000000000000000000000000000000000000000000"
        infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-blue"
      }
      green = {
        image                    = "registry.example.com/integration/project:5d6e7f8@sha256:1111111111111111111111111111111111111111111111111111111111111111"
        infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-green"
      }
    }
  }

  assert {
    condition     = length(azurerm_container_app_environment.this) == 2 && length(azapi_resource.app) == 2 && length(azurerm_container_app_job.migrate) == 2
    error_message = "Each slot must get its own environment, app and migrate job."
  }

  assert {
    condition     = azapi_resource.app["green"].body.properties.configuration.ingress.exposedPort == azapi_resource.app["blue"].body.properties.configuration.ingress.exposedPort
    error_message = "Both slots must expose the same MLLP port, each in its own environment."
  }

  assert {
    condition     = azapi_resource.app["green"].body.properties.template.containers[0].image != azapi_resource.app["blue"].body.properties.template.containers[0].image
    error_message = "Each slot must run its own image."
  }
}

run "entra_administrator_and_private_endpoint_when_named" {
  command = plan

  variables {
    postgres = {
      delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
      private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/example.postgres.database.azure.com"
      entra_administrator = {
        object_id      = "00000000-0000-0000-0000-000000000004"
        principal_name = "pathways-db-admins"
        principal_type = "Group"
      }
    }
    key_vault = {
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    }
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_active_directory_administrator.this[0].principal_name == "pathways-db-admins"
    error_message = "The named Entra administrator must be created."
  }

  assert {
    condition     = azurerm_private_endpoint.key_vault[0].private_service_connection[0].subresource_names == tolist(["vault"])
    error_message = "The Key Vault private endpoint must connect to the vault."
  }
}

run "a_public_environment_admits_only_the_allowed_ranges" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["198.51.100.0/24", "203.0.113.8/29"]
  }

  assert {
    condition     = azurerm_container_app_environment.this["blue"].internal_load_balancer_enabled == false
    error_message = "The environment must be public when the internal load balancer is off."
  }

  assert {
    condition     = [for r in azapi_resource.app["blue"].body.properties.configuration.ingress.ipSecurityRestrictions : r.ipAddressRange] == ["198.51.100.0/24", "203.0.113.8/29"]
    error_message = "The app's address restrictions must be the ranges in ingress_allowed_cidrs, in order."
  }

  assert {
    condition     = alltrue([for r in azapi_resource.app["blue"].body.properties.configuration.ingress.ipSecurityRestrictions : r.action == "Allow"])
    error_message = "Each allowed range must be an Allow rule, so every other address is denied."
  }
}

run "any_address_only_with_the_explicit_opt_in" {
  command = plan

  variables {
    internal_load_balancer_enabled     = false
    ingress_allowed_cidrs              = ["0.0.0.0/0"]
    unsafe_allow_mllp_from_any_address = true
  }

  assert {
    condition     = [for r in azapi_resource.app["blue"].body.properties.configuration.ingress.ipSecurityRestrictions : r.ipAddressRange] == ["0.0.0.0/0"]
    error_message = "With the opt-in, the any-address range must pass through as asked."
  }
}

run "a_key_vault_reached_over_its_public_endpoint_needs_no_private_endpoint" {
  command = plan

  variables {
    key_vault = {
      public_network_access_enabled = true
      allowed_ip_ranges             = ["198.51.100.10/32"]
    }
  }

  assert {
    condition     = length(azurerm_private_endpoint.key_vault) == 0
    error_message = "No private endpoint is created unless a subnet is named."
  }

  assert {
    condition     = toset(azurerm_key_vault.this.network_acls[0].ip_rules) == toset(["198.51.100.10/32"])
    error_message = "The vault must admit only the listed ranges."
  }
}

# Unsafe inputs, refused at plan time.

run "refuses_a_public_environment_with_no_allowed_ranges" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
  }

  expect_failures = [var.internal_load_balancer_enabled]
}

run "refuses_the_ipv4_any_address_range" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["198.51.100.0/24", "0.0.0.0/0"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

run "refuses_the_ipv6_any_address_range" {
  command = plan

  variables {
    ingress_allowed_cidrs = ["::/0"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}

run "refuses_a_key_vault_nothing_can_reach" {
  command = plan

  variables {
    key_vault = {}
  }

  expect_failures = [var.key_vault]
}

# The documented limits, refused at plan time.

run "refuses_port_80" {
  command = plan

  variables {
    mllp_ports = [80]
  }

  expect_failures = [var.mllp_ports]
}

run "refuses_port_443" {
  command = plan

  variables {
    mllp_ports = [2575, 443]
  }

  expect_failures = [var.mllp_ports]
}

run "refuses_more_than_six_ports" {
  command = plan

  variables {
    mllp_ports = [2575, 2576, 2577, 2578, 2579, 2580, 2581]
  }

  expect_failures = [var.mllp_ports]
}

run "refuses_a_repeated_port" {
  command = plan

  variables {
    mllp_ports = [2575, 2575]
  }

  expect_failures = [var.mllp_ports]
}

run "refuses_the_reserved_port" {
  command = plan

  variables {
    mllp_ports = [2575, 36985]
  }

  expect_failures = [var.mllp_ports]
}

run "refuses_the_probe_port_as_an_mllp_port" {
  command = plan

  variables {
    mllp_ports = [2575, 9091]
  }

  expect_failures = [var.mllp_ports]
}

run "refuses_a_grace_period_over_600_seconds" {
  command = plan

  variables {
    drain_seconds = 601
  }

  expect_failures = [var.drain_seconds]
}

run "refuses_an_image_without_a_digest" {
  command = plan

  variables {
    slots = {
      blue = {
        image                    = "registry.example.com/integration/project:1a2b3c4"
        infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-blue"
      }
    }
  }

  expect_failures = [var.slots]
}

run "refuses_two_slots_on_one_subnet" {
  command = plan

  variables {
    slots = {
      blue = {
        image                    = "registry.example.com/integration/project:1a2b3c4@sha256:0000000000000000000000000000000000000000000000000000000000000000"
        infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-blue"
      }
      green = {
        image                    = "registry.example.com/integration/project:1a2b3c4@sha256:0000000000000000000000000000000000000000000000000000000000000000"
        infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-blue"
      }
    }
  }

  expect_failures = [var.slots]
}

run "refuses_log_retention_under_30_days" {
  command = plan

  variables {
    log_retention_days = 7
  }

  expect_failures = [var.log_retention_days]
}
