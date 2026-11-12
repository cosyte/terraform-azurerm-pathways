---
id: module-identity
title: The identity module
sidebar_label: identity
description: "Every input and output of the identity module, generated from its code."
---

# The identity module

The user-assigned managed identity the Pathways app and its migrate job run as. It creates the identity only: the key_vault module grants it Key Vault Secrets User, and you grant it AcrPull on a private registry.

Use it on its own with `source = "github.com/cosyte/terraform-azurerm-pathways//modules/identity"`.

This page is generated from the code in `modules/identity/` by `scripts/docs.sh`, and CI fails when it no longer matches. Change `modules/identity/variables.tf` or its `outputs.tf`, then run `scripts/docs.sh`.

## Requirements

| Name | Version |
| --- | --- |
| `terraform` | `>= 1.9.0` |
| `azurerm` | `>= 4.42.0, < 5.0.0` |

## Resources

- `azurerm_user_assigned_identity.this`

## Inputs

4 inputs, 3 of them required. The required ones come first, then the rest by name.

### `location`

Required.

The Azure region, such as eastus2.

Type:

```hcl
string
```

### `name`

Required.

Short name the identity's name is built from (id-\<name\>): 3 to 16 lowercase letters, digits and hyphens, starting with a letter.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen.

### `resource_group_name`

Required.

The existing resource group the identity is created in.

Type:

```hcl
string
```

### `tags`

Optional.

Tags added to the identity.

Type:

```hcl
map(string)
```

Default: `{}`

## Outputs

3 outputs, by name.

### `client_id`

The identity's client id.

### `id`

The identity's resource id.

### `principal_id`

The identity's principal id: grant roles to this one.
