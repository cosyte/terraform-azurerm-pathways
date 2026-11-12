output "id" {
  description = "The Key Vault's resource id."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "The Key Vault's name."
  value       = azurerm_key_vault.this.name
}

output "uri" {
  description = "The Key Vault's URI, ending in a slash. A secret's URL is <uri>secrets/<name>."
  value       = azurerm_key_vault.this.vault_uri
}

output "database_url_secret_name" {
  description = "The name of the secret that holds the database URL: database-url, or existing_database_url_secret_name."
  value       = local.database_url_secret
}

output "database_url_secret_id" {
  description = "The versionless id of the secret that holds the database URL. It is ready only once the reader holds its role, so a container app that reads it can start."
  value       = local.create_database_url_secret ? azurerm_key_vault_secret.database_url[0].versionless_id : "${azurerm_key_vault.this.vault_uri}secrets/${local.database_url_secret}"

  depends_on = [azurerm_role_assignment.identity_secrets_user]
}

output "data_plane_id" {
  description = "The Key Vault's resource id, ready only once its private endpoint (when there is one) exists, so a module that writes to the vault's data plane, such as a key, waits for a way in."
  value       = azurerm_key_vault.this.id

  depends_on = [azurerm_private_endpoint.key_vault]
}
