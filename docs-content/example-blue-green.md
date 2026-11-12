---
id: example-blue-green
title: Blue and green slots
sidebar_label: blue-green
description: "Not yet supported as an example. This folder holds no Terraform, on purpose."
---

# Blue and green slots

[`examples/blue-green`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/blue-green) is the shape **blue and green slots with a handover**. Not yet supported as an example. This folder holds no Terraform, on purpose.

**Not yet supported.** There is no Terraform in this folder, and CI checks that none is added
until the engine supports this shape.

## What it deploys

- Nothing yet. Blue and green is two slots, each with an environment of its own, since a TCP port is unique across one environment and both slots must expose the same MLLP ports. The switch between them waits on the engine: a planned handover of the engine lease from the working engine to the waiting one, on request, so that a switch hands the work over rather than stopping one engine and waiting for the other to take the lease.
- We will write this example once Pathways hands the lease over on request. Until then, the [production example](./example-production.md) keeps a warm standby beside the working engine in one slot.

## When to choose it

Not yet. When it lands, choose it to upgrade the engine or your channels with intake open, and to switch back if the new version misbehaves.

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Nothing: there is no Terraform here yet, so there is nothing to apply.

## What it does not cover

- Everything, for now: there is no Terraform here.

## Files

Every file in `examples/blue-green`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `README.md`

```markdown title="examples/blue-green/README.md"
# examples/blue-green

**Shape:** Blue and green slots with a handover.

Not yet supported as an example. This folder holds no Terraform, on purpose.

## Status

**Not yet supported.** There is no Terraform in this folder, and CI checks that none is added
until the engine supports this shape.

## What it builds

- Nothing yet. Blue and green is two slots, each with an environment of its own, since a TCP port is unique across one environment and both slots must expose the same MLLP ports. The switch between them waits on the engine: a planned handover of the engine lease from the working engine to the waiting one, on request, so that a switch hands the work over rather than stopping one engine and waiting for the other to take the lease.
- We will write this example once Pathways hands the lease over on request. Until then, the [production example](../production) keeps a warm standby beside the working engine in one slot.

## When to choose it

Not yet. When it lands, choose it to upgrade the engine or your channels with intake open, and to switch back if the new version misbehaves.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Nothing: there is no Terraform here yet, so there is nothing to apply.

## What it does not cover

- Everything, for now: there is no Terraform here.
```
