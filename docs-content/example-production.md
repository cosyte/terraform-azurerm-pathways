---
id: example-production
title: The production example
sidebar_label: production
description: "One slot for production traffic: one engine working and a second replica waiting as its warm standby, a zone-redundant PostgreSQL server, a year of logs and every schema change run from the migrate job."
---

# The production example

[`examples/production`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/production) is the shape **production, one node with its warm standby**. One slot for production traffic: one engine working and a second replica waiting as its warm standby, a zone-redundant PostgreSQL server, a year of logs and every schema change run from the migrate job.

## What it deploys

- The identity, the workspace with 365 days of retention, and the Key Vault with its private endpoint, in `rg-pathways-prod`.
- The PostgreSQL server `psql-pw-prod`: `GP_Standard_D4ds_v5`, 128 GiB, 35 days of backups, its primary in zone 1 and a high-availability standby in zone 2 that Azure fails over to, and a Microsoft Entra group as its administrator.
- The app `pw-prod-blue` with `standby_replica = true`: two replicas of 2 vCPU and 4 GiB, both started with `--standby`. The first to ask takes the engine lease and runs every channel; the other holds no lease, opens no listener and answers `/readyz` with 503 `standby`, so the ingress sends it nothing. When the working engine stops, the standby takes over within about 20 seconds with the default lease.
- The engine starts with `--no-migrate`, so schema changes run only from the migrate job `pw-prod-blue-migrate`.
- Every network id is a variable: the network is yours.

## When to choose it

You carry production traffic in one region and want a stopped or lost engine replaced in seconds rather than at the next restart, and a database zone failure covered by Azure's own failover.

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Two replicas of 2 vCPU and 4 GiB, all the time. The standby is a replica like any other; Container Apps bills a replica it counts as idle at a lower rate, and its pricing page says how idle is counted.
- The PostgreSQL server's compute twice over, for the high-availability standby, and 128 GiB of storage.
- Log Analytics retention for 365 days, past the included days.
- The Key Vault's private endpoint, Key Vault operations, the migrate job while it runs, and data transfer out of the region.

## What it does not cover

- A region lost: the engine, the database and its standby are in one region. The [geo-redundant backup example](./example-geo-redundant-backup.md) keeps the backups in a second one.
- Several engines working at once: one engine holds the lease, and the standby only waits. See [multi-node](./example-multi-node.md).
- We have not yet confirmed against a live environment that Container Apps' TCP ingress sends nothing to a replica whose readiness probe fails, or how a new revision whose replicas start as standbys replaces the old one. Test both before you rely on them.

## Files

Every file in `examples/production`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `README.md`

````markdown title="examples/production/README.md"
# examples/production

**Shape:** Production, one node with its warm standby.

One slot for production traffic: one engine working and a second replica waiting as its warm standby, a zone-redundant PostgreSQL server, a year of logs and every schema change run from the migrate job.

## What it builds

- The identity, the workspace with 365 days of retention, and the Key Vault with its private endpoint, in `rg-pathways-prod`.
- The PostgreSQL server `psql-pw-prod`: `GP_Standard_D4ds_v5`, 128 GiB, 35 days of backups, its primary in zone 1 and a high-availability standby in zone 2 that Azure fails over to, and a Microsoft Entra group as its administrator.
- The app `pw-prod-blue` with `standby_replica = true`: two replicas of 2 vCPU and 4 GiB, both started with `--standby`. The first to ask takes the engine lease and runs every channel; the other holds no lease, opens no listener and answers `/readyz` with 503 `standby`, so the ingress sends it nothing. When the working engine stops, the standby takes over within about 20 seconds with the default lease.
- The engine starts with `--no-migrate`, so schema changes run only from the migrate job `pw-prod-blue-migrate`.
- Every network id is a variable: the network is yours.

## When to choose it

You carry production traffic in one region and want a stopped or lost engine replaced in seconds rather than at the next restart, and a database zone failure covered by Azure's own failover.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Two replicas of 2 vCPU and 4 GiB, all the time. The standby is a replica like any other; Container Apps bills a replica it counts as idle at a lower rate, and its pricing page says how idle is counted.
- The PostgreSQL server's compute twice over, for the high-availability standby, and 128 GiB of storage.
- Log Analytics retention for 365 days, past the included days.
- The Key Vault's private endpoint, Key Vault operations, the migrate job while it runs, and data transfer out of the region.

## What it does not cover

- A region lost: the engine, the database and its standby are in one region. The [geo-redundant backup example](../geo-redundant-backup) keeps the backups in a second one.
- Several engines working at once: one engine holds the lease, and the standby only waits. See [multi-node](../multi-node).
- We have not yet confirmed against a live environment that Container Apps' TCP ingress sends nothing to a replica whose readiness probe fails, or how a new revision whose replicas start as standbys replaces the old one. Test both before you rely on them.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
````

