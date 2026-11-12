---
id: module-container-apps
title: The container_apps module
sidebar_label: container_apps
description: "Every input and output of the container_apps module, generated from its code."
---

# The container_apps module

Per slot: a Container Apps environment on its own infrastructure subnet, the Pathways app with TCP ingress for MLLP (one main port and up to five additional ports, with the address guard on `ingress_allowed_cidrs`), startup, liveness and readiness probes on the engine's probe listener, and a Container Apps job that runs `pathways migrate`. The app and the job read the database URL and each master key from Key Vault through `secretRef`, as the managed identity you pass.

Use it on its own with `source = "github.com/cosyte/terraform-azurerm-pathways//modules/container_apps"`.

This page is generated from the code in `modules/container_apps/` by `scripts/docs.sh`, and CI fails when it no longer matches. Change `modules/container_apps/variables.tf` or its `outputs.tf`, then run `scripts/docs.sh`.

## Requirements

| Name | Version |
| --- | --- |
| `terraform` | `>= 1.9.0` |
| `azapi` | `>= 2.0.0, < 3.0.0` |
| `azurerm` | `>= 4.42.0, < 5.0.0` |

## Resources

- `azapi_resource.app`
- `azurerm_container_app_environment.this`
- `azurerm_container_app_job.migrate`
- `data.azurerm_resource_group.this`

## Inputs

23 inputs, 9 of them required. The required ones come first, then the rest by name.

### `database_url_secret_id`

Required.

The versionless id of the Key Vault secret that holds the engine's database URL. The app and the migrate job read it as PATHWAYS\_DATABASE\_URL.

Type:

```hcl
string
```

### `identity_id`

Required.

The resource id of the user-assigned managed identity the apps and the jobs run as. It must hold Key Vault Secrets User on the vault before a revision starts, and AcrPull on container\_registry\_server when that is set.

Type:

```hcl
string
```

### `key_vault_uri`

Required.

The URI of the Key Vault the secrets are read from, ending in a slash, such as https://kv-example.vault.azure.net/. Each secret named in encryption\_key\_secrets is read from \<key\_vault\_uri\>secrets/\<name\>.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- key\_vault\_uri must end in a slash, as a Key Vault's vault\_uri does.

### `location`

Required.

The Azure region, such as eastus2.

Type:

```hcl
string
```

### `log_analytics_workspace_id`

Required.

The Log Analytics workspace every environment sends its logs to.

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

Short name the environment, app and job names are built from (cae-\<name\>-\<slot\>, \<name\>-\<slot\>, \<name\>-\<slot\>-migrate): 3 to 16 lowercase letters, digits and hyphens, starting with a letter.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen.

### `resource_group_name`

Required.

The existing resource group the environments, apps and jobs are created in.

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

A private registry the images are pulled from with the managed identity at identity\_id, such as an Azure Container Registry login server. Grant that identity AcrPull. Null pulls anonymously, as from ghcr.io.

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

The master keys, by environment variable name (such as PATHWAYS\_KEY\_2026\_11) to the name of a secret you put in the Key Vault at key\_vault\_uri. The module never generates or reads a key: create each secret before the app's revision starts.

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

2 outputs, by name.

### `mllp_ports`

The MLLP ports each slot exposes.

### `slots`

Per slot: the environment's id and static IP address (where senders connect for MLLP), the app's id and name, and the migrate job's name.
