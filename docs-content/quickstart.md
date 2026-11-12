---
id: quickstart
title: Deploy the basic example
sidebar_label: Quickstart
description: "Deploy the smallest example, one slot of Pathways on Azure Container Apps in a network you have, from an empty folder to a running engine, then remove it."
---

# Deploy the basic example

This tutorial deploys [`examples/basic`](./example-basic.md), the smallest configuration of the
module: one slot of Pathways, its database, its Key Vault and its logs, in a virtual network you
already have. At the end the engine runs on Azure Container Apps, listening for MLLP on port 2575
on your network, and you remove it all again.

It creates resources that Azure bills while they exist; the
[example's page](./example-basic.md#what-it-costs-to-leave-running) says which. We have not yet run
these steps against a real subscription ourselves (see the [overview](./intro.md#status)).

## Before you start

- What [Installation](./installation.md#what-you-need) lists: Terraform, the Azure CLI signed in
  with a role that can assign roles, and your project's image pinned by digest.
- The network, from [Prepare the network](./prepare-the-network.md): a subnet for the slot
  delegated to `Microsoft.App/environments`, a subnet for the database delegated to
  `Microsoft.DBforPostgreSQL/flexibleServers`, a subnet for private endpoints, and the two private
  DNS zones, each linked to the virtual network.
- A shell on a machine inside that virtual network, or peered with it: the apply writes a secret
  to the Key Vault, which only its private endpoint reaches.

## 1. Make the resource group

The example deploys into `rg-pathways-example` in `eastus2`, and expects it to exist:

```bash
az group create --name rg-pathways-example --location eastus2
```

## 2. Copy the example

```bash
git clone https://github.com/cosyte/terraform-azurerm-pathways.git
cp -r terraform-azurerm-pathways/examples/basic pathways-basic
cd pathways-basic
```

In `main.tf`, point the module at a release rather than at the clone:

```hcl
module "pathways" {
  source = "github.com/cosyte/terraform-azurerm-pathways?ref=v0.0.1"
```

Then replace each placeholder id in `main.tf` with yours: the slot's `infrastructure_subnet_id`, the
database's `delegated_subnet_id` and `private_dns_zone_id`, and the Key Vault's
`private_endpoint_subnet_id` and `private_dns_zone_id`. Set `ingress_allowed_cidrs` to the range
your MLLP senders connect from.

## 3. Give it your subscription and image

Make `terraform.tfvars` beside `main.tf`, with your own values:

```hcl
subscription_id = "00000000-0000-0000-0000-000000000000"
image           = "registry.example.com/integration/my-project:3f2a91c@sha256:<64 hex digits>"
```

The image must carry its digest. Its `pathways.yaml` needs a `probes` block on port 9091 with host
`0.0.0.0`, `storage.postgres` reading `PATHWAYS_DATABASE_URL` with `tls` set, and the key
`PATHWAYS_KEY_2026_11` under `encryption.keys`: the
[complete example's project](./example-complete.md#projectpathwaysyaml) is one that does.

## 4. Plan

```bash
terraform init
terraform plan
```

The plan lists what will be created and changes nothing. If it stops with an error from a
variable's check, the message says which value and why; [the reference](./inputs-and-outputs.md)
lists every check.

## 5. Make the Key Vault, then put the master key in it

The app reads its master key from the Key Vault when its revision starts, and the module never
makes or reads a key. So apply the vault first, with what it depends on:

```bash
terraform apply -target=module.pathways.module.key_vault
```

Terraform warns that a targeted apply is not a full one; that is expected here. This step makes the
identity, the workspace, the database server (several minutes) and the vault with the database URL
in it. Then make a master key, 32 random bytes in base64, and store it under the name the example
gives in `encryption_key_secrets`:

```bash
az keyvault secret set --vault-name kv-pw-example --name pathways-key-2026-11 \
  --value "$(openssl rand -base64 32)"
```

Keep a copy of the key where you keep your other secrets: every message the engine stores is
encrypted under it. [Encrypt stored messages](https://docs.cosyte.com/pathways/encrypt-stored-messages)
in the Pathways docs says how keys rotate.

## 6. Apply the rest

```bash
terraform apply
```

This makes the Container Apps environment, the app and the migrate job. The app starts with the
image's own command, `pathways start -C /project`, which applies the expand steps of the schema
itself before it takes the engine lease.

## 7. Check it runs

The `slots` output gives the environment's address, where senders connect on port 2575:

```bash
terraform output slots
```

See the revision's health, and the engine's log since it started:

```bash
az containerapp revision list --name pw-example-blue --resource-group rg-pathways-example \
  --query "[].{name:name, health:properties.healthState, running:properties.runningState}" --output table
az containerapp logs show --name pw-example-blue --resource-group rg-pathways-example --tail 50
```

A revision whose health is `Healthy` passed its readiness probe on `/readyz`: the engine is up. If
it is not, [Troubleshooting](./troubleshooting.md) goes through the usual causes.

## 8. Remove it

```bash
terraform destroy
```

The Key Vault has purge protection, so Azure keeps it soft-deleted for its retention (90 days by
default) and its name, `kv-pw-example`, stays taken until then. A new deployment in the same
subscription needs another `name`.

## Next

- [Give partners SFTP access](./give-partners-sftp-access.md) and
  [store the engine's files in Blob Storage](./store-files-in-blob-storage.md).
- [Upgrade the engine and the module](./upgrade-the-engine-and-the-module.md), including the switch
  between two slots.
- [Deployment shapes](./deployment-shapes.md): what else the module can stand up.