### `main.tf`

```hcl title="examples/production/main.tf"
# Pathways for production on one slot: one engine working and a second replica waiting as its warm
# standby, a zone-redundant PostgreSQL server with a standby of its own in a second zone, a year of
# logs, and the master key and the database URL in a Key Vault reached only through its private
# endpoint. It runs in a virtual network you already have, named by id. Every name, id and range
# here is a placeholder: replace them with your own. Nothing in this example is applied by our CI.

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

variable "apps_subnet_id" {
  description = "A subnet delegated to Microsoft.App/environments, /27 or larger, for the slot's environment."
  type        = string
}

variable "postgres_subnet_id" {
  description = "A subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "postgres_private_dns_zone_id" {
  description = "A private DNS zone whose name ends in .postgres.database.azure.com, linked to the virtual network."
  type        = string
}

variable "endpoints_subnet_id" {
  description = "A subnet for the Key Vault's private endpoint."
  type        = string
}

variable "key_vault_private_dns_zone_id" {
  description = "The privatelink.vaultcore.azure.net private DNS zone, linked to the virtual network."
  type        = string
}

variable "sender_cidrs" {
  description = "The address ranges your MLLP senders connect from, inside or connected to the virtual network."
  type        = list(string)
}

variable "database_administrators" {
  description = "The Microsoft Entra group whose members administer the database server."
  type = object({
    object_id      = string
    principal_name = string
  })
}

module "pathways" {
  source = "../.."

  name                = "pw-prod"
  resource_group_name = "rg-pathways-prod"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = var.apps_subnet_id
    }
  }

  # Two replicas, both started with --standby: the first takes the engine lease and runs every
  # channel; the other answers /readyz 503 standby, so the ingress sends it nothing, and takes over
  # within about 20 seconds once the first stops. pathways.yaml's probes block listens on
  # 0.0.0.0:9091, and its storage block reads PATHWAYS_DATABASE_URL with tls set.
  standby_replica = true

  mllp_ports            = [2575]
  ingress_allowed_cidrs = var.sender_cidrs
  drain_seconds         = 30 # Above 30 is unconfirmed: see "Limits we rely on" in the README.

  cpu    = 2
  memory = "4Gi"

  # Every schema change runs from the migrate job, before a new revision starts.
  app_start_args = ["start", "-C", "/project", "--no-migrate"]

  log_retention_days = 365

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = var.postgres_subnet_id
    private_dns_zone_id = var.postgres_private_dns_zone_id

    # Four vCores, 128 GiB, the longest backup retention, and a standby server in a second zone that
    # Azure fails over to.
    sku_name                       = "GP_Standard_D4ds_v5"
    storage_mb                     = 131072
    backup_retention_days          = 35
    zone                           = "1"
    high_availability_standby_zone = "2"

    entra_administrator = {
      object_id      = var.database_administrators.object_id
      principal_name = var.database_administrators.principal_name
      principal_type = "Group"
    }
  }

  key_vault = {
    private_endpoint_subnet_id = var.endpoints_subnet_id
    private_dns_zone_id        = var.key_vault_private_dns_zone_id
  }

  tags = {
    environment = "production"
  }
}

output "slots" {
  description = "The slot's environment address (where senders connect for MLLP), app and migrate job."
  value       = module.pathways.slots
}

output "postgres" {
  description = "The PostgreSQL server's host name, database and administrator login."
  value       = module.pathways.postgres
}
```

### `tests/example.tftest.hcl`

```hcl title="examples/production/tests/example.tftest.hcl"
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
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pathways-prod"
    }
  }
}

mock_provider "azapi" {}

variables {
  subscription_id               = "00000000-0000-0000-0000-000000000000"
  image                         = "registry.example.com/integration/my-project:3f2a91c@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  apps_subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-pathways-blue"
  postgres_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
  postgres_private_dns_zone_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/pathways-prod.postgres.database.azure.com"
  endpoints_subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
  key_vault_private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  sender_cidrs                  = ["10.20.0.0/16"]
  database_administrators = {
    object_id      = "00000000-0000-0000-0000-000000000004"
    principal_name = "pathways-db-admins"
  }
}

run "plans_one_engine_with_a_warm_standby_and_a_zone_redundant_database" {
  command = plan

  assert {
    condition     = output.slots["blue"].app_name == "pw-prod-blue"
    error_message = "The example must plan its one slot."
  }

  assert {
    condition     = output.postgres.administrator_login == "pathways_admin"
    error_message = "The production example must make its PostgreSQL server."
  }
}
```

### `versions.tf`

```hcl title="examples/production/versions.tf"
terraform {
  required_version = ">= 1.9.0"

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
      version = ">= 3.6.0, < 4.0.0"
    }
  }
}
```
