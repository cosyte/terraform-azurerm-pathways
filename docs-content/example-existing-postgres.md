---
id: example-existing-postgres
title: The existing PostgreSQL example
sidebar_label: existing-postgres
description: "Pathways on a PostgreSQL server you already run. The module makes no server; the app reads the database URL from a Key Vault secret you put there yourself."
---

# The existing PostgreSQL example

[`examples/existing-postgres`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/existing-postgres) is the shape **an existing postgresql server**. Pathways on a PostgreSQL server you already run. The module makes no server; the app reads the database URL from a Key Vault secret you put there yourself.

## What it deploys

- The identity, the workspace, the Key Vault with its private endpoint, and the slot `blue` with its app and migrate job, as in the basic example.
- No PostgreSQL server. With `existing_postgres`, the app and the migrate job read `PATHWAYS_DATABASE_URL` from the vault secret `pathways-database-url`, which you create. The module never sees the URL, so it and its password stay out of the Terraform state.
- Apply in two steps, as the comment at the top of `main.tf` shows: make the Key Vault first, put the database URL and the master key in it, then apply the rest.

## When to choose it

A platform team already runs PostgreSQL for you, or your messages must live on a server with its own backup, replication or audit setup.

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- No database server from this module: your server is billed as it is today.
- The app's replica, the Key Vault's private endpoint and operations, Log Analytics, the migrate job while it runs, and data transfer, as in the basic example.

## What it does not cover

- The server's network, TLS, backups and high availability are yours. The app reaches it from the environment's subnet, and the server must take TLS.
- The user in the URL creates the engine's tables when the engine or the migrate job first runs: give it that right on the database.
- The module does not check the URL: a wrong one shows as a revision that does not start and an error in the app's logs.

## Files

Every file in `examples/existing-postgres`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `README.md`

````markdown title="examples/existing-postgres/README.md"
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
````

### `main.tf`

```hcl title="examples/existing-postgres/main.tf"
# Pathways on a PostgreSQL server you already run. The module makes no server: the app and the
# migrate job read the database URL from a Key Vault secret you put there yourself, so the URL and
# its password never pass through Terraform or its state. Every name, id and range here is a
# placeholder: replace them with your own. Nothing in this example is applied by our CI.
#
# Apply in two steps. The first makes the Key Vault, the identity and the logs; put the database URL
# secret and the master key in the vault; the second makes the app, which reads both as it starts:
#
#   terraform apply -target=module.pathways.module.key_vault
#   az keyvault secret set --vault-name kv-pw-example --name pathways-database-url --file database-url.txt
#   az keyvault secret set --vault-name kv-pw-example --name pathways-key-2026-11 --file key.txt
#   terraform apply

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

  # One MLLP source on 2575; pathways.yaml's probes block listens on 0.0.0.0:9091, and its storage
  # block reads PATHWAYS_DATABASE_URL with tls set.
  mllp_ports            = [2575]
  ingress_allowed_cidrs = ["10.20.0.0/16"]

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  # Your server: the URL is in the vault secret pathways-database-url, in the form
  # postgres://<user>:<password>@<host>:5432/<database>. The server must take TLS, and the app's
  # subnet must reach it.
  existing_postgres = {
    database_url_secret_name = "pathways-database-url"
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
  description = "The slot's environment address (where senders connect for MLLP), app and migrate job."
  value       = module.pathways.slots
}

output "database_url_secret_name" {
  description = "The Key Vault secret the app reads the database URL from."
  value       = module.pathways.database_url_secret_name
}
```

### `tests/example.tftest.hcl`

```hcl title="examples/existing-postgres/tests/example.tftest.hcl"
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

run "plans_without_a_server_reading_your_secret" {
  command = plan

  assert {
    condition     = output.database_url_secret_name == "pathways-database-url"
    error_message = "The app must read the database URL from the secret you put in the vault."
  }

  assert {
    condition     = output.slots["blue"].app_name == "pw-example-blue"
    error_message = "The example must plan its one slot."
  }
}
```

### `versions.tf`

```hcl title="examples/existing-postgres/versions.tf"
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
