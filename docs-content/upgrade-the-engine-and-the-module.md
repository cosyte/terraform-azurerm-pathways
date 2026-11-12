---
id: upgrade-the-engine-and-the-module
title: Upgrade the engine and the module
sidebar_label: Upgrade
description: "Roll out a new image of your project, run schema changes from the migrate job, switch senders between two slots, and move to a new release of this module."
---

# Upgrade the engine and the module

Two things move on their own schedules: your project's image, which carries the Pathways version
and your channels, and this module. This page covers both.

## Roll out a new image

Each slot's `image` names your project's image by digest. Change it and apply:

```hcl
  slots = {
    blue = {
      image                    = "registry.example.com/integration/my-project:4b7e02d@sha256:<64 hex digits>"
      infrastructure_subnet_id = "<the slot's subnet>"
    }
  }
```

The app runs one revision at a time, with one replica. The apply makes a new revision; Container
Apps sends the old one SIGTERM, and the engine drains for up to `drain_seconds` before it is
stopped. See [Limits we rely on](./limits-we-rely-on.md#the-termination-grace-period) before you
raise `drain_seconds` above 30.

With one slot, the engine is down between the old revision stopping and the new one turning ready,
and senders retry. To keep intake open through an upgrade, use two slots.

## Run schema changes from the migrate job

By default the engine applies the expand steps of a schema change itself when it starts. To run
every schema change from the migrate job instead, start the engine with `--no-migrate`:

```hcl
  app_start_args = ["start", "-C", "/project", "--no-migrate"]
```

Then, for each upgrade, apply the new image, which also updates the job, and start the job before
the new revision takes the engine lease:

```bash
az containerapp job start --name pw-example-blue-migrate --resource-group rg-pathways-example
az containerapp job execution list --name pw-example-blue-migrate --resource-group rg-pathways-example \
  --query "[0].properties.status" --output tsv
```

The job is `<name>-<slot>-migrate`, and the `slots` output gives it as `migrate_job_name`. A run may
take up to `migrate_timeout_seconds`, 1800 by default, and is not retried. With `--no-migrate`, an
engine refuses a database that lacks a step it needs, and names both versions.
[Upgrade Pathways](https://docs.cosyte.com/pathways/upgrade-pathways) in the Pathways docs says
what expand and contract steps are, and how to check a version before it sends anything.

## Switch between two slots

Two slots, `blue` and `green`, each have an environment of their own, so both expose the same MLLP
ports at once, and both use the same database. To upgrade without closing intake:

1. Give the second engine `lease.standby: true` in `pathways.yaml`, so it waits for the engine lease
   instead of being refused.
2. Add the second slot, on its own subnet, with the new image, and apply.
3. Point your senders, or the DNS name they use, at the new slot's `static_ip` from the `slots`
   output.
4. Once the old slot has no connections left, remove it from `slots` and apply. Its engine drains
   and releases the lease, and the standby takes it.

[Deployment shapes](./deployment-shapes.md#two-slots-blue-and-green) says why each slot has its own
environment.

## Move to a new release of the module

Change the tag in `source`, then:

```bash
terraform init -upgrade
terraform plan
```

Read the plan before you apply. The [CHANGELOG](https://github.com/cosyte/terraform-azurerm-pathways/blob/main/CHANGELOG.md)
names every change to an input or an output, and what a caller must change. A plan that replaces
the database server, the Key Vault or the storage account loses what they hold: stop and read the
release's notes.

## Related

- [Inputs and outputs](./inputs-and-outputs.md#slots): `slots`, `app_start_args`, `migrate_args`
  and `drain_seconds`.
- [Stop and upgrade a node](https://docs.cosyte.com/pathways/stop-and-upgrade-a-node) in the
  Pathways docs: what a stop does, on Azure Container Apps among others.
