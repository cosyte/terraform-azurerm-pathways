---
id: example-basic
title: The basic example
sidebar_label: basic
description: "The root module called with one slot, in a virtual network you already have: what it deploys, what it costs to leave running, and its files."
---

# The basic example

[`examples/basic`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/basic) is
the smallest full configuration of the module: one slot, private intake, and the subnets and DNS
zones of a network you already have, named by id. The [quickstart](./quickstart.md) deploys it step
by step. Every name, id and range in it is a placeholder to replace with your own. Our CI validates
it and never applies it.

## What it deploys

Everything goes in the resource group `rg-pathways-example`, in `eastus2`, which must exist first:

- the managed identity `id-pw-example`, which the app and the job run as;
- the Log Analytics workspace `log-pw-example`, keeping logs for 90 days;
- the PostgreSQL flexible server `psql-pw-example`, version 16, `GP_Standard_D2ds_v5` with 32 GiB of
  storage and 35 days of backups, on the delegated subnet `snet-postgres`, with the `pathways`
  database;
- the Key Vault `kv-pw-example`, with its private endpoint on `snet-endpoints`, the `database-url`
  secret, the identity's read role and its audit log in the workspace;
- for the slot `blue`: the Container Apps environment `cae-pw-example-blue` on `snet-pathways-blue`,
  with an internal load balancer; the app `pw-example-blue`, one replica of 1 vCPU and 2 GiB,
  taking MLLP on port 2575 from `10.20.0.0/16` only; and the migrate job `pw-example-blue-migrate`.

The app reads one master key, `PATHWAYS_KEY_2026_11`, from the vault secret `pathways-key-2026-11`,
which you put there yourself: the [quickstart](./quickstart.md#5-make-the-key-vault-then-put-the-master-key-in-it)
says when.

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement with
Microsoft, set those. Azure's pricing calculator takes each item below.

Billed every hour it exists, whether a message arrives or not:

- **The PostgreSQL server's compute,** `GP_Standard_D2ds_v5` (2 vCores), and its 32 GiB of storage.
  Backups up to the size of the storage are included; 35 days of them can go past that on a busy
  database. This is the largest line.
- **The app's replica,** 1 vCPU and 2 GiB, which runs all the time: the module never scales it to
  zero. Container Apps bills a replica it counts as idle at a lower rate, and gives each
  subscription a monthly free grant; its pricing page says how both are counted.
- **The Key Vault's private endpoint,** by the hour, and the data through it.

Billed by use:

- **Log Analytics,** each GB the environment and the vault's audit log send, and retention past the
  included days, since this keeps 90.
- **Key Vault** operations: the engine's secret reads when a revision starts.
- **The migrate job,** only while it runs.
- **Data transfer** out of the region.

The managed identity and the role assignments cost nothing. `terraform destroy` removes every billed
item; the Key Vault is then kept soft-deleted, at no charge, for its retention.

## Files

Every file in `examples/basic`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `README.md`

````markdown title="examples/basic/README.md"
# examples/basic

**Shape:** Minimal.

The smallest full configuration of the module: one slot, private intake, in a virtual network you already have, named by id.

## What it builds

- In the existing resource group `rg-pathways-example`, in `eastus2`: the managed identity `id-pw-example`, the Log Analytics workspace `log-pw-example` (90 days), and the Key Vault `kv-pw-example` with its private endpoint on `snet-endpoints`.
- The PostgreSQL flexible server `psql-pw-example`: version 16, `GP_Standard_D2ds_v5`, 32 GiB, 35 days of backups, private access on `snet-postgres`, TLS required.
- For the slot `blue`: the Container Apps environment `cae-pw-example-blue` on `snet-pathways-blue`, internal to the network; the app `pw-example-blue`, one replica of 1 vCPU and 2 GiB, taking MLLP on 2575 from `10.20.0.0/16` only; and the migrate job `pw-example-blue-migrate`.

## When to choose it

Your first deployment, or a trial of the module. It is the shape the [quickstart](https://docs.cosyte.com/terraform-azurerm-pathways/quickstart) deploys, and it runs one engine with no public address.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- The PostgreSQL server's compute and its 32 GiB of storage, every hour it exists. This is the largest line.
- The app's one replica, which runs all the time: the module never scales it to zero.
- The Key Vault's private endpoint, by the hour.
- By use: Log Analytics ingestion and retention past the included days, Key Vault operations, the migrate job while it runs, and data transfer out of the region.

## What it does not cover

- No standby: while a revision is replaced or the engine restarts, intake is closed and senders retry. The [production example](../production) adds one.
- No zone-redundant database, and no copy of the backups in a second region.
- It creates no network: the subnets, their delegations and the private DNS zones must exist first.
- No storage account, no SFTP and no HTTP intake.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
````

### `main.tf`

```hcl title="examples/basic/main.tf"
# Pathways on Azure Container Apps, one slot, in a virtual network you already have. Every name and
# id here is a placeholder: replace them with your own. Nothing in this example is applied by our CI.

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

  name                = "pw-example"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-pathways-blue"
    }
  }

  # One MLLP source on 2575; pathways.yaml's probes block listens on 0.0.0.0:9091.
  mllp_ports            = [2575]
  ingress_allowed_cidrs = ["10.20.0.0/16"]
  drain_seconds         = 30 # Above 30 is unconfirmed: see "Limits we rely on" in the README.

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/pathways-example.postgres.database.azure.com"
  }

  key_vault = {
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
    private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  tags = {
    environment = "example"
  }
}

output "slots" {
  description = "Each slot's environment address, app and migrate job."
  value       = module.pathways.slots
}
```

### `tests/example.tftest.hcl`

```hcl title="examples/basic/tests/example.tftest.hcl"
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

run "plans_one_private_slot" {
  command = plan

  assert {
    condition     = output.slots["blue"].app_name == "pw-example-blue"
    error_message = "The example must plan its one slot."
  }

  assert {
    condition     = output.slots["blue"].migrate_job_name == "pw-example-blue-migrate"
    error_message = "The example must plan the slot's migrate job."
  }
}
```

### `versions.tf`

```hcl title="examples/basic/versions.tf"
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
