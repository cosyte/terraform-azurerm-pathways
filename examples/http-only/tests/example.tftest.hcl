# Plans the example against mocked providers: no Azure account, no credentials. tests/run.sh at the
# repository root runs it. Every id and value below is synthetic.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pathways-example"
    }
  }
}

mock_provider "azapi" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  image           = "registry.example.com/integration/my-project:3f2a91c@sha256:0000000000000000000000000000000000000000000000000000000000000000"
}

run "plans_http_ingress_and_the_environment_zone" {
  command = plan

  assert {
    condition     = azurerm_private_dns_a_record.apps.name == "*"
    error_message = "Every name in the environment's zone must point at its static address."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.environment.registration_enabled == false
    error_message = "The zone must be linked to the network without registration."
  }
}
