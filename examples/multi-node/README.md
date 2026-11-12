# examples/multi-node

**Shape:** Several active nodes on one database.

Not yet supported. This folder holds no Terraform, on purpose.

## Status

**Not yet supported.** There is no Terraform in this folder, and CI checks that none is added
until the engine supports this shape.

## What it builds

- Nothing yet. Several engines working at once on one database waits on the engine: today one engine holds the engine lease on a database, a second is refused or waits as a standby, and the engine does not yet share channels and their work between engines that are active together. Running more than one replica of the app that is not a standby would have the extra engines refused.
- We will write this example once Pathways runs several active engines on one database. Until then, the [production example](../production) runs one engine with a warm standby, which is what Pathways runs safely today.

## When to choose it

Not yet. When it lands, choose it when one engine cannot keep up with your traffic.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Nothing: there is no Terraform here yet, so there is nothing to apply.

## What it does not cover

- Everything, for now: there is no Terraform here.
