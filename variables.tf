variable "name" {
  description = "Short name every resource name is built from: 3 to 16 lowercase letters, digits and hyphens, starting with a letter. The Key Vault and the PostgreSQL server names are global in Azure, so pick one nobody else uses."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "resource_group_name" {
  description = "The existing resource group everything is created in."
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

variable "slots" {
  description = <<-EOT
    The deployment slots, keyed by a slot name of 1 to 5 lowercase letters or digits (such as blue
    and green). Each slot gets its own Container Apps environment, app and migrate job, on its own
    infrastructure subnet, so the two slots can expose the same MLLP ports at once: TCP ports are
    unique across one environment. Each subnet must be delegated to Microsoft.App/environments and be
    at least a /27. The image must be pinned by digest (registry/repository:tag@sha256:...).
  EOT
  type = map(object({
    image                    = string
    infrastructure_subnet_id = string
  }))

  validation {
    condition     = length(var.slots) >= 1 && length(var.slots) <= 2
    error_message = "slots must name one slot, or two for blue and green."
  }

  validation {
    condition     = alltrue([for k in keys(var.slots) : can(regex("^[a-z][a-z0-9]{0,4}$", k))])
    error_message = "Each slot name must be 1 to 5 lowercase letters or digits, starting with a letter."
  }

  validation {
    condition     = alltrue([for s in values(var.slots) : can(regex("^[^\\s@]+@sha256:[0-9a-f]{64}$", s.image))])
    error_message = "Each slot's image must be pinned by digest: registry/repository:tag@sha256:<64 hex digits>."
  }

  validation {
    condition     = length(distinct([for s in values(var.slots) : lower(s.infrastructure_subnet_id)])) == length(var.slots)
    error_message = "Each slot needs its own infrastructure subnet: one subnet holds one Container Apps environment."
  }
}

variable "mllp_ports" {
  description = "The TCP ports the engine's MLLP sources listen on, each exposed on the same port number. The first is the app's main ingress port, the rest are additional port mappings: six at most (one plus five), never 80 or 443, never the reserved port 36985, never the probe port. Every exposed port, main or additional, is unique across the environment, and each slot has an environment of its own."
  type        = list(number)

  validation {
    condition     = length(var.mllp_ports) >= 1 && length(var.mllp_ports) <= 6
    error_message = "mllp_ports must hold 1 to 6 ports: Container Apps exposes one main port and at most five additional TCP ports."
  }

  validation {
    condition     = alltrue([for p in var.mllp_ports : p >= 1 && p <= 65535 && floor(p) == p])
    error_message = "Each MLLP port must be a whole number from 1 to 65535."
  }

  validation {
    condition     = length(distinct(var.mllp_ports)) == length(var.mllp_ports)
    error_message = "mllp_ports must not repeat a port: an exposed TCP port, main or additional, is unique across the environment."
  }

  validation {
    condition     = !contains(var.mllp_ports, 36985)
    error_message = "Port 36985 is reserved by Container Apps and cannot be exposed."
  }

  validation {
    condition     = !contains(var.mllp_ports, 80) && !contains(var.mllp_ports, 443)
    error_message = "Ports 80 and 443 belong to the environment's HTTP ingress and cannot be exposed as TCP ports."
  }

  validation {
    condition     = !contains(var.mllp_ports, var.probes_port)
    error_message = "mllp_ports must not include probes_port: the probe listener is never exposed."
  }
}

variable "ingress_allowed_cidrs" {
  description = "The address ranges allowed to reach the MLLP ports; every other address is denied. Each entry is a plain CIDR range: no spaces, a prefix length with no leading zero. Empty allows every address that can route to the environment, which is private to its virtual network, and is refused when internal_load_balancer_enabled is false. Unless unsafe_allow_mllp_from_any_address is true, it refuses an IPv4 range shorter than /8, an IPv6 range shorter than /32, an IPv4-mapped IPv6 range (::ffff:0:0/96) wider than an IPv4 /8 or holding the whole mapped range, and a list whose IPv4 ranges add up to every IPv4 address. Every other range is trusted as written."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.ingress_allowed_cidrs : can(cidrhost(c, 0)) && can(regex("^[0-9A-Fa-f:.]+/(0|[1-9][0-9]{0,2})$", c))])
    error_message = "Each entry of ingress_allowed_cidrs must be a plain CIDR range, such as 10.20.0.0/16 or 2001:db8::/48: no spaces, and a prefix length with no leading zero."
  }

  # The prefix length is compared as a number, after the entry has parsed as a CIDR range. An entry
  # that does not parse counts as wide (try falls back to false), so this check fails closed.
  validation {
    condition = var.unsafe_allow_mllp_from_any_address || alltrue([
      for c in var.ingress_allowed_cidrs : try(
        strcontains(c, ":")
        ? (
          tonumber(split("/", c)[1]) >= 32
          && !(tonumber(split("/", c)[1]) <= 96 && cidrhost(c, 0) == cidrhost("::ffff:0:0/${split("/", c)[1]}", 0))
          && !(tonumber(split("/", c)[1]) < 104 && strcontains(cidrhost(c, 0), "."))
        )
        : tonumber(split("/", c)[1]) >= 8,
        false
      )
    ])
    error_message = "ingress_allowed_cidrs must not hold a range wider than an IPv4 /8 or an IPv6 /32, nor an IPv4-mapped IPv6 range wider than an IPv4 /8 (0.0.0.0/0, ::/0, 0.0.0.0/1 and ::ffff:0:0/96 are all refused): MLLP has no authentication and carries PHI. Name your senders' ranges, or set unsafe_allow_mllp_from_any_address = true if you mean it."
  }

  # Ranges that are each narrow enough can still add up to every IPv4 address, such as 256 /8s. The
  # sizes are added without removing overlaps, so the sum can only overstate the coverage.
  validation {
    condition = var.unsafe_allow_mllp_from_any_address || try(sum(concat([0], [
      for c in distinct(var.ingress_allowed_cidrs) : (
        strcontains(c, ":")
        ? (strcontains(cidrhost(c, 0), ".") && tonumber(split("/", c)[1]) >= 96 ? pow(2, 128 - tonumber(split("/", c)[1])) : 0)
        : pow(2, 32 - tonumber(split("/", c)[1]))
      )
    ])) < pow(2, 32), false)
    error_message = "The ranges in ingress_allowed_cidrs add up to every IPv4 address: MLLP has no authentication and carries PHI. Name your senders' ranges, or set unsafe_allow_mllp_from_any_address = true if you mean it."
  }
}

