output "identity" {
  description = "The user-assigned managed identity the apps and jobs run as: its resource id, client id and principal id. Grant it AcrPull on a private registry."
  value = {
    id           = azurerm_user_assigned_identity.this.id
    client_id    = azurerm_user_assigned_identity.this.client_id
    principal_id = azurerm_user_assigned_identity.this.principal_id
  }
}

output "key_vault" {
  description = "The Key Vault's id, name and URI. Put each master key named in encryption_key_secrets here."
  value = {
    id   = azurerm_key_vault.this.id
    name = azurerm_key_vault.this.name
    uri  = azurerm_key_vault.this.vault_uri
  }
}

output "postgres" {
  description = "The PostgreSQL server's id, host name, database and administrator login. The password is only in the database-url secret."
  value = {
    id                  = azurerm_postgresql_flexible_server.this.id
    fqdn                = azurerm_postgresql_flexible_server.this.fqdn
    database            = azurerm_postgresql_flexible_server_database.pathways.name
    administrator_login = azurerm_postgresql_flexible_server.this.administrator_login
  }
}

output "log_analytics_workspace_id" {
  description = "The Log Analytics workspace the environments send logs to."
  value       = azurerm_log_analytics_workspace.this.id
}

output "slots" {
  description = "Per slot: the environment's id and static IP address (where senders connect for MLLP), the app's id and name, and the migrate job's name."
  value = {
    for k in keys(var.slots) : k => {
      environment_id   = azurerm_container_app_environment.this[k].id
      static_ip        = azurerm_container_app_environment.this[k].static_ip_address
      app_id           = azapi_resource.app[k].id
      app_name         = azapi_resource.app[k].name
      migrate_job_name = azurerm_container_app_job.migrate[k].name
    }
  }
}

output "mllp_ports" {
  description = "The MLLP ports each slot exposes."
  value       = var.mllp_ports
}
