---
id: inputs-and-outputs
title: Inputs and outputs
sidebar_label: Inputs and outputs
description: "Every input and output of the root module, with its type, its default and what the plan refuses, generated from the code."
---

# Inputs and outputs

The root module composes the modules under `modules/`: this is the page to read when you call `source = "github.com/cosyte/terraform-azurerm-pathways"`. Each module has a page of its own as well.

This page is generated from the code in the repository root by `scripts/docs.sh`, and CI fails when it no longer matches. Change `variables.tf` or its `outputs.tf`, then run `scripts/docs.sh`.

## Requirements

| Name | Version |
| --- | --- |
| `terraform` | `>= 1.9.0` |
| `azapi` | `>= 2.0.0, < 3.0.0` |
| `azurerm` | `>= 4.42.0, < 5.0.0` |
| `random` | `>= 3.6.0, < 4.0.0` |

## Modules

| Name | Source |
| --- | --- |
| `identity` | `./modules/identity` |
| `logs` | `./modules/logs` |
| `database` | `./modules/database` |
| `key_vault` | `./modules/key_vault` |
| `container_apps` | `./modules/container_apps` |
| `storage` | `./modules/storage` |

## Inputs

23 inputs, 6 of them required. The required ones come first, then the rest by name.

### `location`

Required.

The Azure region, such as eastus2.

Type:

```hcl
string
```

### `mllp_ports`

Required.

The TCP ports the engine's MLLP sources listen on, each exposed on the same port number. The first is the app's main ingress port, the rest are additional port mappings: six at most (one plus five), never 80 or 443, never the reserved port 36985, never the probe port. Every exposed port, main or additional, is unique across the environment, and each slot has an environment of its own.

Type:

```hcl
list(number)
```

The plan refuses a value that breaks one of these rules, with its message:

- mllp\_ports must hold 1 to 6 ports: Container Apps exposes one main port and at most five additional TCP ports.
- Each MLLP port must be a whole number from 1 to 65535.
- mllp\_ports must not repeat a port: an exposed TCP port, main or additional, is unique across the environment.
- Port 36985 is reserved by Container Apps and cannot be exposed.
- Ports 80 and 443 belong to the environment's HTTP ingress and cannot be exposed as TCP ports.
- mllp\_ports must not include probes\_port: the probe listener is never exposed.

### `name`

Required.

Short name every resource name is built from: 3 to 16 lowercase letters, digits and hyphens, starting with a letter. The Key Vault and the PostgreSQL server names are global in Azure, so pick one nobody else uses.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen.

### `postgres`

Required.

The PostgreSQL flexible server. It has private access only: delegated\_subnet\_id is a subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers, and private\_dns\_zone\_id a private DNS zone ending in .postgres.database.azure.com linked to the virtual network. Password and Microsoft Entra authentication are both on; entra\_administrator, when set, makes that principal an Entra administrator of the server.

Type:

```hcl
object({
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
```

The plan refuses a value that breaks one of these rules, with its message:

- postgres.backup\_retention\_days must be from 7 to 35.
- postgres.private\_dns\_zone\_id must be a private DNS zone whose name ends in .postgres.database.azure.com.
- postgres.entra\_administrator.principal\_type must be User, Group or ServicePrincipal.

### `resource_group_name`

Required.

The existing resource group everything is created in.

Type:

```hcl
string
```

### `slots`

Required.

The deployment slots, keyed by a slot name of 1 to 5 lowercase letters or digits (such as blue and green). Each slot gets its own Container Apps environment, app and migrate job, on its own infrastructure subnet, so the two slots can expose the same MLLP ports at once: TCP ports are unique across one environment. Each subnet must be delegated to Microsoft.App/environments and be at least a /27. The image must be pinned by digest (registry/repository:tag@sha256:...).

Type:

```hcl
map(object({
  image                    = string
  infrastructure_subnet_id = string
}))
```

The plan refuses a value that breaks one of these rules, with its message:

- slots must name one slot, or two for blue and green.
- Each slot name must be 1 to 5 lowercase letters or digits, starting with a letter.
- Each slot's image must be pinned by digest: registry/repository:tag@sha256:\<64 hex digits\>.
- Each slot needs its own infrastructure subnet: one subnet holds one Container Apps environment.

