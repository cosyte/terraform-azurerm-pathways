# Plan-only test against mocked providers: no Azure account, no credentials. Every id and name
# below is synthetic. The address guard refuses this list unless the unsafe opt-in is set.
# ::/80 is a /80, but it holds the whole IPv4-mapped range.

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

run "refuses_ipv6_holding_the_ipv4_mapped_range" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["::/80"]
  }

  expect_failures = [var.ingress_allowed_cidrs]
}
