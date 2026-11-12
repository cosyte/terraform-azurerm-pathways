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
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pathways-prod"
    }
  }
}

mock_provider "azapi" {}

variables {
  subscription_id               = "00000000-0000-0000-0000-000000000000"
  image                         = "registry.example.com/integration/my-project:3f2a91c@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  apps_subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-pathways-blue"
  postgres_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
  postgres_private_dns_zone_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/pathways-prod.postgres.database.azure.com"
  endpoints_subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
  key_vault_private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  sender_cidrs                  = ["10.20.0.0/16"]
  database_administrators = {
    object_id      = "00000000-0000-0000-0000-000000000004"
    principal_name = "pathways-db-admins"
  }
}

run "plans_one_engine_with_a_warm_standby_and_a_zone_redundant_database" {
  command = plan

  assert {
    condition     = output.slots["blue"].app_name == "pw-prod-blue"
    error_message = "The example must plan its one slot."
  }

  assert {
    condition     = output.postgres.administrator_login == "pathways_admin"
    error_message = "The production example must make its PostgreSQL server."
  }
}
