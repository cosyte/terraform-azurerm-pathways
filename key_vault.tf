resource "azurerm_key_vault" "this" {
  name                          = "kv-${var.name}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = var.key_vault.soft_delete_retention_days
  public_network_access_enabled = var.key_vault.public_network_access_enabled
  tags                          = local.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.key_vault.allowed_ip_ranges
  }
}

resource "azurerm_private_endpoint" "key_vault" {
  count = var.key_vault.private_endpoint_subnet_id == null ? 0 : 1

  name                = "pe-kv-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.key_vault.private_endpoint_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "kv-${var.name}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "vault"
    private_dns_zone_ids = [var.key_vault.private_dns_zone_id]
  }
}

# The apps and the jobs read secrets, nothing more.
resource "azurerm_role_assignment" "identity_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

# Whoever applies writes the database-url secret.
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_secret" "database_url" {
  name         = local.database_url_secret
  key_vault_id = azurerm_key_vault.this.id
  content_type = "text/plain"
  value = format(
    "postgres://%s:%s@%s:5432/%s",
    azurerm_postgresql_flexible_server.this.administrator_login,
    random_password.postgres.result,
    azurerm_postgresql_flexible_server.this.fqdn,
    azurerm_postgresql_flexible_server_database.pathways.name,
  )
  tags = local.tags

  depends_on = [azurerm_role_assignment.deployer_secrets_officer, azurerm_private_endpoint.key_vault]
}

# Who reads which secret: Key Vault's audit log, kept with the engine's logs.
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "audit"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "audit"
  }
}
