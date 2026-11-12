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
