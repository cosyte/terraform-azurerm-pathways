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
  description = "The PostgreSQL server's id, host name, database and administrator login. The password is only in the database-url secret."
  value = {
    id                  = module.database.id
    fqdn                = module.database.fqdn
    database            = module.database.database
    administrator_login = module.database.administrator_login
  }
}

output "log_analytics_workspace_id" {
  description = "The Log Analytics workspace the environments send logs to."
  value       = module.logs.id
}

output "slots" {
  description = "Per slot: the environment's id and static IP address (where senders connect for MLLP), the app's id and name, and the migrate job's name."
  value       = module.container_apps.slots
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
