# Plan-only tests of the key_vault module with a database it did not make: the database URL is a
# secret you put in the vault yourself, so the module writes none and never sees the URL. Mocked
# providers: no Azure account, no credentials. Every id and name below is synthetic.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}

variables {
  name                = "pw-example"
  resource_group_name = "rg-example"
  location            = "eastus2"

  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
  private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"

  secrets_reader_principal_id = "00000000-0000-0000-0000-000000000005"
  log_analytics_workspace_id  = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/log-pw-example"

  existing_database_url_secret_name = "existing-database-url"
}

run "an_existing_database_url_secret_is_read_not_written" {
  command = plan

  assert {
    condition     = length(azurerm_key_vault_secret.database_url) == 0
    error_message = "With existing_database_url_secret_name the module must write no database-url secret."
  }

  assert {
    condition     = output.database_url_secret_name == "existing-database-url"
    error_message = "The secret name output must be the existing secret's."
  }
}

run "refuses_a_secret_name_key_vault_does_not_take" {
  command = plan

  variables {
    existing_database_url_secret_name = "database_url"
  }

  expect_failures = [var.existing_database_url_secret_name]
}

run "refuses_a_database_url_beside_an_existing_secret" {
  command = plan

  variables {
    database_url = "postgres://psql-pw-example.example.com:5432/pathways"
  }

  expect_failures = [var.existing_database_url_secret_name]
}

run "refuses_neither_a_database_url_nor_an_existing_secret" {
  command = plan

  variables {
    existing_database_url_secret_name = null
  }

  expect_failures = [var.existing_database_url_secret_name]
}
