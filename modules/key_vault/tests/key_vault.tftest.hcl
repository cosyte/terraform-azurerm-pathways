# Plan-only tests of the key_vault module used on its own, against mocked providers: no Azure
# account, no credentials. Every id, name and value below is synthetic.

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
  database_url                = "postgres://psql-pw-example.example.com:5432/pathways"
}

run "defaults_are_private_and_audited" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.name == "kv-pw-example"
    error_message = "The vault must be named from name."
  }

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "The Key Vault must have no public network access by default."
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled && azurerm_key_vault.this.rbac_authorization_enabled
    error_message = "The Key Vault must have purge protection and RBAC authorization."
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny"
    error_message = "The Key Vault network rules must deny by default."
  }

  assert {
    condition     = azurerm_private_endpoint.key_vault[0].private_service_connection[0].subresource_names == tolist(["vault"])
    error_message = "The Key Vault private endpoint must connect to the vault."
  }

  assert {
    condition     = azurerm_role_assignment.identity_secrets_user.principal_id == var.secrets_reader_principal_id && azurerm_role_assignment.identity_secrets_user.role_definition_name == "Key Vault Secrets User"
    error_message = "The reader must get Key Vault Secrets User on the vault, and nothing more."
  }

  assert {
    condition     = azurerm_key_vault_secret.database_url.name == "database-url"
    error_message = "The database URL must be written to the database-url secret."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.key_vault.log_analytics_workspace_id == var.log_analytics_workspace_id
    error_message = "The vault's audit log must go to the workspace it is given."
  }

  assert {
    condition     = [for l in azurerm_monitor_diagnostic_setting.key_vault.enabled_log : l.category_group] == ["audit"]
    error_message = "The vault's diagnostic setting must send the audit category group."
  }
}

run "a_key_vault_reached_over_its_public_endpoint_needs_no_private_endpoint" {
  command = plan

  variables {
    private_endpoint_subnet_id    = null
    private_dns_zone_id           = null
    public_network_access_enabled = true
    allowed_ip_ranges             = ["198.51.100.10/32"]
  }

  assert {
    condition     = length(azurerm_private_endpoint.key_vault) == 0
    error_message = "No private endpoint is created unless a subnet is named."
  }

  assert {
    condition     = toset(azurerm_key_vault.this.network_acls[0].ip_rules) == toset(["198.51.100.10/32"])
    error_message = "The vault must admit only the listed ranges."
  }
}

run "refuses_a_key_vault_nothing_can_reach" {
  command = plan

  variables {
    private_endpoint_subnet_id = null
    private_dns_zone_id        = null
  }

  expect_failures = [var.private_endpoint_subnet_id]
}

run "refuses_a_private_endpoint_without_its_dns_zone" {
  command = plan

  variables {
    private_dns_zone_id = null
  }

  expect_failures = [var.private_dns_zone_id]
}

run "refuses_allowed_ranges_on_a_closed_public_endpoint" {
  command = plan

  variables {
    allowed_ip_ranges = ["198.51.100.10/32"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "refuses_a_soft_delete_retention_under_7_days" {
  command = plan

  variables {
    soft_delete_retention_days = 6
  }

  expect_failures = [var.soft_delete_retention_days]
}
