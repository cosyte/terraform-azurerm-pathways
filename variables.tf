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
  description = "The TCP ports the engine's MLLP sources listen on, each exposed on the same port number. The first is the app's main ingress port, the rest are additional port mappings: six at most (one plus five), never 80 or 443, never the reserved port 36985, never the probe port. Every exposed port, main or additional, is unique across the environment, and each slot has an environment of its own. Empty only with http_port set: the app takes either MLLP over TCP ingress or HTTP, not both."
  type        = list(number)
  default     = []

  validation {
    condition     = length(var.mllp_ports) <= 6
    error_message = "mllp_ports must hold at most 6 ports: Container Apps exposes one main port and at most five additional TCP ports."
  }

  validation {
    condition     = (length(var.mllp_ports) > 0) != (var.http_port != null)
    error_message = "Set mllp_ports or http_port, one of the two: the app's ingress is either TCP for MLLP or HTTP, not both and not neither."
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

variable "http_port" {
  description = "The port the engine's HTTP source listens on, for an app whose only intake is HTTP. The app then gets HTTP ingress in place of TCP: Container Apps ends TLS on port 443 of the app's address and passes plain HTTP to this port inside the environment, and plain HTTP from outside is refused (allowInsecure is false). ingress_allowed_cidrs guards it as it guards MLLP. Null, the default, for MLLP over TCP ingress (mllp_ports)."
  type        = number
  default     = null

  validation {
    condition     = var.http_port == null || try(var.http_port >= 1 && var.http_port <= 65535 && floor(var.http_port) == var.http_port && var.http_port != 36985, false)
    error_message = "http_port must be a whole number from 1 to 65535, and not the reserved port 36985."
  }

  validation {
    condition     = var.http_port == null || try(var.http_port != var.probes_port, false)
    error_message = "http_port must not be probes_port: the probe listener is never exposed."
  }
}

variable "standby_replica" {
  description = "Run a second replica of the app as the engine's warm standby. Both replicas start with --standby: the first to ask takes the engine lease and runs every channel, the other holds no lease, opens no listener and answers /readyz 503 standby, so the ingress sends it nothing, and takes over within about 20 seconds once the engine holding the lease stops. Only one engine works at a time: the lease, not the replica count, decides. Off by default: one replica."
  type        = bool
  default     = false
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
    administrator of the server. Null with existing_postgres, for a server you already run.
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
  default = null

  # Each check reads the object through try, so a null postgres (existing_postgres instead) passes
  # here and is checked by existing_postgres.
  validation {
    condition     = var.postgres == null || try(var.postgres.backup_retention_days >= 7 && var.postgres.backup_retention_days <= 35, false)
    error_message = "postgres.backup_retention_days must be from 7 to 35."
  }

  validation {
    condition     = var.postgres == null || can(regex("(?i)\\.postgres\\.database\\.azure\\.com$", var.postgres.private_dns_zone_id))
    error_message = "postgres.private_dns_zone_id must be a private DNS zone whose name ends in .postgres.database.azure.com."
  }

  validation {
    condition     = var.postgres == null || try(var.postgres.entra_administrator == null, false) || contains(["User", "Group", "ServicePrincipal"], try(var.postgres.entra_administrator.principal_type, ""))
    error_message = "postgres.entra_administrator.principal_type must be User, Group or ServicePrincipal."
  }
}

variable "existing_postgres" {
  description = <<-EOT
    A PostgreSQL server you already run, in place of the one the module makes. database_url_secret_name
    names a secret you put in this module's Key Vault yourself, holding the engine's database URL
    (the server must take TLS, and the app must reach it from its environment's subnet). The module
    makes no server, writes no database-url secret and never sees the URL, so it stays out of the
    Terraform state. Set postgres or existing_postgres, one of the two.
  EOT
  type = object({
    database_url_secret_name = string
  })
  default = null

  validation {
    condition     = (var.postgres == null) != (var.existing_postgres == null)
    error_message = "Set postgres, for a server the module makes, or existing_postgres, for one you already run: one of the two."
  }

  validation {
    condition     = var.existing_postgres == null || can(regex("^[0-9A-Za-z-]{1,127}$", var.existing_postgres.database_url_secret_name))
    error_message = "existing_postgres.database_url_secret_name must be a Key Vault secret name: 1 to 127 letters, digits and hyphens."
  }

  validation {
    condition     = var.existing_postgres == null || !contains(values(var.encryption_key_secrets), try(var.existing_postgres.database_url_secret_name, ""))
    error_message = "existing_postgres.database_url_secret_name must not be the name of a master key's secret in encryption_key_secrets."
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

variable "storage" {
  description = <<-EOT
    An optional storage account for files partners send and fetch over SFTP, and for the engine's own
    blobs: off unless enabled is true. The modules/storage README says what each setting does. The
    account has hierarchical namespace and SFTP on, no public network access, a blob private endpoint
    (private_endpoint_subnet_id and private_dns_zone_id, a zone named
    privatelink.blob.core.windows.net, are required: the engine reads through it), its shared keys
    off, and, unless customer_managed_key_enabled is false, a key from this module's Key Vault.
    public_network_access_enabled with allowed_ip_ranges opens it to SFTP clients at named public
    IPv4 ranges. Each user in sftp_users signs in with an SSH key, never a password, and reaches only
    its own container, sftp-<user>. The engine's identity gets blob data access on each container,
    and the app gets AZURE_CLIENT_ID, PATHWAYS_AZBLOB_ACCOUNT, PATHWAYS_AZBLOB_CONTAINER and
    PATHWAYS_SFTP_<USER>_CONTAINER for its channels to read.
  EOT
  type = object({
    enabled                       = optional(bool, false)
    account_name                  = optional(string)
    container_name                = optional(string, "pathways")
    replication_type              = optional(string, "LRS")
    sftp_enabled                  = optional(bool, true)
    public_network_access_enabled = optional(bool, false)
    allowed_ip_ranges             = optional(list(string), [])
    private_endpoint_subnet_id    = optional(string)
    private_dns_zone_id           = optional(string)
    customer_managed_key_enabled  = optional(bool, true)
    soft_delete_retention_days    = optional(number, 7)
    sftp_users = optional(map(object({
      ssh_public_keys = list(string)
      permissions     = optional(list(string), ["create", "write", "list"])
    })), {})
  })
  default = {}

  validation {
    condition     = !var.storage.enabled || (var.storage.private_endpoint_subnet_id != null && var.storage.private_dns_zone_id != null)
    error_message = "storage needs private_endpoint_subnet_id and private_dns_zone_id (the privatelink.blob.core.windows.net zone): the engine reads the account through its private endpoint, since Azure Storage's IP rules do not apply to traffic from the same region."
  }

  validation {
    condition     = var.storage.account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage.account_name))
    error_message = "storage.account_name must be 3 to 24 lowercase letters and digits."
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.storage.container_name)) && !strcontains(var.storage.container_name, "--") && !startswith(var.storage.container_name, "sftp-")
    error_message = "storage.container_name must be 3 to 63 lowercase letters, digits and single hyphens, starting and ending with a letter or digit, and must not start with sftp-: each SFTP user's container is sftp-<user>."
  }

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.storage.replication_type)
    error_message = "storage.replication_type must be LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
  }

  validation {
    condition     = var.storage.sftp_enabled || length(var.storage.sftp_users) == 0
    error_message = "storage.sftp_users needs storage.sftp_enabled = true: a local user can sign in only over SFTP."
  }

  validation {
    condition     = !var.storage.public_network_access_enabled || length(var.storage.allowed_ip_ranges) > 0
    error_message = "storage.public_network_access_enabled = true needs storage.allowed_ip_ranges naming the SFTP clients' public addresses: the account carries PHI."
  }

  validation {
    condition     = length(var.storage.allowed_ip_ranges) == 0 || var.storage.public_network_access_enabled
    error_message = "storage.allowed_ip_ranges has no effect unless storage.public_network_access_enabled is true."
  }

  validation {
    condition = alltrue([
      for c in var.storage.allowed_ip_ranges :
      can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}(/[1-9][0-9]?)?$", c)) && can(cidrhost(strcontains(c, "/") ? c : "${c}/32", 0))
    ])
    error_message = "Each entry of storage.allowed_ip_ranges must be a public IPv4 address or range, such as 203.0.113.7 or 198.51.100.0/24: no spaces, no leading zero in the prefix, and no IPv6 (Azure Storage's IP rules take IPv4 only)."
  }

  validation {
    condition     = alltrue([for c in var.storage.allowed_ip_ranges : !can(regex("/3[12]$", c))])
    error_message = "Azure Storage does not take a /31 or /32 range in an IP rule: write each address in storage.allowed_ip_ranges on its own, without a prefix."
  }

  # The prefix is compared as a number once the entry has parsed; an entry that does not parse counts
  # as wide (try falls back to false), so this check fails closed.
  validation {
    condition = alltrue([
      for c in var.storage.allowed_ip_ranges : try(!strcontains(c, "/") || tonumber(split("/", c)[1]) >= 8, false)
    ])
    error_message = "storage.allowed_ip_ranges must not hold a range wider than a /8 (0.0.0.0/0 included): the account carries PHI. Name your SFTP clients' ranges."
  }

  # Ranges each narrow enough can still add up to most of the internet: since private ranges are
  # refused, a list that covers every public address never reaches 2^32. So the whole list may hold
  # no more addresses than one /8 (2^24), well under the public space and far more than any set of
  # SFTP partners needs. Overlaps are counted twice, so the sum can only overstate the coverage.
  validation {
    condition = try(sum(concat([0], [
      for c in distinct(var.storage.allowed_ip_ranges) : strcontains(c, "/") ? pow(2, 32 - tonumber(split("/", c)[1])) : 1
    ])) <= pow(2, 24), false)
    error_message = "The ranges in storage.allowed_ip_ranges add up to more addresses than one /8 (16,777,216): the account carries PHI. Name your SFTP clients' ranges."
  }

  # Two ranges overlap when the wider one holds the narrower one's first address.
  validation {
    condition = alltrue(flatten([
      for c in var.storage.allowed_ip_ranges : [
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
    error_message = "storage.allowed_ip_ranges must not hold or overlap a private range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16): Azure Storage's IP rules take public addresses only. Clients in your virtual network reach the account through its private endpoint."
  }

  validation {
    condition     = var.storage.soft_delete_retention_days >= 1 && var.storage.soft_delete_retention_days <= 365 && floor(var.storage.soft_delete_retention_days) == var.storage.soft_delete_retention_days
    error_message = "storage.soft_delete_retention_days must be a whole number from 1 to 365."
  }

  validation {
    condition     = alltrue([for u in keys(var.storage.sftp_users) : can(regex("^[a-z][a-z0-9]{2,31}$", u))])
    error_message = "Each storage.sftp_users name must be 3 to 32 lowercase letters and digits, starting with a letter."
  }

  validation {
    condition     = alltrue([for u in values(var.storage.sftp_users) : length(u.ssh_public_keys) >= 1 && length(u.ssh_public_keys) <= 10])
    error_message = "Each storage.sftp_users entry needs 1 to 10 SSH public keys: a user signs in with a key, never a password."
  }

  validation {
    condition = alltrue(flatten([
      for u in values(var.storage.sftp_users) : [
        for k in u.ssh_public_keys : can(regex("^[a-z][a-z0-9.@-]* [A-Za-z0-9+/]+={0,3}( [^\\r\\n]*)?$", k)) && !strcontains(upper(k), "PRIVATE KEY")
      ]
    ]))
    error_message = "Each SSH key in storage.sftp_users must be one public key on one line, in OpenSSH form: its type (such as ssh-rsa), its base64 data and an optional comment. Never a private key."
  }

  validation {
    condition = alltrue([
      for u in values(var.storage.sftp_users) :
      length(u.permissions) >= 1 && alltrue([for p in u.permissions : contains(["create", "write", "list", "read", "delete"], p)])
    ])
    error_message = "Each storage.sftp_users entry's permissions must be one or more of create, write, list, read and delete."
  }

  validation {
    condition = !var.storage.enabled || alltrue([
      for k in keys(var.environment_variables) :
      !contains(["AZURE_CLIENT_ID", "PATHWAYS_AZBLOB_ACCOUNT", "PATHWAYS_AZBLOB_CONTAINER"], k) && !can(regex("^PATHWAYS_SFTP_.*_CONTAINER$", k))
    ])
    error_message = "With storage enabled, the module sets AZURE_CLIENT_ID, PATHWAYS_AZBLOB_ACCOUNT, PATHWAYS_AZBLOB_CONTAINER and PATHWAYS_SFTP_<USER>_CONTAINER on the app: do not pass them in environment_variables."
  }
}
