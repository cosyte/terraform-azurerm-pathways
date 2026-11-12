# examples/production

**Shape:** Production, one node with its warm standby.

One slot for production traffic: one engine working and a second replica waiting as its warm standby, a zone-redundant PostgreSQL server, a year of logs and every schema change run from the migrate job.

## What it builds

- The identity, the workspace with 365 days of retention, and the Key Vault with its private endpoint, in `rg-pathways-prod`.
- The PostgreSQL server `psql-pw-prod`: `GP_Standard_D4ds_v5`, 128 GiB, 35 days of backups, its primary in zone 1 and a high-availability standby in zone 2 that Azure fails over to, and a Microsoft Entra group as its administrator.
- The app `pw-prod-blue` with `standby_replica = true`: two replicas of 2 vCPU and 4 GiB, both started with `--standby`. The first to ask takes the engine lease and runs every channel; the other holds no lease, opens no listener and answers `/readyz` with 503 `standby`, so the ingress sends it nothing. When the working engine stops, the standby takes over within about 20 seconds with the default lease.
- The engine starts with `--no-migrate`, so schema changes run only from the migrate job `pw-prod-blue-migrate`.
- Alarms on the engine's own metrics: a metrics collector beside the engine in each replica, an Application Insights resource `appi-pw-prod` on the workspace, and five metric alerts (store down, oldest pending age, queue depth, refused messages, settled destinations failing) that call the action group you name. Your `pathways.yaml` needs a `health` block on port 9090 with `plaintext: true`; see [the alarms](../../README.md#alarms-on-the-engines-metrics).
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
- The alarms: the collector's 0.25 vCPU and 0.5 GiB beside each replica, five metric alert rules, the metrics' data in the workspace (a few rows a minute), the health token's and the connection string's reads from Key Vault, and whatever your action group sends, such as SMS.

## What it does not cover

- A region lost: the engine, the database and its standby are in one region. The [geo-redundant backup example](../geo-redundant-backup) keeps the backups in a second one.
- An engine or a collector that stops reporting: Azure does not fire a metric alert on missing data, so the store down alert fires only while the engine reports that it cannot read its database.
- Several engines working at once: one engine holds the lease, and the standby only waits. See [multi-node](../multi-node).
- We have not yet confirmed against a live environment that Container Apps' TCP ingress sends nothing to a replica whose readiness probe fails, or how a new revision whose replicas start as standbys replaces the old one. Test both before you rely on them.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
