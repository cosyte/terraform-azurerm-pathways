variable "name" {
  description = "Short name the account's default name (st<name> without its hyphens) and the other names are built from: 3 to 16 lowercase letters, digits and hyphens, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "resource_group_name" {
  description = "The existing resource group the account is created in."
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

variable "account_name" {
  description = "The storage account's name: 3 to 24 lowercase letters and digits. It is global in Azure. Null names it st<name> without its hyphens."
  type        = string
  default     = null

  validation {
    condition     = var.account_name == null || can(regex("^[a-z0-9]{3,24}$", var.account_name))
    error_message = "account_name must be 3 to 24 lowercase letters and digits."
  }
}

variable "container_name" {
  description = "The engine's own container: 3 to 63 lowercase letters, digits and single hyphens, not starting with sftp-, which names the SFTP users' containers."
  type        = string
  default     = "pathways"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.container_name)) && !strcontains(var.container_name, "--") && !startswith(var.container_name, "sftp-")
    error_message = "container_name must be 3 to 63 lowercase letters, digits and single hyphens, starting and ending with a letter or digit, and must not start with sftp-: each SFTP user's container is sftp-<user>."
  }
}

variable "replication_type" {
  description = "The account's redundancy: LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS. More copies cost more. Not every region offers zone redundancy."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
  }
}

variable "sftp_enabled" {
  description = "Turn the account's SFTP endpoint on. Azure charges for SFTP by the hour while it is on, used or not; turn it off when no partner needs it. Hierarchical namespace stays on either way."
  type        = bool
  default     = true

  validation {
    condition     = var.sftp_enabled || length(var.sftp_users) == 0
    error_message = "sftp_users needs sftp_enabled = true: a local user can sign in only over SFTP."
  }
}

variable "public_network_access_enabled" {
  description = "Open the account's public endpoint to the ranges in allowed_ip_ranges, for SFTP clients outside your virtual network. Off by default: only the private endpoint reaches the account."
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "The public IPv4 addresses and ranges allowed through the account's public endpoint, such as 198.51.100.0/24 or 203.0.113.7. Has no effect unless public_network_access_enabled is true. Azure Storage takes IPv4 only, a single address without a prefix rather than a /31 or /32, and no private (RFC 1918) range. The plan refuses those, a range wider than a /8 (0.0.0.0/0 included), and a list that adds up to every IPv4 address."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.allowed_ip_ranges) == 0 || var.public_network_access_enabled
    error_message = "allowed_ip_ranges has no effect unless public_network_access_enabled is true."
  }

  validation {
    condition     = !var.public_network_access_enabled || length(var.allowed_ip_ranges) > 0
    error_message = "public_network_access_enabled = true needs allowed_ip_ranges naming the SFTP clients' public addresses: the account carries PHI."
  }

  validation {
    condition = alltrue([
      for c in var.allowed_ip_ranges :
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}(/[1-9][0-9]?)?$", c)) && can(cidrhost(strcontains(c, "/") ? c : "${c}/32", 0))
    ])
    error_message = "Each entry of allowed_ip_ranges must be a public IPv4 address or range, such as 203.0.113.7 or 198.51.100.0/24: no spaces, no leading zero in the prefix, and no IPv6 (Azure Storage's IP rules take IPv4 only)."
  }

  validation {
    condition     = alltrue([for c in var.allowed_ip_ranges : !can(regex("/3[12]$", c))])
    error_message = "Azure Storage does not take a /31 or /32 range in an IP rule: write each address on its own, without a prefix."
  }

  # The prefix is compared as a number once the entry has parsed; an entry that does not parse counts
  # as wide (try falls back to false), so this check fails closed.
  validation {
    condition = alltrue([
      for c in var.allowed_ip_ranges : try(!strcontains(c, "/") || tonumber(split("/", c)[1]) >= 8, false)
    ])
    error_message = "allowed_ip_ranges must not hold a range wider than a /8 (0.0.0.0/0 included): the account carries PHI. Name your SFTP clients' ranges."
  }

  # Ranges each narrow enough can still add up to every IPv4 address. Overlaps are counted twice, so
  # the sum can only overstate the coverage.
  validation {
    condition = try(sum(concat([0], [
      for c in distinct(var.allowed_ip_ranges) : strcontains(c, "/") ? pow(2, 32 - tonumber(split("/", c)[1])) : 1
    ])) < pow(2, 32), false)
    error_message = "The ranges in allowed_ip_ranges add up to every IPv4 address: the account carries PHI. Name your SFTP clients' ranges."
  }

  # Two ranges overlap when the wider one holds the narrower one's first address.
  validation {
    condition = alltrue(flatten([
      for c in var.allowed_ip_ranges : [
        for p in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] : try(
          !(
            tonumber(strcontains(c, "/") ? split("/", c)[1] : "32") <= tonumber(split("/", p)[1])
            ? cidrhost("${cidrhost(p, 0)}/${strcontains(c, "/") ? split("/", c)[1] : "32"}", 0) == cidrhost(strcontains(c, "/") ? c : "${c}/32", 0)
            : cidrhost("${cidrhost(strcontains(c, "/") ? c : "${c}/32", 0)}/${split("/", p)[1]}", 0) == cidrhost(p, 0)
          ),
          false
        )
      ]
    ]))
    error_message = "allowed_ip_ranges must not hold or overlap a private range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16): Azure Storage's IP rules take public addresses only. Clients in your virtual network reach the account through its private endpoint."
  }
}