### `app_start_args`

Optional.

Arguments for the engine container. Null keeps the image's own command, pathways start -C /project, which applies the expand steps of a schema change itself; pass \["start", "-C", "/project", "--no-migrate"\] to leave every schema change to the migrate job.

Type:

```hcl
list(string)
```

Default: `null`

### `container_registry_server`

Optional.

A private registry the images are pulled from with the module's managed identity, such as an Azure Container Registry login server. Grant that identity AcrPull. Null pulls anonymously, as from ghcr.io.

Type:

```hcl
string
```

Default: `null`

### `cpu`

Optional.

vCPU for the engine container. memory must be twice this many Gi.

Type:

```hcl
number
```

Default: `1`

### `drain_seconds`

Optional.

The termination grace period: how long the engine gets to stop after SIGTERM before it is killed. On SIGTERM it turns /readyz to draining, closes its sources and gives each hook up to its timeout. 0 to 600, default 30, the platform's own default. Container Apps documents no maximum for this field, and its lifecycle page still says a container is killed 30 seconds after SIGTERM, so a value above 30 is not confirmed to be honored: test it in your environment before you rely on it.

Type:

```hcl
number
```

Default: `30`

The plan refuses a value that breaks this rule, with this message:

- drain\_seconds must be a whole number of seconds from 0 to 600. 600 is this module's own bound: Container Apps documents none, and does not confirm a grace period above 30 seconds.

### `encryption_key_secrets`

Optional.

The master keys, by environment variable name (such as PATHWAYS\_KEY\_2026\_11) to the name of a secret you put in this module's Key Vault. The module never generates or reads a key: create each secret before the app's revision starts.

Type:

```hcl
map(string)
```

Default: `{}`

The plan refuses a value that breaks one of these rules, with its message:

- Each key of encryption\_key\_secrets must be an environment variable name in capitals, digits and underscores.
- Each value of encryption\_key\_secrets must be a Key Vault secret name: 1 to 127 letters, digits and hyphens.
- The secret name database-url belongs to the module.

### `environment_variables`

Optional.

Plain environment variables for the engine and the migrate job, such as the settings pathways.yaml reads with env. Never a secret: use encryption\_key\_secrets or a Key Vault secret.

Type:

```hcl
map(string)
```

Default: `{}`

The plan refuses a value that breaks one of these rules, with its message:

- Each environment variable name must be letters, digits and underscores, not starting with a digit.
- PATHWAYS\_DATABASE\_URL is set by the module from Key Vault; do not pass it as a plain variable.

### `ingress_allowed_cidrs`

Optional.

The address ranges allowed to reach the MLLP ports; every other address is denied. Each entry is a plain CIDR range: no spaces, a prefix length with no leading zero. Empty allows every address that can route to the environment, which is private to its virtual network, and is refused when internal\_load\_balancer\_enabled is false. Unless unsafe\_allow\_mllp\_from\_any\_address is true, it refuses an IPv4 range shorter than /8, an IPv6 range shorter than /32, an IPv4-mapped IPv6 range (::ffff:0:0/96) wider than an IPv4 /8 or holding the whole mapped range, and a list whose IPv4 ranges add up to every IPv4 address. Every other range is trusted as written.

Type:

```hcl
list(string)
```

Default: `[]`

The plan refuses a value that breaks one of these rules, with its message:

- Each entry of ingress\_allowed\_cidrs must be a plain CIDR range, such as 10.20.0.0/16 or 2001:db8::/48: no spaces, and a prefix length with no leading zero.
- ingress\_allowed\_cidrs must not hold a range wider than an IPv4 /8 or an IPv6 /32, nor an IPv4-mapped IPv6 range wider than an IPv4 /8 (0.0.0.0/0, ::/0, 0.0.0.0/1 and ::ffff:0:0/96 are all refused): MLLP has no authentication and carries PHI. Name your senders' ranges, or set unsafe\_allow\_mllp\_from\_any\_address = true if you mean it.
- The ranges in ingress\_allowed\_cidrs add up to every IPv4 address: MLLP has no authentication and carries PHI. Name your senders' ranges, or set unsafe\_allow\_mllp\_from\_any\_address = true if you mean it.

### `internal_load_balancer_enabled`

Optional.

