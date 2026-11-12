output "id" {
  description = "The PostgreSQL server's resource id."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "name" {
  description = "The PostgreSQL server's name."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  description = "The PostgreSQL server's host name, resolvable through the private DNS zone."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "database" {
  description = "The database the engine uses."
  value       = azurerm_postgresql_flexible_server_database.pathways.name
}

output "administrator_login" {
  description = "The administrator login. The password is only in database_url."
  value       = azurerm_postgresql_flexible_server.this.administrator_login
}

output "database_url" {
  description = "The engine's database URL, with the generated administrator password in it. Store it as a secret, never as a plain value."
  sensitive   = true
  value = format(
    "postgres://%s:%s@%s:5432/%s",
    azurerm_postgresql_flexible_server.this.administrator_login,
    random_password.postgres.result,
    azurerm_postgresql_flexible_server.this.fqdn,
    azurerm_postgresql_flexible_server_database.pathways.name,
  )
}
