---
id: example-existing-network
title: The existing network example
sidebar_label: existing-network
description: "Pathways in a virtual network your network team already runs, looked up by name, with the module's own resources in a resource group of their own."
---

# The existing network example

[`examples/existing-network`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/existing-network) is the shape **bring your own virtual network**. Pathways in a virtual network your network team already runs, looked up by name, with the module's own resources in a resource group of their own.

## What it deploys

- Lookups, not resources: the apps, database and endpoints subnets of `vnet-example` in `rg-network-example`, and the database and Key Vault private DNS zones in `rg-dns-example`. A plan stops with a clear error when one is missing.
- The resource group `rg-pathways-example`, and the module in it, as in the basic example.

## When to choose it

A network team owns the virtual network, its subnets and its DNS zones, often as the spoke of a hub, and you may not create anything in their resource groups.

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for. The network, its zones and their links are billed to whoever runs them, as before.

## What it does not cover

- It creates no subnet, delegation, zone, zone link, route or network security group. The [prepare the network](./prepare-the-network.md) guide says what each needs.
- No storage account: with storage on, the network also needs the `privatelink.blob.core.windows.net` zone.

## Files

Every file in `examples/existing-network`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `README.md`

````markdown title="examples/existing-network/README.md"
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
````

### `main.tf`

```hcl title="examples/existing-network/main.tf"
# Pathways in a virtual network your network team already runs. The example looks the network up by
# name, so a plan stops with a clear error when a subnet or a zone is missing, and it creates
# nothing in the network's resource group: only the module's own resources, in a group of their own.
# Prepare the network first (the "Prepare the network" guide says what each subnet and zone needs).
# Every name here is a placeholder: replace them with your own. Nothing in this example is applied by
# our CI.

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

variable "network" {
  description = "The existing virtual network and the names of what Pathways uses in it."
  type = object({
    resource_group_name    = string
    virtual_network_name   = string
    apps_subnet_name       = string
    postgres_subnet_name   = string
    endpoints_subnet_name  = string
    dns_resource_group     = string
    postgres_dns_zone_name = string
  })
  default = {
    resource_group_name    = "rg-network-example"
    virtual_network_name   = "vnet-example"
    apps_subnet_name       = "snet-pathways-blue"
    postgres_subnet_name   = "snet-postgres"
    endpoints_subnet_name  = "snet-endpoints"
    dns_resource_group     = "rg-dns-example"
    postgres_dns_zone_name = "pathways-example.postgres.database.azure.com"
  }
}

variable "sender_cidrs" {
  description = "The address ranges your MLLP senders connect from, inside or connected to the virtual network."
  type        = list(string)
  default     = ["10.20.0.0/16"]
}

data "azurerm_subnet" "apps" {
  name                 = var.network.apps_subnet_name
  virtual_network_name = var.network.virtual_network_name
  resource_group_name  = var.network.resource_group_name
}

data "azurerm_subnet" "postgres" {
  name                 = var.network.postgres_subnet_name
  virtual_network_name = var.network.virtual_network_name
  resource_group_name  = var.network.resource_group_name
}

data "azurerm_subnet" "endpoints" {
  name                 = var.network.endpoints_subnet_name
  virtual_network_name = var.network.virtual_network_name
  resource_group_name  = var.network.resource_group_name
}

data "azurerm_private_dns_zone" "postgres" {
  name                = var.network.postgres_dns_zone_name
  resource_group_name = var.network.dns_resource_group
}

data "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.network.dns_resource_group
}

# The module's resources go in a group of their own, apart from the network's.
resource "azurerm_resource_group" "pathways" {
  name     = "rg-pathways-example"
  location = "eastus2"
}

module "pathways" {
  source = "../.."

  name                = "pw-example"
  resource_group_name = azurerm_resource_group.pathways.name
  location            = azurerm_resource_group.pathways.location

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = data.azurerm_subnet.apps.id
    }
  }

  # pathways.yaml's probes block listens on 0.0.0.0:9091.
  mllp_ports            = [2575]
  ingress_allowed_cidrs = var.sender_cidrs

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = data.azurerm_subnet.postgres.id
    private_dns_zone_id = data.azurerm_private_dns_zone.postgres.id
  }

  key_vault = {
    private_endpoint_subnet_id = data.azurerm_subnet.endpoints.id
    private_dns_zone_id        = data.azurerm_private_dns_zone.key_vault.id
  }
}

output "slots" {
  description = "The slot's environment address (where senders connect for MLLP), app and migrate job."
  value       = module.pathways.slots
}
```

### `tests/example.tftest.hcl`

```hcl title="examples/existing-network/tests/example.tftest.hcl"
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

# The network the example looks up, as a lookup would find it.
override_data {
  target = data.azurerm_subnet.apps
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-pathways-blue"
  }
}

override_data {
  target = data.azurerm_subnet.postgres
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
  }
}

override_data {
  target = data.azurerm_subnet.endpoints
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
  }
}

override_data {
  target = data.azurerm_private_dns_zone.postgres
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-example/providers/Microsoft.Network/privateDnsZones/pathways-example.postgres.database.azure.com"
  }
}

override_data {
  target = data.azurerm_private_dns_zone.key_vault
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }
}

run "plans_in_the_network_it_looks_up" {
  command = plan

  assert {
    condition     = azurerm_resource_group.pathways.name == "rg-pathways-example"
    error_message = "The module's resources must go in a group of their own."
  }

  assert {
    condition     = output.slots["blue"].app_name == "pw-example-blue"
    error_message = "The example must plan its one slot."
  }
}
```

### `versions.tf`

```hcl title="examples/existing-network/versions.tf"
terraform {
  required_version = ">= 1.11.0"

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
      version = ">= 3.7.0, < 4.0.0"
    }
  }
}
```
