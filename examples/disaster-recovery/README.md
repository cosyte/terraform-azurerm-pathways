# examples/disaster-recovery

**Shape:** A second region with promotion for disaster recovery.

Not yet supported. This folder holds no Terraform, on purpose.

## Status

**Not yet supported.** There is no Terraform in this folder, and CI checks that none is added
until the engine supports this shape.

## What it builds

- Nothing yet. A second region with promotion is a deployment kept ready in another region on a copy of the database, promoted to take over when the first region is lost. It waits on the engine: the engine must be sure the first region's engine can no longer write once the copy is promoted, and take over on the promoted database without sending what was already sent as new.
- We will write this example once Pathways supports a second region with promotion. Until then, the [geo-redundant backup example](../geo-redundant-backup) keeps the backups in a second region and documents a restore there.

## When to choose it

Not yet. When it lands, choose it when a region's loss must not stop intake for longer than a promotion takes.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Nothing: there is no Terraform here yet, so there is nothing to apply.

## What it does not cover

- Everything, for now: there is no Terraform here.
