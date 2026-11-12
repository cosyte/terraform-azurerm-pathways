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

# The network the example looks up, as a lookup would find it.
override_data {
  target = data.azurerm_subnet.apps
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-pathways-blue"
  }
}

override_data {
  target = data.azurerm_subnet.postgres
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
  }
}

override_data {
  target = data.azurerm_subnet.endpoints
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
  }
}

override_data {
  target = data.azurerm_private_dns_zone.postgres
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-example/providers/Microsoft.Network/privateDnsZones/pathways-example.postgres.database.azure.com"
  }
}

override_data {
  target = data.azurerm_private_dns_zone.key_vault
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }
}

run "plans_in_the_network_it_looks_up" {
  command = plan

  assert {
    condition     = azurerm_resource_group.pathways.name == "rg-pathways-example"
    error_message = "The module's resources must go in a group of their own."
  }

  assert {
    condition     = output.slots["blue"].app_name == "pw-example-blue"
    error_message = "The example must plan its one slot."
  }
}
