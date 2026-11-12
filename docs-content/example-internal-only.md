---
id: example-internal-only
title: The internal only example
sidebar_label: internal-only
description: "Pathways with no public ingress anywhere: a private environment, a private Key Vault and database, no storage account, and senders on your own network only."
---

# The internal only example

[`examples/internal-only`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/internal-only) is the shape **internal only, no public ingress**. Pathways with no public ingress anywhere: a private environment, a private Key Vault and database, no storage account, and senders on your own network only.

## What it deploys

- The module as in the basic example, with the private defaults written out: an internal environment, the Key Vault's public endpoint closed, and the address guard set to your network's own ranges.
- A private DNS zone for the environment's default domain, linked to the network, so senders connect by name rather than by address.

## When to choose it

Every sender is on your virtual network or a network connected to it, or your policy forbids public endpoints on anything that holds patient data.

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- The private DNS zone, by the month, and the queries it answers.

## What it does not cover

- The Log Analytics workspace keeps Azure's public endpoints for ingestion and query; reading it still needs a role on it. Closing them takes an Azure Monitor Private Link Scope, which the module does not create.
- The VPN or ExpressRoute that connects other networks: yours to set up.
- The machine that applies must be inside the network, since the Key Vault is reached only through its private endpoint.

## Files

Every file in `examples/internal-only`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `README.md`

````markdown title="examples/internal-only/README.md"
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
````

### `main.tf`

```hcl title="examples/internal-only/main.tf"
# Pathways with no public ingress anywhere: the environment has only a private address in your
# virtual network, the Key Vault and the database have no public endpoint, there is no storage
# account, and the address guard admits only your network's own range. Senders reach the engine over
# the virtual network or a network connected to it (a VPN or ExpressRoute), by a name in a private DNS
# zone this example adds. Apply from a machine inside the network: the Key Vault is reached only
# through its private endpoint. Every name, id and range here is a placeholder: replace them with
# your own. Nothing in this example is applied by our CI.

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

variable "virtual_network_id" {
  description = "The virtual network the environment runs in."
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example"
}

variable "network_cidrs" {
  description = "Your network's own address ranges: the virtual network and the networks connected to it."
  type        = list(string)
  default     = ["10.20.0.0/16", "10.30.0.0/16"]
}

locals {
  resource_group_name = "rg-pathways-example"
  slot                = module.pathways.slots["blue"]
}

module "pathways" {
  source = "../.."

  name                = "pw-internal"
  resource_group_name = local.resource_group_name
  location            = "eastus2"

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = "${var.virtual_network_id}/subnets/snet-pathways-blue"
    }
  }

  # The module's default, written out: a private address only.
  internal_load_balancer_enabled = true
  ingress_allowed_cidrs          = var.network_cidrs

  # pathways.yaml's probes block listens on 0.0.0.0:9091.
  mllp_ports = [2575]

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = "${var.virtual_network_id}/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/pathways-internal.postgres.database.azure.com"
  }

  # The private endpoint, and the public endpoint left closed (the default, written out).
  key_vault = {
    public_network_access_enabled = false
    private_endpoint_subnet_id    = "${var.virtual_network_id}/subnets/snet-endpoints"
    private_dns_zone_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  tags = {
    environment = "example"
  }
}

# A name for senders to use in place of the static address: an internal environment's default
# domain resolves only through a private zone of that name.
resource "azurerm_private_dns_zone" "environment" {
  name                = local.slot.default_domain
  resource_group_name = local.resource_group_name
}

resource "azurerm_private_dns_a_record" "apps" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.environment.name
  resource_group_name = local.resource_group_name
  ttl                 = 300
  records             = [local.slot.static_ip]
}

resource "azurerm_private_dns_zone_virtual_network_link" "environment" {
  name                  = "link-pw-internal-blue"
  resource_group_name   = local.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.environment.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
}

output "mllp_endpoint" {
  description = "Where senders on your network connect for MLLP: the environment's private address, the app's name in the private zone, and the port."
  value = {
    address = local.slot.static_ip
    name    = local.slot.fqdn
    port    = 2575
  }
}
```

### `tests/example.tftest.hcl`

```hcl title="examples/internal-only/tests/example.tftest.hcl"
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

run "plans_a_private_slot_and_its_zone" {
  command = plan

  assert {
    condition     = output.mllp_endpoint.port == 2575
    error_message = "The example must expose its MLLP port."
  }

  assert {
    condition     = azurerm_private_dns_a_record.apps.name == "*"
    error_message = "Every name in the environment's zone must point at its static address."
  }
}
```

### `versions.tf`

```hcl title="examples/internal-only/versions.tf"
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
