# examples/existing-postgres

**Shape:** An existing PostgreSQL server.

Pathways on a PostgreSQL server you already run. The module makes no server; the app reads the database URL from a Key Vault secret you put there yourself.

## What it builds

- The identity, the workspace, the Key Vault with its private endpoint, and the slot `blue` with its app and migrate job, as in the basic example.
- No PostgreSQL server. With `existing_postgres`, the app and the migrate job read `PATHWAYS_DATABASE_URL` from the vault secret `pathways-database-url`, which you create. The module never sees the URL, so it and its password stay out of the Terraform state.
- Apply in two steps, as the comment at the top of `main.tf` shows: make the Key Vault first, put the database URL and the master key in it, then apply the rest.

## When to choose it

A platform team already runs PostgreSQL for you, or your messages must live on a server with its own backup, replication or audit setup.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- No database server from this module: your server is billed as it is today.
- The app's replica, the Key Vault's private endpoint and operations, Log Analytics, the migrate job while it runs, and data transfer, as in the basic example.

## What it does not cover

- The server's network, TLS, backups and high availability are yours. The app reaches it from the environment's subnet, and the server must take TLS.
- The user in the URL creates the engine's tables when the engine or the migrate job first runs: give it that right on the database.
- The module does not check the URL: a wrong one shows as a revision that does not start and an error in the app's logs.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
