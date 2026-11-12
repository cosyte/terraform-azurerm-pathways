# Pathways for production on one slot: one engine working and a second replica waiting as its warm
# standby, a zone-redundant PostgreSQL server with a standby of its own in a second zone, a year of
# logs, and the master key and the database URL in a Key Vault reached only through its private
# endpoint. It runs in a virtual network you already have, named by id. Every name, id and range
# here is a placeholder: replace them with your own. Nothing in this example is applied by our CI.

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  description = "The subscription to deploy into."
  type        = string
}

variable "image" {
  description = "Your project's image, built on the Pathways image and pinned by digest."
  type        = string
}

variable "apps_subnet_id" {
  description = "A subnet delegated to Microsoft.App/environments, /27 or larger, for the slot's environment."
  type        = string
}

variable "postgres_subnet_id" {
  description = "A subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "postgres_private_dns_zone_id" {
  description = "A private DNS zone whose name ends in .postgres.database.azure.com, linked to the virtual network."
  type        = string
}

variable "endpoints_subnet_id" {
  description = "A subnet for the Key Vault's private endpoint."
  type        = string
}

variable "key_vault_private_dns_zone_id" {
  description = "The privatelink.vaultcore.azure.net private DNS zone, linked to the virtual network."
  type        = string
}

variable "sender_cidrs" {
  description = "The address ranges your MLLP senders connect from, inside or connected to the virtual network."
  type        = list(string)
}

variable "database_administrators" {
  description = "The Microsoft Entra group whose members administer the database server."
  type = object({
    object_id      = string
    principal_name = string
  })
}

module "pathways" {
  source = "../.."

  name                = "pw-prod"
  resource_group_name = "rg-pathways-prod"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = var.apps_subnet_id
    }
  }

  # Two replicas, both started with --standby: the first takes the engine lease and runs every
  # channel; the other answers /readyz 503 standby, so the ingress sends it nothing, and takes over
  # within about 20 seconds once the first stops. pathways.yaml's probes block listens on
  # 0.0.0.0:9091, and its storage block reads PATHWAYS_DATABASE_URL with tls set.
  standby_replica = true

  mllp_ports            = [2575]
  ingress_allowed_cidrs = var.sender_cidrs
  drain_seconds         = 30 # Above 30 is unconfirmed: see "Limits we rely on" in the README.

  cpu    = 2
  memory = "4Gi"

  # Every schema change runs from the migrate job, before a new revision starts.
  app_start_args = ["start", "-C", "/project", "--no-migrate"]

  log_retention_days = 365

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = var.postgres_subnet_id
    private_dns_zone_id = var.postgres_private_dns_zone_id

    # Four vCores, 128 GiB, the longest backup retention, and a standby server in a second zone that
    # Azure fails over to.
    sku_name                       = "GP_Standard_D4ds_v5"
    storage_mb                     = 131072
    backup_retention_days          = 35
    zone                           = "1"
    high_availability_standby_zone = "2"

    entra_administrator = {
      object_id      = var.database_administrators.object_id
      principal_name = var.database_administrators.principal_name
      principal_type = "Group"
    }
  }

  key_vault = {
    private_endpoint_subnet_id = var.endpoints_subnet_id
    private_dns_zone_id        = var.key_vault_private_dns_zone_id
  }

  tags = {
    environment = "production"
  }
}

output "slots" {
  description = "The slot's environment address (where senders connect for MLLP), app and migrate job."
  value       = module.pathways.slots
}

output "postgres" {
  description = "The PostgreSQL server's host name, database and administrator login."
  value       = module.pathways.postgres
}
