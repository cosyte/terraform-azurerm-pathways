---
id: example-geo-redundant-backup
title: The geo-redundant backup example
sidebar_label: geo-redundant-backup
description: "Pathways with its database backups copied to a second region, and the steps to restore the database there and run Pathways on it."
---

# The geo-redundant backup example

[`examples/geo-redundant-backup`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/geo-redundant-backup) is the shape **geo-redundant database backup with a documented restore**. Pathways with its database backups copied to a second region, and the steps to restore the database there and run Pathways on it.

## What it deploys

- The module as in the basic example, with `geo_redundant_backup_enabled = true` and 35 days of backups: Azure copies the server's backups to the region it pairs with `eastus2`.
- Set it when the server is made. Changing it on a server that exists can replace the server: read the plan.

## When to choose it

The messages the engine holds must survive the loss of a region, and you can accept the time a restore takes and the messages since the last copied backup.

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- Backup storage for the copy in the second region, on top of the copy in the first; 35 days of backups make both larger.

## What it does not cover

- An engine already running in the second region: this is a restore, not a failover. See [disaster recovery](./example-disaster-recovery.md).
- The master keys: with encryption at rest, the message bodies in a restored database are ciphertext without them. Keep a copy of each key where you can reach it if the region is lost.
- The second region's network, Key Vault and Container Apps environment: the restore steps make them with the module.

## Restore in the second region

Practise this before you need it. Each step names what it needs; check each command's `--help` for
the flags your version of the Azure CLI takes.

1. Prepare the second region's network as for any deployment: a delegated subnet for the slot, one
   for the database, one for private endpoints, and the private DNS zones, linked to that network.
2. Restore the database there from the geo-redundant backup, into the second region's subnet and
   zone. The `postgres` output gives the source server's id:

   ```sh
   az postgres flexible-server geo-restore \
     --resource-group rg-pathways-restore \
     --name psql-pw-geo-restored \
     --source-server "<the postgres output's id>" \
     --location "<the region Azure pairs with eastus2>" \
     --vnet "<the second region's virtual network>" \
     --subnet "<its subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers>" \
     --private-dns-zone "<its zone ending in .postgres.database.azure.com>"
   ```

3. Deploy the module in the second region with `existing_postgres`, as the
   [existing PostgreSQL example](./example-existing-postgres.md) does, and with the same `encryption_key_secrets`. Before
   the second apply, put two secrets in its Key Vault: the database URL, the one from the first
   region with the restored server's host name in it (a restore keeps the source's administrator
   login and password), and each master key, from the copy you kept.
4. Point your senders at the new slot's address.

The restored database is the source as it was at the restore point. Deliveries the first engine
made after that point are pending again and are sent again: a receiver drops a copy by the
message's `messageId` and `seq`. Messages received after that point are not in it: senders that
did not get an acknowledgement send them again.

## Files

Every file in `examples/geo-redundant-backup`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `README.md`

````markdown title="examples/geo-redundant-backup/README.md"
# examples/geo-redundant-backup

**Shape:** Geo-redundant database backup with a documented restore.

Pathways with its database backups copied to a second region, and the steps to restore the database there and run Pathways on it.

## What it builds

- The module as in the basic example, with `geo_redundant_backup_enabled = true` and 35 days of backups: Azure copies the server's backups to the region it pairs with `eastus2`.
- Set it when the server is made. Changing it on a server that exists can replace the server: read the plan.

## When to choose it

The messages the engine holds must survive the loss of a region, and you can accept the time a restore takes and the messages since the last copied backup.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- Backup storage for the copy in the second region, on top of the copy in the first; 35 days of backups make both larger.

## What it does not cover

- An engine already running in the second region: this is a restore, not a failover. See [disaster recovery](../disaster-recovery).
- The master keys: with encryption at rest, the message bodies in a restored database are ciphertext without them. Keep a copy of each key where you can reach it if the region is lost.
- The second region's network, Key Vault and Container Apps environment: the restore steps make them with the module.

## Restore in the second region