variable "unsafe_allow_mllp_from_any_address" {
  description = "Allow ranges in ingress_allowed_cidrs that cover every address or most of it: a /0 (0.0.0.0/0, ::/0), an IPv4 range shorter than /8, an IPv6 range shorter than /32, a wide IPv4-mapped IPv6 range, or a list adding up to every IPv4 address. MLLP has no authentication of its own and carries PHI: with a public environment this opens the engine's intake to the whole internet. Leave it false."
  type        = bool
  default     = false
}

variable "internal_load_balancer_enabled" {
  description = "Give each environment a private address in its virtual network and no public address. Turn it off only when senders reach the engine over the internet, and then name them in ingress_allowed_cidrs: a public environment with no allowed ranges is refused."
  type        = bool
  default     = true

  validation {
    condition     = var.internal_load_balancer_enabled || length(var.ingress_allowed_cidrs) > 0
    error_message = "internal_load_balancer_enabled = false gives the environment a public address, and MLLP has no authentication and carries PHI: name the senders' address ranges in ingress_allowed_cidrs."
  }
}

variable "probes_port" {
  description = "The port of the engine's probe listener (the probes block of pathways.yaml, with host 0.0.0.0), which answers /livez and /readyz."
  type        = number
  default     = 9091

  validation {
    condition     = var.probes_port >= 1 && var.probes_port <= 65535 && floor(var.probes_port) == var.probes_port && var.probes_port != 36985
    error_message = "probes_port must be a whole number from 1 to 65535, and not the reserved port 36985."
  }
}

