# Plan-only tests of the root module, the composition, against mocked providers: no Azure account,
# no credentials. tests/run.sh refuses a run block that does not plan, and a file that does not mock
# azurerm and azapi. Every id and name below is synthetic.


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

# The composition: the root wires the modules under modules/ together, and its outputs come from
# them. What each module creates is tested in its own tests/ folder.

run "the_composition_plans_with_the_defaults" {
  command = plan

  assert {
    condition     = output.key_vault.name == "kv-pw-example"
    error_message = "The Key Vault must come from the key_vault module, named from name."
  }

  assert {
    condition     = output.postgres.database == "pathways" && output.postgres.administrator_login == "pathways_admin"
    error_message = "The postgres output must come from the database module."
  }

  assert {
    condition     = sort(keys(output.slots)) == tolist(["blue"])
    error_message = "The slots output must hold one entry per slot."
  }

  assert {
    condition     = output.slots["blue"].app_name == "pw-example-blue" && output.slots["blue"].migrate_job_name == "pw-example-blue-migrate"
    error_message = "Each slot's app and migrate job must come from the container_apps module, named from name and the slot."
  }

  assert {
    condition     = output.mllp_ports == tolist([2575])
    error_message = "The mllp_ports output must be the ports asked for."
  }
}

run "blue_and_green_each_reach_the_outputs" {
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
    condition     = sort(keys(output.slots)) == tolist(["blue", "green"])
    error_message = "Each slot must reach the slots output."
  }

  assert {
    condition     = output.slots["green"].app_name == "pw-example-green"
    error_message = "The green slot's app must be named for it."
  }
}

run "every_input_reaches_its_module" {
  command = plan

  variables {
    mllp_ports                = [2575, 2576]
    probes_port               = 9092
    drain_seconds             = 60
    cpu                       = 2
    memory                    = "4Gi"
    environment_variables     = { PATHWAYS_LOG_LEVEL = "info" }
    encryption_key_secrets    = { PATHWAYS_KEY_2026_11 = "pathways-key-2026-11" }
    container_registry_server = "example.azurecr.io"
    app_start_args            = ["start", "-C", "/project", "--no-migrate"]
    migrate_args              = ["migrate", "-C", "/project"]
    migrate_timeout_seconds   = 600
    log_retention_days        = 365
    tags                      = { environment = "example" }
    postgres = {
      delegated_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
      private_dns_zone_id            = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/example.postgres.database.azure.com"
      version                        = "16"
      sku_name                       = "GP_Standard_D4ds_v5"
      storage_mb                     = 65536
      backup_retention_days          = 14
      geo_redundant_backup_enabled   = true
      zone                           = "1"
      high_availability_standby_zone = "2"
      entra_administrator = {
        object_id      = "00000000-0000-0000-0000-000000000004"
        principal_name = "pathways-db-admins"
        principal_type = "Group"
      }
    }
    key_vault = {
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
      soft_delete_retention_days = 30
    }
  }

  assert {
    condition     = output.mllp_ports == tolist([2575, 2576])
    error_message = "The mllp_ports output must be the ports asked for."
  }
}

run "a_public_environment_with_allowed_ranges_plans" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["198.51.100.0/24", "203.0.113.8/29"]
  }

  assert {
    condition     = sort(keys(output.slots)) == tolist(["blue"])
    error_message = "A public environment with named senders must plan."
  }
}

run "any_address_plans_only_with_the_explicit_opt_in" {
  command = plan

  variables {
    internal_load_balancer_enabled     = false
    ingress_allowed_cidrs              = ["0.0.0.0/0"]
    unsafe_allow_mllp_from_any_address = true
  }

  assert {
    condition     = sort(keys(output.slots)) == tolist(["blue"])
    error_message = "With the opt-in, the any-address range must plan."
  }
}

run "a_key_vault_reached_over_its_public_endpoint_plans" {
  command = plan

  variables {
    key_vault = {
      public_network_access_enabled = true
      allowed_ip_ranges             = ["198.51.100.10/32"]
    }
  }

  assert {
    condition     = output.key_vault.name == "kv-pw-example"
    error_message = "A Key Vault reached over its public endpoint must plan."
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
