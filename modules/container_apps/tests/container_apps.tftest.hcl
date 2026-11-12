# Plan-only tests of the container_apps module used on its own, against mocked providers: no Azure
# account, no credentials. Every id and name below is synthetic.

mock_provider "azurerm" {
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

  identity_id                = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-pw-example"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/log-pw-example"
  key_vault_uri              = "https://kv-pw-example.vault.azure.net/"
  database_url_secret_id     = "https://kv-pw-example.vault.azure.net/secrets/database-url"
}

run "defaults_are_private_and_log_to_the_workspace" {
  command = plan

  assert {
    condition     = azurerm_container_app_environment.this["blue"].internal_load_balancer_enabled
    error_message = "The environment must be internal to its virtual network by default."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.configuration.ingress.ipSecurityRestrictions == []
    error_message = "An internal environment with no allowed ranges adds no address restriction."
  }

  assert {
    condition     = azurerm_container_app_environment.this["blue"].logs_destination == "log-analytics"
    error_message = "The environment must send its logs to Log Analytics."
  }

  assert {
    condition     = azurerm_container_app_environment.this["blue"].log_analytics_workspace_id == var.log_analytics_workspace_id
    error_message = "The environment must send its logs to the workspace it is given."
  }

  assert {
    condition     = azapi_resource.app["blue"].name == "pw-example-blue" && azurerm_container_app_job.migrate["blue"].name == "pw-example-blue-migrate"
    error_message = "The app and the migrate job must be named from name and the slot."
  }

  assert {
    condition     = output.slots["blue"].app_name == "pw-example-blue" && output.slots["blue"].migrate_job_name == "pw-example-blue-migrate"
    error_message = "The slots output must name each slot's app and migrate job."
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
      [for s in azapi_resource.app["blue"].body.properties.configuration.secrets : s.keyVaultUrl] == ["https://kv-pw-example.vault.azure.net/secrets/database-url", "https://kv-pw-example.vault.azure.net/secrets/pathways-key-2026-11"] &&
      alltrue([for s in azapi_resource.app["blue"].body.properties.configuration.secrets : s.identity == var.identity_id])
    )
    error_message = "Each secret must be read from the Key Vault it is given, with the identity it is given."
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
    condition     = [for s in azurerm_container_app_job.migrate["blue"].secret : s.key_vault_secret_id] == [var.database_url_secret_id]
    error_message = "The migrate job's database-url secret must be the Key Vault secret it is given."
  }

  assert {
    condition     = azurerm_container_app_job.migrate["blue"].replica_retry_limit == 0
    error_message = "A failed migration must not be retried on its own."
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

run "a_private_registry_is_pulled_with_the_identity" {
  command = plan

  variables {
    container_registry_server = "example.azurecr.io"
  }

  assert {
    condition     = [for r in azapi_resource.app["blue"].body.properties.configuration.registries : "${r.server} ${r.identity}"] == ["example.azurecr.io ${var.identity_id}"]
    error_message = "The app must pull from the private registry with the identity it is given."
  }

  assert {
    condition     = [for r in azurerm_container_app_job.migrate["blue"].registry : r.server] == ["example.azurecr.io"]
    error_message = "The migrate job must pull from the private registry too."
  }
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

run "refuses_the_database_url_as_a_plain_variable" {
  command = plan

  variables {
    environment_variables = {
      PATHWAYS_DATABASE_URL = "postgres://example.invalid/pathways"
    }
  }

  expect_failures = [var.environment_variables]
}

run "refuses_the_database_url_secret_name_for_a_master_key" {
  command = plan

  variables {
    encryption_key_secrets = {
      PATHWAYS_KEY_2026_11 = "database-url"
    }
  }

  expect_failures = [var.encryption_key_secrets]
}

run "refuses_a_key_vault_uri_without_its_trailing_slash" {
  command = plan

  variables {
    key_vault_uri = "https://kv-pw-example.vault.azure.net"
  }

  expect_failures = [var.key_vault_uri]
}