Practise this before you need it. Each step names what it needs; check each command's `--help` for
the flags your version of the Azure CLI takes.

1. Prepare the second region's network as for any deployment: a delegated subnet for the slot, one
   for the database, one for private endpoints, and the private DNS zones, linked to that network.
2. Restore the database there from the geo-redundant backup, into the second region's subnet and
   zone. The `postgres` output gives the source server's id:

   ```sh
   az postgres flexible-server geo-restore \
     --resource-group rg-pathways-restore \
     --name psql-pw-geo-restored \
     --source-server "<the postgres output's id>" \
     --location "<the region Azure pairs with eastus2>" \
     --vnet "<the second region's virtual network>" \
     --subnet "<its subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers>" \
     --private-dns-zone "<its zone ending in .postgres.database.azure.com>"
   ```

3. Deploy the module in the second region with `existing_postgres`, as the
   [existing PostgreSQL example](../existing-postgres) does, and with the same `encryption_key_secrets`. Before
   the second apply, put two secrets in its Key Vault: the database URL, the one from the first
   region with the restored server's host name in it (a restore keeps the source's administrator
   login and password), and each master key, from the copy you kept.
4. Point your senders at the new slot's address.

The restored database is the source as it was at the restore point. Deliveries the first engine
made after that point are pending again and are sent again: a receiver drops a copy by the
message's `messageId` and `seq`. Messages received after that point are not in it: senders that
did not get an acknowledgement send them again.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
````

### `main.tf`

```hcl title="examples/geo-redundant-backup/main.tf"
# Pathways with its database backups copied to a second region, so the messages it holds can be
# restored there if the first region is lost. The engine itself runs in one region; the README says
# how to restore the database in the other and run Pathways on it. Every name, id and range here is
# a placeholder: replace them with your own. Nothing in this example is applied by our CI.

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  description = "The subscription to deploy into."
  type        = string
}

variable "image" {
  description = "Your project's image, built on the Pathways image and pinned by digest."
  type        = string
}

module "pathways" {
  source = "../.."

  name                = "pw-geo"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-pathways-blue"
    }
  }

  # pathways.yaml's probes block listens on 0.0.0.0:9091.
  mllp_ports            = [2575]
  ingress_allowed_cidrs = ["10.20.0.0/16"]

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/pathways-geo.postgres.database.azure.com"

    # Backups kept 35 days, the most the server allows, and copied to the region Azure pairs with
    # eastus2. Set this when the server is made: changing it on a server that exists can replace the
    # server, so read the plan.
    backup_retention_days        = 35
    geo_redundant_backup_enabled = true
  }

  key_vault = {
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
    private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  tags = {
    environment = "example"
  }
}

output "postgres" {
  description = "The PostgreSQL server to restore from: its id is the restore's source."
  value       = module.pathways.postgres
}

output "key_vault_name" {
  description = "The Key Vault that holds the master key. A restored database is unreadable without it: keep a copy of each key outside this region."
  value       = module.pathways.key_vault.name
}
```

### `tests/example.tftest.hcl`

```hcl title="examples/geo-redundant-backup/tests/example.tftest.hcl"
# Plans the example against mocked providers: no Azure account, no credentials. tests/run.sh at the
# repository root runs it. Every id and value below is synthetic.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pathways-example"
    }
  }
}

mock_provider "azapi" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  image           = "registry.example.com/integration/my-project:3f2a91c@sha256:0000000000000000000000000000000000000000000000000000000000000000"
}

run "plans_a_server_with_geo_redundant_backup" {
  command = plan

  assert {
    condition     = output.postgres.database == "pathways"
    error_message = "The example must make its PostgreSQL server."
  }

  assert {
    condition     = output.key_vault_name == "kv-pw-geo"
    error_message = "The example must name its Key Vault."
  }
}
```

### `versions.tf`

```hcl title="examples/geo-redundant-backup/versions.tf"
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.42.0, < 5.0.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0.0, < 3.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.0, < 4.0.0"
    }
  }
}
```
