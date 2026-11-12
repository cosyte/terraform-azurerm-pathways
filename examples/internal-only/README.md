# examples/internal-only

**Shape:** Internal only, no public ingress.

Pathways with no public ingress anywhere: a private environment, a private Key Vault and database, no storage account, and senders on your own network only.

## What it builds

- The module as in the basic example, with the private defaults written out: an internal environment, the Key Vault's public endpoint closed, and the address guard set to your network's own ranges.
- A private DNS zone for the environment's default domain, linked to the network, so senders connect by name rather than by address.

## When to choose it

Every sender is on your virtual network or a network connected to it, or your policy forbids public endpoints on anything that holds patient data.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- The private DNS zone, by the month, and the queries it answers.

## What it does not cover

- The Log Analytics workspace keeps Azure's public endpoints for ingestion and query; reading it still needs a role on it. Closing them takes an Azure Monitor Private Link Scope, which the module does not create.
- The VPN or ExpressRoute that connects other networks: yours to set up.
- The machine that applies must be inside the network, since the Key Vault is reached only through its private endpoint.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