variable "drain_seconds" {
  description = "The termination grace period: how long the engine gets to stop after SIGTERM before it is killed. On SIGTERM it turns /readyz to draining, closes its sources and gives each hook up to its timeout. 0 to 600, default 30, the platform's own default. Container Apps documents no maximum for this field, and its lifecycle page still says a container is killed 30 seconds after SIGTERM, so a value above 30 is not confirmed to be honored: test it in your environment before you rely on it."
  type        = number
  default     = 30

  validation {
    condition     = var.drain_seconds >= 0 && var.drain_seconds <= 600 && floor(var.drain_seconds) == var.drain_seconds
    error_message = "drain_seconds must be a whole number of seconds from 0 to 600. 600 is this module's own bound: Container Apps documents none, and does not confirm a grace period above 30 seconds."
  }
}

variable "cpu" {
  description = "vCPU for the engine container. memory must be twice this many Gi."
  type        = number
  default     = 1
}

variable "memory" {
  description = "Memory for the engine container, such as 2Gi."
  type        = string
  default     = "2Gi"
}

variable "environment_variables" {
  description = "Plain environment variables for the engine and the migrate job, such as the settings pathways.yaml reads with env. Never a secret: use encryption_key_secrets or a Key Vault secret."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.environment_variables) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k))])
    error_message = "Each environment variable name must be letters, digits and underscores, not starting with a digit."
  }

  validation {
    condition     = !contains(keys(var.environment_variables), "PATHWAYS_DATABASE_URL")
    error_message = "PATHWAYS_DATABASE_URL is set by the module from Key Vault; do not pass it as a plain variable."
  }
}

variable "encryption_key_secrets" {
  description = "The master keys, by environment variable name (such as PATHWAYS_KEY_2026_11) to the name of a secret you put in this module's Key Vault. The module never generates or reads a key: create each secret before the app's revision starts."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.encryption_key_secrets) : can(regex("^[A-Z][A-Z0-9_]*$", k))])
    error_message = "Each key of encryption_key_secrets must be an environment variable name in capitals, digits and underscores."
  }

  validation {
    condition     = alltrue([for v in values(var.encryption_key_secrets) : can(regex("^[0-9A-Za-z-]{1,127}$", v))])
    error_message = "Each value of encryption_key_secrets must be a Key Vault secret name: 1 to 127 letters, digits and hyphens."
  }

  validation {
    condition     = !contains(values(var.encryption_key_secrets), "database-url")
    error_message = "The secret name database-url belongs to the module."
  }
}

variable "container_registry_server" {
  description = "A private registry the images are pulled from with the module's managed identity, such as an Azure Container Registry login server. Grant that identity AcrPull. Null pulls anonymously, as from ghcr.io."
  type        = string
  default     = null
}

variable "app_start_args" {
  description = "Arguments for the engine container. Null keeps the image's own command, pathways start -C /project, which applies the expand steps of a schema change itself; pass [\"start\", \"-C\", \"/project\", \"--no-migrate\"] to leave every schema change to the migrate job."
  type        = list(string)
  default     = null
}

variable "migrate_args" {
  description = "Arguments for the migrate job's container."
  type        = list(string)
  default     = ["migrate", "-C", "/project"]
}

variable "migrate_timeout_seconds" {
  description = "How long one run of the migrate job may take."
  type        = number
  default     = 1800

  validation {
    condition     = var.migrate_timeout_seconds >= 60 && floor(var.migrate_timeout_seconds) == var.migrate_timeout_seconds
    error_message = "migrate_timeout_seconds must be a whole number of at least 60."
  }
}

variable "log_retention_days" {
  description = "How long the Log Analytics workspace keeps the engine's logs: 30 to 730 days."
  type        = number
  default     = 90

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "log_retention_days must be a whole number from 30 to 730."
  }
}