variable "private_endpoint_subnet_id" {
  description = "The subnet for the account's blob private endpoint, which the engine reads through and SFTP clients in your virtual network connect to. Required: Azure Storage's IP rules do not apply to traffic from the same region, so the engine cannot come in over the public endpoint."
  type        = string
}

variable "private_dns_zone_id" {
  description = "The private DNS zone named privatelink.blob.core.windows.net the private endpoint registers in, linked to the virtual network."
  type        = string
}

variable "customer_managed_key_enabled" {
  description = "Encrypt the account with a key the module creates in the Key Vault at key_vault_id, rotated by the vault every year. Whoever applies gets Key Vault Crypto Officer on the vault to create it. False leaves Microsoft-managed keys."
  type        = bool
  default     = true
}

variable "key_vault_id" {
  description = "The Key Vault the customer-managed key is created in. It must have purge protection and RBAC authorization on, and let Azure's trusted services through its firewall, as the key_vault module's vault does. The machine that applies needs to reach it, as for any secret it writes."
  type        = string
  default     = null

  validation {
    condition     = !var.customer_managed_key_enabled || var.key_vault_id != null
    error_message = "customer_managed_key_enabled needs key_vault_id: name the vault the key is created in, or set customer_managed_key_enabled = false."
  }
}

variable "soft_delete_retention_days" {
  description = "How long a deleted blob or container can be recovered: 1 to 365 days. A soft-deleted blob still holds its data and still costs storage."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365 && floor(var.soft_delete_retention_days) == var.soft_delete_retention_days
    error_message = "soft_delete_retention_days must be a whole number from 1 to 365."
  }
}

variable "sftp_users" {
  description = <<-EOT
    The SFTP local users, keyed by a user name of 3 to 32 lowercase letters and digits, starting with a
    letter. Each gets a container of its own, sftp-<user>, as its home directory and a permission on
    that container only, so it cannot reach another user's files: on Blob Storage a home directory
    alone does not confine a user. Each signs in with an SSH key, never a password, as
    <account>.<user>. ssh_public_keys holds one or more public keys, each one line in OpenSSH form
    (type, base64 data and an optional comment, which becomes the key's description). permissions is
    any of create, write, list, read and delete; the default, create, write and list, lets a partner
    drop files and see them, and no more.
  EOT
  type = map(object({
    ssh_public_keys = list(string)
    permissions     = optional(list(string), ["create", "write", "list"])
  }))
  default = {}

  validation {
    condition     = alltrue([for u in keys(var.sftp_users) : can(regex("^[a-z][a-z0-9]{2,31}$", u))])
    error_message = "Each SFTP user name must be 3 to 32 lowercase letters and digits, starting with a letter."
  }

  validation {
    condition     = alltrue([for u in values(var.sftp_users) : length(u.ssh_public_keys) >= 1 && length(u.ssh_public_keys) <= 10])
    error_message = "Each SFTP user needs 1 to 10 SSH public keys: a user signs in with a key, never a password."
  }

  validation {
    condition = alltrue(flatten([
      for u in values(var.sftp_users) : [
        for k in u.ssh_public_keys : can(regex("^[a-z][a-z0-9.@-]* [A-Za-z0-9+/]+={0,3}( [^\\r\\n]*)?$", k)) && !strcontains(upper(k), "PRIVATE KEY")
      ]
    ]))
    error_message = "Each SSH key must be one public key on one line, in OpenSSH form: its type (such as ssh-rsa), its base64 data and an optional comment. Never a private key."
  }

  validation {
    condition = alltrue([
      for u in values(var.sftp_users) :
      length(u.permissions) >= 1 && alltrue([for p in u.permissions : contains(["create", "write", "list", "read", "delete"], p)])
    ])
    error_message = "Each SFTP user's permissions must be one or more of create, write, list, read and delete."
  }
}

variable "blob_data_principal_id" {
  description = "The principal that reads and writes blobs for the engine, such as its user-assigned managed identity. It gets Storage Blob Data Contributor on the engine's container and on each SFTP user's container, so the engine needs no account key."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "The Log Analytics workspace the blob service's read, write and delete logs are sent to."
  type        = string
}
