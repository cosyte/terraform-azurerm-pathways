# examples/existing-network

**Shape:** Bring your own virtual network.

Pathways in a virtual network your network team already runs, looked up by name, with the module's own resources in a resource group of their own.

## What it builds

- Lookups, not resources: the apps, database and endpoints subnets of `vnet-example` in `rg-network-example`, and the database and Key Vault private DNS zones in `rg-dns-example`. A plan stops with a clear error when one is missing.
- The resource group `rg-pathways-example`, and the module in it, as in the basic example.

## When to choose it

A network team owns the virtual network, its subnets and its DNS zones, often as the spoke of a hub, and you may not create anything in their resource groups.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for. The network, its zones and their links are billed to whoever runs them, as before.

## What it does not cover

- It creates no subnet, delegation, zone, zone link, route or network security group. The [prepare the network](https://docs.cosyte.com/terraform-azurerm-pathways/prepare-the-network) guide says what each needs.
- No storage account: with storage on, the network also needs the `privatelink.blob.core.windows.net` zone.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
