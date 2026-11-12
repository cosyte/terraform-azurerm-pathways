variable "name" {
  description = "Short name the vault's name is built from (kv-<name>): 3 to 16 lowercase letters, digits and hyphens, starting with a letter. The vault name is global in Azure, so pick one nobody else uses."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "resource_group_name" {
  description = "The existing resource group the vault is created in."
  type        = string
}

variable "location" {
  description = "The Azure region, such as eastus2."
  type        = string
}

variable "tags" {
  description = "Tags added to every resource that takes them."
  type        = map(string)
  default     = {}
}

variable "public_network_access_enabled" {
  description = "Open the vault's public endpoint to the ranges in allowed_ip_ranges. The vault denies every network by default, and the apps and the machine that applies (Terraform writes the database-url secret) both need a way in: a private endpoint (recommended), or this with allowed_ip_ranges naming the runner and the environments' outbound addresses. Container Apps is not a trusted Azure service, so the AzureServices bypass does not let the apps in."
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "The address ranges allowed through the vault's public endpoint. Has no effect unless public_network_access_enabled is true."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.allowed_ip_ranges) == 0 || var.public_network_access_enabled
    error_message = "allowed_ip_ranges has no effect unless public_network_access_enabled is true."
  }
}

variable "private_endpoint_subnet_id" {
  description = "A subnet for the vault's private endpoint. Set with private_dns_zone_id, or leave both null."
  type        = string
  default     = null

  validation {
    condition     = var.private_endpoint_subnet_id != null || (var.public_network_access_enabled && length(var.allowed_ip_ranges) > 0)
    error_message = "Nothing could reach the Key Vault: the apps could not read their secrets and the apply could not write database-url. Set private_endpoint_subnet_id and private_dns_zone_id (recommended), or set public_network_access_enabled = true with allowed_ip_ranges naming the runner and the environments' outbound addresses."
  }
}

variable "private_dns_zone_id" {
  description = "The private DNS zone named privatelink.vaultcore.azure.net the private endpoint registers in. Set with private_endpoint_subnet_id, or leave both null."
  type        = string
  default     = null

  validation {
    condition     = (var.private_endpoint_subnet_id == null) == (var.private_dns_zone_id == null)
    error_message = "private_endpoint_subnet_id and private_dns_zone_id are set together or not at all."
  }
}

variable "soft_delete_retention_days" {
  description = "How long a deleted vault or secret can be recovered: 7 to 90 days. Purge protection is always on."
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be from 7 to 90."
  }
}

variable "secrets_reader_principal_id" {
  description = "The principal that reads the vault's secrets, such as the apps' user-assigned managed identity. It gets Key Vault Secrets User on the vault and nothing more."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "The Log Analytics workspace the vault's audit log is sent to."
  type        = string
}

variable "database_url" {
  description = "The engine's database URL, written to the database-url secret."
  type        = string
  sensitive   = true
}
