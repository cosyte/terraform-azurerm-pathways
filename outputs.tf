output "identity" {
  description = "The user-assigned managed identity the apps and jobs run as: its resource id, client id and principal id. Grant it AcrPull on a private registry."
  value = {
    id           = module.identity.id
    client_id    = module.identity.client_id
    principal_id = module.identity.principal_id
  }
}

output "key_vault" {
  description = "The Key Vault's id, name and URI. Put each master key named in encryption_key_secrets here."
  value = {
    id   = module.key_vault.id
    name = module.key_vault.name
    uri  = module.key_vault.uri
  }
}

output "postgres" {
  description = "The PostgreSQL server's id, host name, database and administrator login. The password is only in the database-url secret. Null with existing_postgres: the module made no server."
  value = one([
    for d in module.database : {
      id                  = d.id
      fqdn                = d.fqdn
      database            = d.database
      administrator_login = d.administrator_login
    }
  ])
}

output "database_url_secret_name" {
  description = "The Key Vault secret the app and the migrate job read the database URL from: database-url, which the module writes, or existing_postgres.database_url_secret_name."
  value       = module.key_vault.database_url_secret_name
}

output "log_analytics_workspace_id" {
  description = "The Log Analytics workspace the environments send logs to."
  value       = module.logs.id
}

output "slots" {
  description = "Per slot: the environment's id, static IP address (where senders connect for MLLP) and default domain, the app's id, name and address (fqdn, where senders connect for HTTP over TLS), and the migrate job's name."
  value       = module.container_apps.slots
}

output "http_port" {
  description = "The port the engine's HTTP source listens on behind HTTP ingress, or null for MLLP over TCP ingress."
  value       = var.http_port
}

output "standby_replica" {
  description = "Whether the app runs a second replica as the engine's warm standby."
  value       = var.standby_replica
}

output "mllp_ports" {
  description = "The MLLP ports each slot exposes."
  value       = var.mllp_ports
}

output "storage" {
  description = "With storage on: the account's id and name, the engine's container, the SFTP host (port 22), each SFTP user's sign-in name and container, and the plain environment variables the app gets for its channels. Null with storage off."
  value = one([
    for s in module.storage : {
      account_id      = s.account_id
      account_name    = s.account_name
      container       = s.container
      sftp_host       = s.sftp_host
      sftp_users      = s.sftp_users
      app_environment = tomap(local.storage_app_environment)
    }
  ])
}
