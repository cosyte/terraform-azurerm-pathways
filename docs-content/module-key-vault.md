---
id: module-key-vault
title: The key_vault module
sidebar_label: key_vault
description: "Every input and output of the key_vault module, generated from its code."
---

# The key_vault module

A Key Vault with RBAC authorization, purge protection and a deny-by-default network rule, a private endpoint when you name a subnet for it, the engine's database URL as the `database-url` secret, Key Vault Secrets User for the principal that reads the secrets, Key Vault Secrets Officer for whoever applies (Terraform writes the secret), and the vault's audit log sent to a Log Analytics workspace.

Use it on its own with `source = "github.com/cosyte/terraform-azurerm-pathways//modules/key_vault"`.

This page is generated from the code in `modules/key_vault/` by `scripts/docs.sh`, and CI fails when it no longer matches. Change `modules/key_vault/variables.tf` or its `outputs.tf`, then run `scripts/docs.sh`.

## Requirements

| Name | Version |
| --- | --- |
| `terraform` | `>= 1.9.0` |
| `azurerm` | `>= 4.42.0, < 5.0.0` |

## Resources

- `azurerm_key_vault.this`
- `azurerm_key_vault_secret.database_url`
- `azurerm_monitor_diagnostic_setting.key_vault`
- `azurerm_private_endpoint.key_vault`
- `azurerm_role_assignment.deployer_secrets_officer`
- `azurerm_role_assignment.identity_secrets_user`
- `data.azurerm_client_config.current`

## Inputs

12 inputs, 6 of them required. The required ones come first, then the rest by name.

### `database_url`

Required.

The engine's database URL, written to the database-url secret.

Type:

```hcl
string
```

### `location`

Required.

The Azure region, such as eastus2.

Type:

```hcl
string
```

### `log_analytics_workspace_id`

Required.

The Log Analytics workspace the vault's audit log is sent to.

Type:

```hcl
string
```

### `name`

Required.

Short name the vault's name is built from (kv-\<name\>): 3 to 16 lowercase letters, digits and hyphens, starting with a letter. The vault name is global in Azure, so pick one nobody else uses.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen.

### `resource_group_name`

Required.

The existing resource group the vault is created in.

Type:

```hcl
string
```

### `secrets_reader_principal_id`

Required.

The principal that reads the vault's secrets, such as the apps' user-assigned managed identity. It gets Key Vault Secrets User on the vault and nothing more.

Type:

```hcl
string
```

### `allowed_ip_ranges`

Optional.

The address ranges allowed through the vault's public endpoint. Has no effect unless public\_network\_access\_enabled is true.

Type:

```hcl
list(string)
```

Default: `[]`

The plan refuses a value that breaks this rule, with this message:

- allowed\_ip\_ranges has no effect unless public\_network\_access\_enabled is true.

### `private_dns_zone_id`

Optional.

The private DNS zone named privatelink.vaultcore.azure.net the private endpoint registers in. Set with private\_endpoint\_subnet\_id, or leave both null.

Type:

```hcl
string
```

Default: `null`

The plan refuses a value that breaks this rule, with this message:

- private\_endpoint\_subnet\_id and private\_dns\_zone\_id are set together or not at all.

### `private_endpoint_subnet_id`

Optional.

A subnet for the vault's private endpoint. Set with private\_dns\_zone\_id, or leave both null.

Type:

```hcl
string
```

Default: `null`

The plan refuses a value that breaks this rule, with this message:

- Nothing could reach the Key Vault: the apps could not read their secrets and the apply could not write database-url. Set private\_endpoint\_subnet\_id and private\_dns\_zone\_id (recommended), or set public\_network\_access\_enabled = true with allowed\_ip\_ranges naming the runner and the environments' outbound addresses.

### `public_network_access_enabled`

Optional.

Open the vault's public endpoint to the ranges in allowed\_ip\_ranges. The vault denies every network by default, and the apps and the machine that applies (Terraform writes the database-url secret) both need a way in: a private endpoint (recommended), or this with allowed\_ip\_ranges naming the runner and the environments' outbound addresses. Container Apps is not a trusted Azure service, so the AzureServices bypass does not let the apps in.

Type:

```hcl
bool
```

Default: `false`

### `soft_delete_retention_days`

Optional.

How long a deleted vault or secret can be recovered: 7 to 90 days. Purge protection is always on.

Type:

```hcl
number
```

Default: `90`

The plan refuses a value that breaks this rule, with this message:

- soft\_delete\_retention\_days must be from 7 to 90.

### `tags`

Optional.

Tags added to every resource that takes them.

Type:

```hcl
map(string)
```

Default: `{}`

## Outputs

6 outputs, by name.

### `data_plane_id`

The Key Vault's resource id, ready only once its private endpoint (when there is one) exists, so a module that writes to the vault's data plane, such as a key, waits for a way in.

### `database_url_secret_id`

The versionless id of the database-url secret. It is ready only once the reader holds its role, so a container app that reads it can start.

### `database_url_secret_name`

The name of the secret that holds the database URL.

### `id`

The Key Vault's resource id.

### `name`

The Key Vault's name.

### `uri`

The Key Vault's URI, ending in a slash. A secret's URL is \<uri\>secrets/\<name\>.
