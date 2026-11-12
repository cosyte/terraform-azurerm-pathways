---
id: performance
title: Performance
sidebar_label: Performance
description: "What sets the engine's speed on Azure Container Apps, which inputs size it, and how long the module's own checks take at each release."
---

# Performance

The module runs no code of its own once it is applied: the engine is Pathways, and its throughput,
latency and memory are measured on the
[Pathways performance page](https://docs.cosyte.com/pathways/performance). What the module sets is
what the engine runs on. The time its own checks take at each release is in
[Current numbers](#current-numbers) below.

## What sizes the engine

| Input | Default | What it sets |
| --- | --- | --- |
| `cpu` | `1` | the vCPU of the engine's container |
| `memory` | `"2Gi"` | its memory: twice `cpu` in Gi, as Container Apps requires on the Consumption profile |
| `postgres.sku_name` | `"GP_Standard_D2ds_v5"` | the database server's compute |
| `postgres.storage_mb` | `32768` | the database's storage |

The app runs one replica, on the environment's Consumption workload profile. It does not scale out:
Pathways runs one engine per database, and a second engine waits as a standby. To go faster, give
the one replica more `cpu` and `memory`, and the server a larger SKU, and measure your own messages
with the Pathways benchmark before and after.

## What we measure here

At each release, the release workflow runs the module's validation and its tests on a GitHub-hosted
runner and records how long each took. These are the module's own checks, not the engine: they say
how long a contributor waits, and they change when a module or a test is added. They are not a
benchmark of anything Azure runs.

## Current numbers

The numbers for this section are measured on `main` at each release and filled in when the
release is built. They are never typed by hand.
