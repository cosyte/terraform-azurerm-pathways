---
id: module-storage
title: The storage module
sidebar_label: storage
description: "Every input and output of the storage module, generated from its code."
---

# The storage module

A StorageV2 account with hierarchical namespace and SFTP on, for files partners send and fetch over SFTP and for the engine's own blobs:

- no public network access by default, a blob private endpoint (which SFTP uses too), and, when you open the public endpoint, an IP firewall of the public IPv4 ranges you name;
- shared keys off, HTTPS only, TLS 1.2 at least, no public containers, infrastructure encryption, and blob and container soft delete;
- encryption with a customer-managed key the module creates in your Key Vault, read by an identity of the account's own, unless `customer_managed_key_enabled = false`;
- the engine's container, and one container per SFTP user, `sftp-<user>`, as that user's home directory, with a permission on that container alone;
- each SFTP user signing in with SSH keys only, never a password;
- Storage Blob Data Contributor on each container for the engine's identity, so the engine needs no account key;
- the blob service's read, write and delete logs sent to a Log Analytics workspace.

Use it on its own with `source = "github.com/cosyte/terraform-azurerm-pathways//modules/storage"`.

This page is generated from the code in `modules/storage/` by `scripts/docs.sh`, and CI fails when it no longer matches. Change `modules/storage/variables.tf` or its `outputs.tf`, then run `scripts/docs.sh`.

## Requirements

| Name | Version |
| --- | --- |
| `terraform` | `>= 1.9.0` |
| `azurerm` | `>= 4.42.0, < 5.0.0` |

## Resources

- `azurerm_key_vault_key.storage`
- `azurerm_monitor_diagnostic_setting.blob`
- `azurerm_private_endpoint.blob`
- `azurerm_role_assignment.blob_data`
- `azurerm_role_assignment.deployer_crypto_officer`
- `azurerm_role_assignment.key_user`
- `azurerm_storage_account.this`
- `azurerm_storage_account_local_user.this`
- `azurerm_storage_container.this`
- `azurerm_user_assigned_identity.storage`
- `data.azurerm_client_config.current`

## Inputs

18 inputs, 7 of them required. The required ones come first, then the rest by name.

### `blob_data_principal_id`

Required.

The principal that reads and writes blobs for the engine, such as its user-assigned managed identity. It gets Storage Blob Data Contributor on the engine's container and on each SFTP user's container, so the engine needs no account key.

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

The Log Analytics workspace the blob service's read, write and delete logs are sent to.

Type:

```hcl
string
```

### `name`

Required.

Short name the account's default name (st\<name\> without its hyphens) and the other names are built from: 3 to 16 lowercase letters, digits and hyphens, starting with a letter.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen.

### `private_dns_zone_id`

Required.

The private DNS zone named privatelink.blob.core.windows.net the private endpoint registers in, linked to the virtual network.

Type:

```hcl
string
```

### `private_endpoint_subnet_id`

Required.

The subnet for the account's blob private endpoint, which the engine reads through and SFTP clients in your virtual network connect to. Required: Azure Storage's IP rules do not apply to traffic from the same region, so the engine cannot come in over the public endpoint.

Type:

```hcl
string
```

### `resource_group_name`

Required.

The existing resource group the account is created in.

Type:

```hcl
string
```

### `account_name`

Optional.

The storage account's name: 3 to 24 lowercase letters and digits. It is global in Azure. Null names it st\<name\> without its hyphens.

Type:

```hcl
string
```

Default: `null`

The plan refuses a value that breaks this rule, with this message:

- account\_name must be 3 to 24 lowercase letters and digits.

### `allowed_ip_ranges`

Optional.

The public IPv4 addresses and ranges allowed through the account's public endpoint, such as 198.51.100.0/24 or 203.0.113.7. Has no effect unless public\_network\_access\_enabled is true. Azure Storage takes IPv4 only, a single address without a prefix rather than a /31 or /32, and no private (RFC 1918) range. The plan refuses those, a range wider than a /8 (0.0.0.0/0 included), and a list whose ranges add up to more addresses than one /8 holds (16,777,216), since a list of narrower ranges could otherwise cover every public address.

Type:

```hcl
list(string)
```

Default: `[]`

The plan refuses a value that breaks one of these rules, with its message:

- allowed\_ip\_ranges has no effect unless public\_network\_access\_enabled is true.
- public\_network\_access\_enabled = true needs allowed\_ip\_ranges naming the SFTP clients' public addresses: the account carries PHI.
- Each entry of allowed\_ip\_ranges must be a public IPv4 address or range, such as 203.0.113.7 or 198.51.100.0/24: no spaces, no leading zero in the prefix, and no IPv6 (Azure Storage's IP rules take IPv4 only).
- Azure Storage does not take a /31 or /32 range in an IP rule: write each address on its own, without a prefix.
- allowed\_ip\_ranges must not hold a range wider than a /8 (0.0.0.0/0 included): the account carries PHI. Name your SFTP clients' ranges.
- The ranges in allowed\_ip\_ranges add up to more addresses than one /8 (16,777,216): the account carries PHI. Name your SFTP clients' ranges.
- allowed\_ip\_ranges must not hold or overlap a private range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16): Azure Storage's IP rules take public addresses only. Clients in your virtual network reach the account through its private endpoint.

