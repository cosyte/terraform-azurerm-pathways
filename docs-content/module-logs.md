---
id: module-logs
title: The logs module
sidebar_label: logs
description: "Every input and output of the logs module, generated from its code."
---

# The logs module

A Log Analytics workspace that keeps the engine's logs for 30 to 730 days (90 by default). The Container Apps environments and the Key Vault's audit log write to it.

Use it on its own with `source = "github.com/cosyte/terraform-azurerm-pathways//modules/logs"`.

This page is generated from the code in `modules/logs/` by `scripts/docs.sh`, and CI fails when it no longer matches. Change `modules/logs/variables.tf` or its `outputs.tf`, then run `scripts/docs.sh`.

## Requirements

| Name | Version |
| --- | --- |
| `terraform` | `>= 1.9.0` |
| `azurerm` | `>= 4.42.0, < 5.0.0` |

## Resources

- `azurerm_log_analytics_workspace.this`

## Inputs

5 inputs, 3 of them required. The required ones come first, then the rest by name.

### `location`

Required.

The Azure region, such as eastus2.

Type:

```hcl
string
```

### `name`

Required.

Short name the workspace's name is built from (log-\<name\>): 3 to 16 lowercase letters, digits and hyphens, starting with a letter.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen.

### `resource_group_name`

Required.

The existing resource group the workspace is created in.

Type:

```hcl
string
```

### `retention_days`

Optional.

How long the workspace keeps the engine's logs: 30 to 730 days.

Type:

```hcl
number
```

Default: `90`

The plan refuses a value that breaks this rule, with this message:

- retention\_days must be a whole number from 30 to 730.

### `tags`

Optional.

Tags added to the workspace.

Type:

```hcl
map(string)
```

Default: `{}`

## Outputs

2 outputs, by name.

### `id`

The Log Analytics workspace's resource id.

### `name`

The Log Analytics workspace's name.
