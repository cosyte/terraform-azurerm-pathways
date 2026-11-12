---
id: module-database
title: The database module
sidebar_label: database
description: "Every input and output of the database module, generated from its code."
---

# The database module

A PostgreSQL flexible server with private access only (a delegated subnet and a private DNS zone), TLS required at version 1.2 or later, password and Microsoft Entra authentication on, an optional Entra administrator and an optional zone-redundant standby, and the `pathways` database. It generates the administrator password and puts it in the `database_url` output, which is sensitive: store it as a secret, never as a plain value.

Use it on its own with `source = "github.com/cosyte/terraform-azurerm-pathways//modules/database"`.

This page is generated from the code in `modules/database/` by `scripts/docs.sh`, and CI fails when it no longer matches. Change `modules/database/variables.tf` or its `outputs.tf`, then run `scripts/docs.sh`.

## Requirements

| Name | Version |
| --- | --- |
| `terraform` | `>= 1.9.0` |
| `azurerm` | `>= 4.42.0, < 5.0.0` |
| `random` | `>= 3.6.0, < 4.0.0` |

## Resources

- `azurerm_postgresql_flexible_server.this`
- `azurerm_postgresql_flexible_server_active_directory_administrator.this`
- `azurerm_postgresql_flexible_server_configuration.require_secure_transport`
- `azurerm_postgresql_flexible_server_configuration.ssl_min_protocol_version`
- `azurerm_postgresql_flexible_server_database.pathways`
- `data.azurerm_client_config.current`
- `random_password.postgres`

## Inputs

14 inputs, 5 of them required. The required ones come first, then the rest by name.

### `delegated_subnet_id`

Required.

A subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. The server has private access only.

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

### `name`

Required.

Short name the server's name is built from (psql-\<name\>): 3 to 16 lowercase letters, digits and hyphens, starting with a letter. The server name is global in Azure, so pick one nobody else uses.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen.

### `private_dns_zone_id`

Required.

A private DNS zone whose name ends in .postgres.database.azure.com, linked to the virtual network.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- private\_dns\_zone\_id must be a private DNS zone whose name ends in .postgres.database.azure.com.

### `resource_group_name`

Required.

The existing resource group the server is created in.

Type:

```hcl
string
```

### `backup_retention_days`

Optional.

How long backups are kept: 7 to 35 days.

Type:

```hcl
number
```

Default: `35`

The plan refuses a value that breaks this rule, with this message:

- backup\_retention\_days must be from 7 to 35.

### `entra_administrator`

Optional.

A Microsoft Entra principal made an administrator of the server. Null makes none; password and Entra authentication are both on either way.

Type:

```hcl
object({
  object_id      = string
  principal_name = string
  principal_type = string
})
```

Default: `null`

The plan refuses a value that breaks this rule, with this message:

- entra\_administrator.principal\_type must be User, Group or ServicePrincipal.

### `geo_redundant_backup_enabled`

Optional.

Keep backups in the paired region as well.

Type:

```hcl
bool
```

Default: `false`

### `high_availability_standby_zone`

Optional.

The availability zone of a zone-redundant standby. Null creates no standby.

Type:

```hcl
string
```

Default: `null`

### `postgres_version`

Optional.

The PostgreSQL major version.

Type:

```hcl
string
```

Default: `"16"`

### `sku_name`

Optional.

The server's SKU.

Type:

```hcl
string
```

Default: `"GP_Standard_D2ds_v5"`

### `storage_mb`

Optional.

The server's storage in MB.

Type:

```hcl
number
```

Default: `32768`

### `tags`

Optional.

Tags added to the server.

Type:

```hcl
map(string)
```

Default: `{}`

### `zone`

Optional.

The availability zone of the primary. Null lets Azure choose.

Type:

```hcl
string
```

Default: `null`

## Outputs

6 outputs, by name.

### `administrator_login`

The administrator login. The password is only in database\_url.

### `database`

The database the engine uses.

### `database_url`

The engine's database URL, with the generated administrator password in it. Store it as a secret, never as a plain value.

### `fqdn`

The PostgreSQL server's host name, resolvable through the private DNS zone.

### `id`

The PostgreSQL server's resource id.

### `name`

The PostgreSQL server's name.