Give each environment a private address in its virtual network and no public address. Turn it off only when senders reach the engine over the internet, and then name them in ingress\_allowed\_cidrs: a public environment with no allowed ranges is refused.

Type:

```hcl
bool
```

Default: `true`

The plan refuses a value that breaks this rule, with this message:

- internal\_load\_balancer\_enabled = false gives the environment a public address, and MLLP has no authentication and carries PHI: name the senders' address ranges in ingress\_allowed\_cidrs.

### `key_vault`

Optional.

Key Vault networking. The vault denies every network, and the apps and the machine that applies (Terraform writes the database-url secret) both need a way in, so one of two is required: a private endpoint (private\_endpoint\_subnet\_id and private\_dns\_zone\_id, a zone named privatelink.vaultcore.azure.net), which the apps use from the virtual network, or public\_network\_access\_enabled with allowed\_ip\_ranges naming the runner and the environments' outbound addresses. Container Apps is not a trusted Azure service, so the AzureServices bypass does not let the apps in.

Type:

```hcl
object({
  public_network_access_enabled = optional(bool, false)
  allowed_ip_ranges             = optional(list(string), [])
  private_endpoint_subnet_id    = optional(string)
  private_dns_zone_id           = optional(string)
  soft_delete_retention_days    = optional(number, 90)
})
```

Default: `{}`

The plan refuses a value that breaks one of these rules, with its message:

- key\_vault.private\_endpoint\_subnet\_id and key\_vault.private\_dns\_zone\_id are set together or not at all.
- key\_vault.soft\_delete\_retention\_days must be from 7 to 90.
- key\_vault.allowed\_ip\_ranges has no effect unless key\_vault.public\_network\_access\_enabled is true.
- Nothing could reach the Key Vault: the apps could not read their secrets and the apply could not write database-url. Set key\_vault.private\_endpoint\_subnet\_id and key\_vault.private\_dns\_zone\_id (recommended), or set key\_vault.public\_network\_access\_enabled = true with key\_vault.allowed\_ip\_ranges naming the runner and the environments' outbound addresses.

### `log_retention_days`

Optional.

How long the Log Analytics workspace keeps the engine's logs: 30 to 730 days.

Type:

```hcl
number
```

Default: `90`

The plan refuses a value that breaks this rule, with this message:

- log\_retention\_days must be a whole number from 30 to 730.

### `memory`

Optional.

Memory for the engine container, such as 2Gi.

Type:

```hcl
string
```

Default: `"2Gi"`

### `migrate_args`

Optional.

Arguments for the migrate job's container.

Type:

```hcl
list(string)
```

Default: `["migrate", "-C", "/project"]`

### `migrate_timeout_seconds`

Optional.

How long one run of the migrate job may take.

Type:

```hcl
number
```

Default: `1800`

The plan refuses a value that breaks this rule, with this message:

- migrate\_timeout\_seconds must be a whole number of at least 60.

### `probes_port`

Optional.

The port of the engine's probe listener (the probes block of pathways.yaml, with host 0.0.0.0), which answers /livez and /readyz.

Type:

```hcl
number
```

Default: `9091`

The plan refuses a value that breaks this rule, with this message:

- probes\_port must be a whole number from 1 to 65535, and not the reserved port 36985.

### `storage`

Optional.

An optional storage account for files partners send and fetch over SFTP, and for the engine's own blobs: off unless enabled is true. The modules/storage README says what each setting does. The account has hierarchical namespace and SFTP on, no public network access, a blob private endpoint (private\_endpoint\_subnet\_id and private\_dns\_zone\_id, a zone named privatelink.blob.core.windows.net, are required: the engine reads through it), its shared keys off, and, unless customer\_managed\_key\_enabled is false, a key from this module's Key Vault. public\_network\_access\_enabled with allowed\_ip\_ranges opens it to SFTP clients at named public IPv4 ranges. Each user in sftp\_users signs in with an SSH key, never a password, and reaches only its own container, sftp-\<user\>. The engine's identity gets blob data access on each container, and the app gets AZURE\_CLIENT\_ID, PATHWAYS\_AZBLOB\_ACCOUNT, PATHWAYS\_AZBLOB\_CONTAINER and PATHWAYS\_SFTP\_\<USER\>\_CONTAINER for its channels to read.