### `container_name`

Optional.

The engine's own container: 3 to 63 lowercase letters, digits and single hyphens, not starting with sftp-, which names the SFTP users' containers.

Type:

```hcl
string
```

Default: `"pathways"`

The plan refuses a value that breaks this rule, with this message:

- container\_name must be 3 to 63 lowercase letters, digits and single hyphens, starting and ending with a letter or digit, and must not start with sftp-: each SFTP user's container is sftp-\<user\>.

### `customer_managed_key_enabled`

Optional.

Encrypt the account with a key the module creates in the Key Vault at key\_vault\_id, rotated by the vault every year. Whoever applies gets Key Vault Crypto Officer on the vault to create it. False leaves Microsoft-managed keys.

Type:

```hcl
bool
```

Default: `true`

### `key_vault_id`

Optional.

The Key Vault the customer-managed key is created in. It must have purge protection and RBAC authorization on, and let Azure's trusted services through its firewall, as the key\_vault module's vault does. The machine that applies needs to reach it, as for any secret it writes.

Type:

```hcl
string
```

Default: `null`

The plan refuses a value that breaks this rule, with this message:

- customer\_managed\_key\_enabled needs key\_vault\_id: name the vault the key is created in, or set customer\_managed\_key\_enabled = false.

### `public_network_access_enabled`

Optional.

Open the account's public endpoint to the ranges in allowed\_ip\_ranges, for SFTP clients outside your virtual network. Off by default: only the private endpoint reaches the account.

Type:

```hcl
bool
```

Default: `false`

### `replication_type`

Optional.

The account's redundancy: LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS. More copies cost more. Not every region offers zone redundancy.

Type:

```hcl
string
```

Default: `"LRS"`

The plan refuses a value that breaks this rule, with this message:

- replication\_type must be LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS.

### `sftp_enabled`

Optional.

Turn the account's SFTP endpoint on. Azure charges for SFTP by the hour while it is on, used or not; turn it off when no partner needs it. Hierarchical namespace stays on either way.

Type:

```hcl
bool
```

Default: `true`

The plan refuses a value that breaks this rule, with this message:

- sftp\_users needs sftp\_enabled = true: a local user can sign in only over SFTP.

### `sftp_users`

Optional.

The SFTP local users, keyed by a user name of 3 to 32 lowercase letters and digits, starting with a letter. Each gets a container of its own, sftp-\<user\>, as its home directory and a permission on that container only, so it cannot reach another user's files: on Blob Storage a home directory alone does not confine a user. Each signs in with an SSH key, never a password, as \<account\>.\<user\>. ssh\_public\_keys holds one or more public keys, each one line in OpenSSH form (type, base64 data and an optional comment, which becomes the key's description). permissions is any of create, write, list, read and delete; the default, create, write and list, lets a partner drop files and see them, and no more.

Type:

```hcl
map(object({
  ssh_public_keys = list(string)
  permissions     = optional(list(string), ["create", "write", "list"])
}))
```

Default: `{}`

The plan refuses a value that breaks one of these rules, with its message:

- Each SFTP user name must be 3 to 32 lowercase letters and digits, starting with a letter.
- Each SFTP user needs 1 to 10 SSH public keys: a user signs in with a key, never a password.
- Each SSH key must be one public key on one line, in OpenSSH form: its type (such as ssh-rsa), its base64 data and an optional comment. Never a private key.
- Each SFTP user's permissions must be one or more of create, write, list, read and delete.

### `soft_delete_retention_days`

Optional.

How long a deleted blob or container can be recovered: 1 to 365 days. A soft-deleted blob still holds its data and still costs storage.

Type:

```hcl
number
```

Default: `7`

The plan refuses a value that breaks this rule, with this message:

- soft\_delete\_retention\_days must be a whole number from 1 to 365.

### `tags`

Optional.

Tags added to every resource that takes them.

Type:

```hcl
map(string)
```

Default: `{}`

## Outputs

7 outputs, by name.

### `account_id`

The storage account's resource id.

### `account_name`

The storage account's name: the account key of a channel's azblob block.

### `container`

The engine's own container.

### `customer_managed_key_id`

The versionless id of the key the account is encrypted with, or null with Microsoft-managed keys.

### `sftp_host`

The host SFTP clients connect to on port 22: the account's blob endpoint. In the virtual network it resolves to the private endpoint.

### `sftp_users`

Per SFTP user: the name it signs in with (\<account\>.\<user\>) and its container, which is its home directory.

### `user_containers`

Each SFTP user's container, by user name: a channel reads or writes a user's files there.
