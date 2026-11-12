output "id" {
  description = "The identity's resource id."
  value       = azurerm_user_assigned_identity.this.id
}

output "client_id" {
  description = "The identity's client id."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "The identity's principal id: grant roles to this one."
  value       = azurerm_user_assigned_identity.this.principal_id
}
