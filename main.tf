# The composition: each concern is a module under modules/, and this file wires them together.
# Every module can also be used on its own; its README says what it needs.

locals {
  tags = merge(var.tags, { "pathways-module" = "terraform-azurerm-pathways" })
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

# The PostgreSQL flexible server, private access only, and the database URL.
module "database" {
  source = "./modules/database"

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
  database_url                  = module.database.database_url
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
  environment_variables              = var.environment_variables
  encryption_key_secrets             = var.encryption_key_secrets
  container_registry_server          = var.container_registry_server
  app_start_args                     = var.app_start_args
  migrate_args                       = var.migrate_args
  migrate_timeout_seconds            = var.migrate_timeout_seconds
  identity_id                        = module.identity.id
  log_analytics_workspace_id         = module.logs.id
  key_vault_uri                      = module.key_vault.uri
  database_url_secret_id             = module.key_vault.database_url_secret_id
}
