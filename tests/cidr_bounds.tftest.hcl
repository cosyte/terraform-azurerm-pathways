# Plan-only test against mocked providers: no Azure account, no credentials. Every id and name
# below is synthetic. Ranges just inside the address guard's bounds, and the wide ranges it lets through only with
# the unsafe opt-in.

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

run "narrowest_bounds_pass_without_the_opt_in" {
  command = plan

  variables {
    internal_load_balancer_enabled = false
    ingress_allowed_cidrs          = ["10.0.0.0/8", "2001:db8::/32", "::ffff:198.51.100.0/120", "::ffff:10.0.0.0/104"]
  }

  assert {
    condition     = [for r in azapi_resource.app["blue"].body.properties.configuration.ingress.ipSecurityRestrictions : r.ipAddressRange] == ["10.0.0.0/8", "2001:db8::/32", "::ffff:198.51.100.0/120", "::ffff:10.0.0.0/104"]
    error_message = "Ranges at /8 (IPv4), /32 (IPv6) or narrower must pass through as written."
  }
}

run "wide_ranges_pass_only_with_the_opt_in" {
  command = plan

  variables {
    internal_load_balancer_enabled     = false
    ingress_allowed_cidrs              = ["0.0.0.0/1", "128.0.0.0/1", "::ffff:0:0/96", "2001:db8::/31"]
    unsafe_allow_mllp_from_any_address = true
  }

  assert {
    condition     = [for r in azapi_resource.app["blue"].body.properties.configuration.ingress.ipSecurityRestrictions : r.ipAddressRange] == ["0.0.0.0/1", "128.0.0.0/1", "::ffff:0:0/96", "2001:db8::/31"]
    error_message = "With the opt-in, wide ranges must pass through as written."
  }
}