variable "postgres" {
  description = <<-EOT
    The PostgreSQL flexible server. It has private access only: delegated_subnet_id is a subnet
    delegated to Microsoft.DBforPostgreSQL/flexibleServers, and private_dns_zone_id a private DNS zone
    ending in .postgres.database.azure.com linked to the virtual network. Password and Microsoft
    Entra authentication are both on; entra_administrator, when set, makes that principal an Entra
    administrator of the server.
  EOT
  type = object({
    delegated_subnet_id            = string
    private_dns_zone_id            = string
    version                        = optional(string, "16")
    sku_name                       = optional(string, "GP_Standard_D2ds_v5")
    storage_mb                     = optional(number, 32768)
    backup_retention_days          = optional(number, 35)
    geo_redundant_backup_enabled   = optional(bool, false)
    zone                           = optional(string)
    high_availability_standby_zone = optional(string)
    entra_administrator = optional(object({
      object_id      = string
      principal_name = string
      principal_type = string
    }))
  })

  validation {
    condition     = var.postgres.backup_retention_days >= 7 && var.postgres.backup_retention_days <= 35
    error_message = "postgres.backup_retention_days must be from 7 to 35."
  }

  validation {
    condition     = can(regex("(?i)\\.postgres\\.database\\.azure\\.com$", var.postgres.private_dns_zone_id))
    error_message = "postgres.private_dns_zone_id must be a private DNS zone whose name ends in .postgres.database.azure.com."
  }

  validation {
    condition     = var.postgres.entra_administrator == null || contains(["User", "Group", "ServicePrincipal"], try(var.postgres.entra_administrator.principal_type, ""))
    error_message = "postgres.entra_administrator.principal_type must be User, Group or ServicePrincipal."
  }
}

variable "key_vault" {
  description = <<-EOT
    Key Vault networking. The vault denies every network, and the apps and the machine that applies
    (Terraform writes the database-url secret) both need a way in, so one of two is required: a
    private endpoint (private_endpoint_subnet_id and private_dns_zone_id, a zone named
    privatelink.vaultcore.azure.net), which the apps use from the virtual network, or
    public_network_access_enabled with allowed_ip_ranges naming the runner and the environments'
    outbound addresses. Container Apps is not a trusted Azure service, so the AzureServices bypass
    does not let the apps in.
  EOT
  type = object({
    public_network_access_enabled = optional(bool, false)
    allowed_ip_ranges             = optional(list(string), [])
    private_endpoint_subnet_id    = optional(string)
    private_dns_zone_id           = optional(string)
    soft_delete_retention_days    = optional(number, 90)
  })
  default = {}

  validation {
    condition     = (var.key_vault.private_endpoint_subnet_id == null) == (var.key_vault.private_dns_zone_id == null)
    error_message = "key_vault.private_endpoint_subnet_id and key_vault.private_dns_zone_id are set together or not at all."
  }

  validation {
    condition     = var.key_vault.soft_delete_retention_days >= 7 && var.key_vault.soft_delete_retention_days <= 90
    error_message = "key_vault.soft_delete_retention_days must be from 7 to 90."
  }

  validation {
    condition     = length(var.key_vault.allowed_ip_ranges) == 0 || var.key_vault.public_network_access_enabled
    error_message = "key_vault.allowed_ip_ranges has no effect unless key_vault.public_network_access_enabled is true."
  }

  validation {
    condition     = var.key_vault.private_endpoint_subnet_id != null || (var.key_vault.public_network_access_enabled && length(var.key_vault.allowed_ip_ranges) > 0)
    error_message = "Nothing could reach the Key Vault: the apps could not read their secrets and the apply could not write database-url. Set key_vault.private_endpoint_subnet_id and key_vault.private_dns_zone_id (recommended), or set key_vault.public_network_access_enabled = true with key_vault.allowed_ip_ranges naming the runner and the environments' outbound addresses."
  }
}
