---
id: prepare-the-network
title: Prepare the network
sidebar_label: Prepare the network
description: "The subnets, delegations and private DNS zones the module needs from your virtual network, which inputs take each one, and how senders reach the engine."
---

# Prepare the network

The module does not create the virtual network, its subnets or its private DNS zones: you pass
their ids. This page lists what it needs and which input takes each. The
[complete example](./example-complete.md) creates all of them, and is a working starting point.

## The subnets

| Subnet                       | Delegated to                                | Size                    | Input                                               |
| ---------------------------- | ------------------------------------------- | ----------------------- | --------------------------------------------------- |
| One per slot, for its environment | `Microsoft.App/environments`           | a `/27` at least        | `slots.<slot>.infrastructure_subnet_id`             |
| The database's               | `Microsoft.DBforPostgreSQL/flexibleServers` | Azure's minimum for it  | `postgres.delegated_subnet_id`                      |
| Private endpoints            | nothing                                     | room for one or two     | `key_vault.private_endpoint_subnet_id`, `storage.private_endpoint_subnet_id` |

Each slot needs its own subnet: one subnet holds one Container Apps environment, and the plan
refuses two slots on the same one. The private endpoints of the Key Vault and of the storage
account can share a subnet, as they do in the complete example.

In Terraform, a delegation is a block on the subnet:

```hcl
resource "azurerm_subnet" "apps_blue" {
  name                 = "snet-apps-blue"
  resource_group_name  = "rg-network-example"
  virtual_network_name = "vnet-example"
  address_prefixes     = ["10.40.0.0/23"]

  delegation {
    name = "container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
```

## The private DNS zones

| Zone                                         | For                       | Input                           |
| -------------------------------------------- | ------------------------- | ------------------------------- |
| a name ending in `.postgres.database.azure.com` | the database server    | `postgres.private_dns_zone_id`  |
| `privatelink.vaultcore.azure.net`            | the Key Vault's endpoint  | `key_vault.private_dns_zone_id` |
| `privatelink.blob.core.windows.net`          | the storage account's endpoint, with storage on | `storage.private_dns_zone_id` |

Link each zone to the virtual network, with `azurerm_private_dns_zone_virtual_network_link`, before
the module creates the server and the endpoints: they register in the zones and resolve through
them. The complete example says so with `depends_on` on its module call. The plan refuses a database
zone whose name does not end in `.postgres.database.azure.com`.

## How senders reach the engine

By default each slot's environment has an internal load balancer: a private address in its subnet,
and no public address. The `slots` output gives it as `static_ip`. Senders on the virtual network,
or on a network peered or connected with it, connect there on the MLLP ports.

`ingress_allowed_cidrs` names the ranges allowed to connect; every other address is denied. Leave
it empty to allow everything that can route to the private address, or name your senders' ranges.
Senders on the internet need a public environment, `internal_load_balancer_enabled = false`, and
then the plan refuses an empty `ingress_allowed_cidrs`: [Deployment shapes](./deployment-shapes.md#public-intake)
says what that opens.

## How you apply

The Key Vault denies every network by default, and the apply writes the database URL secret into
it, so the machine that runs `terraform apply` needs a way in. Either run it inside the virtual
network (or a network peered with it), where the vault's private endpoint resolves, or set
`key_vault.public_network_access_enabled = true` with `key_vault.allowed_ip_ranges` naming the
runner's public address. The plan refuses a vault that nothing could reach.

## Related

- [Inputs and outputs](./inputs-and-outputs.md#slots): `slots`, `postgres`, `key_vault` and
  `ingress_allowed_cidrs`.
- [The complete example](./example-complete.md#files): the network in Terraform.
