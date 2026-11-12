# Plan-only tests of the database module used on its own, against mocked providers: no Azure
# account, no credentials. Every id and name below is synthetic.

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

  delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/example.postgres.database.azure.com"
}

run "defaults_are_private_and_encrypted_in_transit" {
  command = plan

  assert {
    condition     = azurerm_postgresql_flexible_server.this.name == "psql-pw-example"
    error_message = "The server must be named from name."
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
    condition     = length(azurerm_postgresql_flexible_server_active_directory_administrator.this) == 0
    error_message = "No Entra administrator is created unless one is named."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.backup_retention_days == 35
    error_message = "Backups must be kept 35 days by default."
  }

  assert {
    condition     = length(azurerm_postgresql_flexible_server.this.high_availability) == 0
    error_message = "No standby is created unless a standby zone is named."
  }

  assert {
    condition     = output.database == "pathways" && output.administrator_login == "pathways_admin"
    error_message = "The database and the administrator login must be the ones the engine uses."
  }

  assert {
    condition     = random_password.postgres.special == false && random_password.postgres.length == 40
    error_message = "The password must be 40 letters and digits, so it needs no escaping in the database URL."
  }
}

run "entra_administrator_and_standby_when_named" {
  command = plan

  variables {
    entra_administrator = {
      object_id      = "00000000-0000-0000-0000-000000000004"
      principal_name = "pathways-db-admins"
      principal_type = "Group"
    }
    zone                           = "1"
    high_availability_standby_zone = "2"
  }

  assert {
    condition     = azurerm_postgresql_flexible_server_active_directory_administrator.this[0].principal_name == "pathways-db-admins"
    error_message = "The named Entra administrator must be created."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.high_availability[0].mode == "ZoneRedundant" && azurerm_postgresql_flexible_server.this.high_availability[0].standby_availability_zone == "2"
    error_message = "A named standby zone must make the server zone redundant."
  }
}

run "refuses_a_backup_retention_under_7_days" {
  command = plan

  variables {
    backup_retention_days = 6
  }

  expect_failures = [var.backup_retention_days]
}

run "refuses_a_dns_zone_that_is_not_for_postgres" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  expect_failures = [var.private_dns_zone_id]
}

run "refuses_an_unknown_entra_principal_type" {
  command = plan

  variables {
    entra_administrator = {
      object_id      = "00000000-0000-0000-0000-000000000004"
      principal_name = "pathways-db-admins"
      principal_type = "Robot"
    }
  }

  expect_failures = [var.entra_administrator]
}
