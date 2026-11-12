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
  description = "The name of the secret that holds the database URL."
  value       = azurerm_key_vault_secret.database_url.name
}

output "database_url_secret_id" {
  description = "The versionless id of the database-url secret. It is ready only once the reader holds its role, so a container app that reads it can start."
  value       = azurerm_key_vault_secret.database_url.versionless_id

  depends_on = [azurerm_role_assignment.identity_secrets_user]
}
