variable "name" {
  description = "Short name the server's name is built from (psql-<name>): 3 to 16 lowercase letters, digits and hyphens, starting with a letter. The server name is global in Azure, so pick one nobody else uses."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "resource_group_name" {
  description = "The existing resource group the server is created in."
  type        = string
}

variable "location" {
  description = "The Azure region, such as eastus2."
  type        = string
}

variable "tags" {
  description = "Tags added to the server."
  type        = map(string)
  default     = {}
}

variable "delegated_subnet_id" {
  description = "A subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. The server has private access only."
  type        = string
}

variable "private_dns_zone_id" {
  description = "A private DNS zone whose name ends in .postgres.database.azure.com, linked to the virtual network."
  type        = string

  validation {
    condition     = can(regex("(?i)\\.postgres\\.database\\.azure\\.com$", var.private_dns_zone_id))
    error_message = "private_dns_zone_id must be a private DNS zone whose name ends in .postgres.database.azure.com."
  }
}

variable "postgres_version" {
  description = "The PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "sku_name" {
  description = "The server's SKU."
  type        = string
  default     = "GP_Standard_D2ds_v5"
}

variable "storage_mb" {
  description = "The server's storage in MB."
  type        = number
  default     = 32768
}

variable "backup_retention_days" {
  description = "How long backups are kept: 7 to 35 days."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be from 7 to 35."
  }
}

variable "geo_redundant_backup_enabled" {
  description = "Keep backups in the paired region as well."
  type        = bool
  default     = false
}

variable "zone" {
  description = "The availability zone of the primary. Null lets Azure choose."
  type        = string
  default     = null
}

variable "high_availability_standby_zone" {
  description = "The availability zone of a zone-redundant standby. Null creates no standby."
  type        = string
  default     = null
}

variable "entra_administrator" {
  description = "A Microsoft Entra principal made an administrator of the server. Null makes none; password and Entra authentication are both on either way."
  type = object({
    object_id      = string
    principal_name = string
    principal_type = string
  })
  default = null

  validation {
    condition     = var.entra_administrator == null || contains(["User", "Group", "ServicePrincipal"], try(var.entra_administrator.principal_type, ""))
    error_message = "entra_administrator.principal_type must be User, Group or ServicePrincipal."
  }
}
