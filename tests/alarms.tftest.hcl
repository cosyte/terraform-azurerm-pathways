# Plan-only tests of the root module's optional alarms, against mocked providers: no Azure account,
# no credentials. What the alarms module creates is tested in modules/alarms/tests, and the collector
# the app runs beside the engine in modules/container_apps/tests; these test that the root keeps the
# alarms off by default, wires them in when asked, and refuses what cannot work. Every id and name
# below is synthetic.

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

run "alarms_are_off_by_default" {
  command = plan

  assert {
    condition     = output.alarms == null
    error_message = "No alarm, Application Insights resource or secret may be created unless alarms_enabled is true."
  }
}

run "alarms_on_make_five_alerts_and_application_insights" {
  command = plan

  variables {
    alarms_enabled         = true
    alarms_action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Insights/actionGroups/ag-pathways-example"
    alarms_collector_image = "registry.example.com/otel/collector:0.0.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"
  }

  assert {
    condition     = sort(keys(output.alarms.alarm_ids)) == tolist(["oldest_pending_age", "queue_depth", "refused_messages", "settled_failed", "store_down"])
    error_message = "With alarms on, the alarms output must give the five alerts."
  }

  assert {
    condition     = output.alarms.application_insights.name == "appi-pw-example"
    error_message = "With alarms on, the alarms output must give the Application Insights resource, named from name."
  }
}

run "alarms_need_an_action_group" {
  command = plan

  variables {
    alarms_enabled         = true
    alarms_collector_image = "registry.example.com/otel/collector:0.0.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"
  }

  expect_failures = [var.alarms_action_group_id]
}

run "alarms_need_a_collector_image" {
  command = plan

  variables {
    alarms_enabled         = true
    alarms_action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Insights/actionGroups/ag-pathways-example"
  }

  expect_failures = [var.alarms_collector_image]
}

run "a_collector_image_without_a_digest_is_refused" {
  command = plan

  variables {
    alarms_enabled         = true
    alarms_action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Insights/actionGroups/ag-pathways-example"
    alarms_collector_image = "registry.example.com/otel/collector:latest"
  }

  expect_failures = [var.alarms_collector_image]
}

run "the_health_port_must_be_its_own" {
  command = plan

  variables {
    alarms_enabled         = true
    alarms_action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Insights/actionGroups/ag-pathways-example"
    alarms_collector_image = "registry.example.com/otel/collector:0.0.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"
    alarms_health_port     = 9091
  }

  expect_failures = [var.alarms_health_port]
}

run "a_health_token_passed_by_hand_is_refused" {
  command = plan

  variables {
    alarms_enabled         = true
    alarms_action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Insights/actionGroups/ag-pathways-example"
    alarms_collector_image = "registry.example.com/otel/collector:0.0.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"
    environment_variables  = { PATHWAYS_HEALTH_TOKEN = "not-a-real-token" }
  }

  expect_failures = [var.alarms_enabled]
}

run "a_master_key_named_after_an_alarms_secret_is_refused" {
  command = plan

  variables {
    alarms_enabled         = true
    alarms_action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Insights/actionGroups/ag-pathways-example"
    alarms_collector_image = "registry.example.com/otel/collector:0.0.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"
    encryption_key_secrets = { PATHWAYS_KEY_2026_11 = "pathways-health-token" }
  }

  expect_failures = [var.alarms_enabled]
}

run "a_store_down_window_azure_does_not_take_is_refused" {
  command = plan

  variables {
    alarms_store_down_minutes = 2
  }

  expect_failures = [var.alarms_store_down_minutes]
}
