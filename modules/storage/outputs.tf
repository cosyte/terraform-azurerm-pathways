output "account_id" {
  description = "The storage account's resource id."
  value       = azurerm_storage_account.this.id
}

output "account_name" {
  description = "The storage account's name: the account key of a channel's azblob block."
  value       = azurerm_storage_account.this.name
}

output "container" {
  description = "The engine's own container."
  value       = azurerm_storage_container.this[var.container_name].name
}

output "sftp_host" {
  description = "The host SFTP clients connect to on port 22: the account's blob endpoint. In the virtual network it resolves to the private endpoint."
  value       = "${azurerm_storage_account.this.name}.blob.core.windows.net"
}

output "sftp_users" {
  description = "Per SFTP user: the name it signs in with (<account>.<user>) and its container, which is its home directory."
  value = {
    for u, c in local.user_containers : u => {
      username  = "${azurerm_storage_account.this.name}.${u}"
      container = azurerm_storage_container.this[c].name
    }
  }
}

output "user_containers" {
  description = "Each SFTP user's container, by user name: a channel reads or writes a user's files there."
  value       = { for u, c in local.user_containers : u => azurerm_storage_container.this[c].name }
}

output "customer_managed_key_id" {
  description = "The versionless id of the key the account is encrypted with, or null with Microsoft-managed keys."
  value       = var.customer_managed_key_enabled ? azurerm_key_vault_key.storage[0].versionless_id : null
}
