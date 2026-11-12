# The composition: each concern is a module under modules/, and this file wires them together.
# Every module can also be used on its own; its README says what it needs.

locals {
  tags = merge(var.tags, { "pathways-module" = "terraform-azurerm-pathways" })

  # With storage on, what the app's channels read: the identity to sign in as (Azure's default chain
  # reads AZURE_CLIENT_ID for a user-assigned identity), the account and the containers. Never a key.
  storage_app_environment = merge(concat([{}], [
    for s in module.storage : merge(
      {
        AZURE_CLIENT_ID           = module.identity.client_id
        PATHWAYS_AZBLOB_ACCOUNT   = s.account_name
        PATHWAYS_AZBLOB_CONTAINER = s.container
      },
      { for u, c in s.user_containers : "PATHWAYS_SFTP_${upper(u)}_CONTAINER" => c },
    )
  ])...)

  # With alarms on, the collector beside the engine: its image, the alarms module's configuration and
  # the two Key Vault secrets it reads. Without them, null, and the app is what it always was.
  metrics_collector = one([
    for a in module.alarms : {
      image                       = var.alarms_collector_image
      config                      = a.collector_config
      health_token_secret_id      = a.health_token_secret_id
      connection_string_secret_id = a.connection_string_secret_id
    }
  ])
}

# The identity the apps and the jobs run as.
module "identity" {
  source = "./modules/identity"

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

# The Log Analytics workspace the environments and the Key Vault's audit log write to.
module "logs" {
  source = "./modules/logs"

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
  retention_days      = var.log_retention_days
}

# The PostgreSQL flexible server, private access only, and the database URL. None with
# existing_postgres: the URL of a server you already run is a secret you put in the Key Vault.
module "database" {
  source = "./modules/database"
  count  = var.postgres == null ? 0 : 1

  name                           = var.name
  resource_group_name            = var.resource_group_name
  location                       = var.location
  tags                           = local.tags
  delegated_subnet_id            = var.postgres.delegated_subnet_id
  private_dns_zone_id            = var.postgres.private_dns_zone_id
  postgres_version               = var.postgres.version
  sku_name                       = var.postgres.sku_name
  storage_mb                     = var.postgres.storage_mb
  backup_retention_days          = var.postgres.backup_retention_days
  geo_redundant_backup_enabled   = var.postgres.geo_redundant_backup_enabled
  zone                           = var.postgres.zone
  high_availability_standby_zone = var.postgres.high_availability_standby_zone
  entra_administrator            = var.postgres.entra_administrator
}

# The Key Vault: the database URL secret, the identity's read role and the audit log.
module "key_vault" {
  source = "./modules/key_vault"

  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tags                          = local.tags
  public_network_access_enabled = var.key_vault.public_network_access_enabled
  allowed_ip_ranges             = var.key_vault.allowed_ip_ranges
  private_endpoint_subnet_id    = var.key_vault.private_endpoint_subnet_id
  private_dns_zone_id           = var.key_vault.private_dns_zone_id
  soft_delete_retention_days    = var.key_vault.soft_delete_retention_days
  secrets_reader_principal_id   = module.identity.principal_id
  log_analytics_workspace_id    = module.logs.id
  database_url                  = one(module.database[*].database_url)

  existing_database_url_secret_name = try(var.existing_postgres.database_url_secret_name, null)
}

# Per slot: the Container Apps environment, the Pathways app and the migrate job.
# The key_vault module's database_url_secret_id output waits for the identity's role on the vault,
# so no app revision or job is created before it can read its secrets.
module "container_apps" {
  source = "./modules/container_apps"

  name                               = var.name
  resource_group_name                = var.resource_group_name
  location                           = var.location
  tags                               = local.tags
  slots                              = var.slots
  mllp_ports                         = var.mllp_ports
  ingress_allowed_cidrs              = var.ingress_allowed_cidrs
  unsafe_allow_mllp_from_any_address = var.unsafe_allow_mllp_from_any_address
  internal_load_balancer_enabled     = var.internal_load_balancer_enabled
  probes_port                        = var.probes_port
  drain_seconds                      = var.drain_seconds
  cpu                                = var.cpu
  memory                             = var.memory
  environment_variables              = merge(var.environment_variables, local.storage_app_environment)
  encryption_key_secrets             = var.encryption_key_secrets
  container_registry_server          = var.container_registry_server
  app_start_args                     = var.app_start_args
  migrate_args                       = var.migrate_args
  migrate_timeout_seconds            = var.migrate_timeout_seconds
  http_port                          = var.http_port
  standby_replica                    = var.standby_replica
  identity_id                        = module.identity.id
  log_analytics_workspace_id         = module.logs.id
  key_vault_uri                      = module.key_vault.uri
  database_url_secret_id             = module.key_vault.database_url_secret_id
  metrics_collector                  = local.metrics_collector
}

# Optional, off by default: a storage account with SFTP for partners' files and the engine's own
# blobs, encrypted with a key from the Key Vault, its logs in the workspace, and blob data access for
# the app's identity on each of its containers.
module "storage" {
  source = "./modules/storage"
  count  = var.storage.enabled ? 1 : 0

  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  tags                          = local.tags
  account_name                  = var.storage.account_name
  container_name                = var.storage.container_name
  replication_type              = var.storage.replication_type
  sftp_enabled                  = var.storage.sftp_enabled
  public_network_access_enabled = var.storage.public_network_access_enabled
  allowed_ip_ranges             = var.storage.allowed_ip_ranges
  private_endpoint_subnet_id    = var.storage.private_endpoint_subnet_id
  private_dns_zone_id           = var.storage.private_dns_zone_id
  customer_managed_key_enabled  = var.storage.customer_managed_key_enabled
  key_vault_id                  = var.storage.customer_managed_key_enabled ? module.key_vault.data_plane_id : null
  soft_delete_retention_days    = var.storage.soft_delete_retention_days
  sftp_users                    = var.storage.sftp_users
  blob_data_principal_id        = module.identity.principal_id
  log_analytics_workspace_id    = module.logs.id
}

# Optional, off by default: alerts on the engine's own metrics. A collector beside the engine (added
# through container_apps above) reads /metrics with a token this module writes to the Key Vault, and
# sends five metrics to Application Insights, where five metric alerts call your action group.
module "alarms" {
  source = "./modules/alarms"
  count  = var.alarms_enabled ? 1 : 0

  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tags                       = local.tags
  log_analytics_workspace_id = module.logs.id
  key_vault_id               = module.key_vault.secrets_writer_id
  action_group_id            = var.alarms_action_group_id
  health_port                = var.alarms_health_port
  health_token_version       = var.alarms_health_token_version
  store_down_minutes         = var.alarms_store_down_minutes
  oldest_pending_age_seconds = var.alarms_oldest_pending_age_seconds
  queue_depth_threshold      = var.alarms_queue_depth_threshold
  refused_messages_threshold = var.alarms_refused_messages_threshold
  settled_failed_threshold   = var.alarms_settled_failed_threshold
}
