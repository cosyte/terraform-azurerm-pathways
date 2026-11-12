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