Type:

```hcl
object({
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
```

Default: `{}`

The plan refuses a value that breaks one of these rules, with its message:

- storage needs private\_endpoint\_subnet\_id and private\_dns\_zone\_id (the privatelink.blob.core.windows.net zone): the engine reads the account through its private endpoint, since Azure Storage's IP rules do not apply to traffic from the same region.
- storage.account\_name must be 3 to 24 lowercase letters and digits.
- storage.container\_name must be 3 to 63 lowercase letters, digits and single hyphens, starting and ending with a letter or digit, and must not start with sftp-: each SFTP user's container is sftp-\<user\>.
- storage.replication\_type must be LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS.
- storage.sftp\_users needs storage.sftp\_enabled = true: a local user can sign in only over SFTP.
- storage.public\_network\_access\_enabled = true needs storage.allowed\_ip\_ranges naming the SFTP clients' public addresses: the account carries PHI.
- storage.allowed\_ip\_ranges has no effect unless storage.public\_network\_access\_enabled is true.
- Each entry of storage.allowed\_ip\_ranges must be a public IPv4 address or range, such as 203.0.113.7 or 198.51.100.0/24: no spaces, no leading zero in the prefix, and no IPv6 (Azure Storage's IP rules take IPv4 only).
- Azure Storage does not take a /31 or /32 range in an IP rule: write each address in storage.allowed\_ip\_ranges on its own, without a prefix.
- storage.allowed\_ip\_ranges must not hold a range wider than a /8 (0.0.0.0/0 included): the account carries PHI. Name your SFTP clients' ranges.
- The ranges in storage.allowed\_ip\_ranges add up to more addresses than one /8 (16,777,216): the account carries PHI. Name your SFTP clients' ranges.
- storage.allowed\_ip\_ranges must not hold or overlap a private range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16): Azure Storage's IP rules take public addresses only. Clients in your virtual network reach the account through its private endpoint.
- storage.soft\_delete\_retention\_days must be a whole number from 1 to 365.
- Each storage.sftp\_users name must be 3 to 32 lowercase letters and digits, starting with a letter.
- Each storage.sftp\_users entry needs 1 to 10 SSH public keys: a user signs in with a key, never a password.
- Each SSH key in storage.sftp\_users must be one public key on one line, in OpenSSH form: its type (such as ssh-rsa), its base64 data and an optional comment. Never a private key.
- Each storage.sftp\_users entry's permissions must be one or more of create, write, list, read and delete.
- With storage enabled, the module sets AZURE\_CLIENT\_ID, PATHWAYS\_AZBLOB\_ACCOUNT, PATHWAYS\_AZBLOB\_CONTAINER and PATHWAYS\_SFTP\_\<USER\>\_CONTAINER on the app: do not pass them in environment\_variables.

### `tags`

Optional.

Tags added to every resource that takes them.

Type:

```hcl
map(string)
```

Default: `{}`

### `unsafe_allow_mllp_from_any_address`

Optional.

Allow ranges in ingress\_allowed\_cidrs that cover every address or most of it: a /0 (0.0.0.0/0, ::/0), an IPv4 range shorter than /8, an IPv6 range shorter than /32, a wide IPv4-mapped IPv6 range, or a list adding up to every IPv4 address. MLLP has no authentication of its own and carries PHI: with a public environment this opens the engine's intake to the whole internet. Leave it false.

Type:

```hcl
bool
```

Default: `false`

## Outputs

7 outputs, by name.

### `identity`

The user-assigned managed identity the apps and jobs run as: its resource id, client id and principal id. Grant it AcrPull on a private registry.

### `key_vault`

The Key Vault's id, name and URI. Put each master key named in encryption\_key\_secrets here.

### `log_analytics_workspace_id`

The Log Analytics workspace the environments send logs to.

### `mllp_ports`

The MLLP ports each slot exposes.

### `postgres`

The PostgreSQL server's id, host name, database and administrator login. The password is only in the database-url secret.

### `slots`

Per slot: the environment's id and static IP address (where senders connect for MLLP), the app's id and name, and the migrate job's name.

### `storage`

With storage on: the account's id and name, the engine's container, the SFTP host (port 22), each SFTP user's sign-in name and container, and the plain environment variables the app gets for its channels. Null with storage off.
