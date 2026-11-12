output "id" {
  description = "The Log Analytics workspace's resource id."
  value       = azurerm_log_analytics_workspace.this.id
}

output "name" {
  description = "The Log Analytics workspace's name."
  value       = azurerm_log_analytics_workspace.this.name
}
