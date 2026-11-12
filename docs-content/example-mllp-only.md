---
id: example-mllp-only
title: The MLLP only example
sidebar_label: mllp-only
description: "Pathways taking HL7 v2 over MLLP, on three TCP ports, from senders outside your network, and nothing else."
---

# The MLLP only example

[`examples/mllp-only`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/mllp-only) is the shape **mllp only over tcp ingress**. Pathways taking HL7 v2 over MLLP, on three TCP ports, from senders outside your network, and nothing else.

## What it deploys

- The module as in the basic example, with `internal_load_balancer_enabled = false`: the environment gets a public address.
- TCP ingress on 2575 (the main port), 2576 and 2577 (additional port mappings), reachable only from the senders' named ranges; every other address is denied.
- No HTTP ingress, no storage account and no SFTP.

## When to choose it

Your senders reach you over the internet, cannot use a VPN or ExpressRoute into your network, and speak only MLLP.

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- Data transfer in from the senders and out to them.

## What it does not cover

- MLLP has no authentication of its own. The address guard is the only check the platform makes: require mutual TLS on each MLLP source in your project as well.
- We prefer a private connection to a public address: the [internal only example](./example-internal-only.md) is that shape.
- Container Apps takes at most six TCP ports per app, and each port once per environment.

## Files

Every file in `examples/mllp-only`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `README.md`

````markdown title="examples/mllp-only/README.md"
# examples/mllp-only

**Shape:** MLLP only over TCP ingress.

Pathways taking HL7 v2 over MLLP, on three TCP ports, from senders outside your network, and nothing else.

## What it builds

- The module as in the basic example, with `internal_load_balancer_enabled = false`: the environment gets a public address.
- TCP ingress on 2575 (the main port), 2576 and 2577 (additional port mappings), reachable only from the senders' named ranges; every other address is denied.
- No HTTP ingress, no storage account and no SFTP.

## When to choose it

Your senders reach you over the internet, cannot use a VPN or ExpressRoute into your network, and speak only MLLP.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- Data transfer in from the senders and out to them.

## What it does not cover

- MLLP has no authentication of its own. The address guard is the only check the platform makes: require mutual TLS on each MLLP source in your project as well.
- We prefer a private connection to a public address: the [internal only example](../internal-only) is that shape.
- Container Apps takes at most six TCP ports per app, and each port once per environment.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
````

### `main.tf`

```hcl title="examples/mllp-only/main.tf"
# Pathways taking HL7 v2 over MLLP from senders outside your network, on TCP ingress, and nothing
# else: no HTTP source, no storage account and no SFTP. The environment has a public address, and
# only the senders' named ranges reach its three MLLP ports; every other address is denied. MLLP has
# no authentication of its own, so require mutual TLS on each MLLP source as well. Every name, id and
# range here is a placeholder: replace them with your own (198.51.100.0/24 and 203.0.113.0/24 are
# documentation ranges). Nothing in this example is applied by our CI.

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

variable "sender_cidrs" {
  description = "The public address ranges of your MLLP senders. Name them as narrowly as you can: the plan refuses a range wider than a /8."
  type        = list(string)
  default     = ["198.51.100.0/24", "203.0.113.0/24"]
}

module "pathways" {
  source = "../.."

  name                = "pw-mllp"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-pathways-blue"
    }
  }

  # Three MLLP sources, one port each: ADT, orders and results. The first is the app's main ingress
  # port and the other two are additional TCP port mappings; Container Apps takes at most six.
  mllp_ports = [2575, 2576, 2577]

  # A public address, reachable only from the senders' ranges.
  internal_load_balancer_enabled = false
  ingress_allowed_cidrs          = var.sender_cidrs

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/pathways-mllp.postgres.database.azure.com"
  }

  key_vault = {
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
    private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  tags = {
    environment = "example"
  }
}

output "mllp_endpoint" {
  description = "Where your senders connect: the environment's public address and the MLLP ports."
  value = {
    address = module.pathways.slots["blue"].static_ip
    ports   = module.pathways.mllp_ports
  }
}
```

### `tests/example.tftest.hcl`

```hcl title="examples/mllp-only/tests/example.tftest.hcl"
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

run "plans_three_mllp_ports_for_named_senders" {
  command = plan

  assert {
    condition     = output.mllp_endpoint.ports == tolist([2575, 2576, 2577])
    error_message = "The example must expose its three MLLP ports."
  }
}
```

### `versions.tf`

```hcl title="examples/mllp-only/versions.tf"
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
