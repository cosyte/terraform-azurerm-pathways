---
id: example-http-only
title: The HTTP only example
sidebar_label: http-only
description: "Pathways taking messages over HTTP only, such as FHIR or HL7 v2 posted by an application on your network, behind HTTP ingress that ends TLS."
---

# The HTTP only example

[`examples/http-only`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/http-only) is the shape **http only**. Pathways taking messages over HTTP only, such as FHIR or HL7 v2 posted by an application on your network, behind HTTP ingress that ends TLS.

## What it deploys

- The module with `http_port = 8080` and no MLLP port: the app gets HTTP ingress. Container Apps ends TLS on port 443 of the app's address and passes plain HTTP to the engine's HTTP source on 8080; plain HTTP from outside the environment is refused, and only `10.20.0.0/16` gets through.
- A private DNS zone named for the environment's default domain, with a record for every name in it pointing at the environment's static address, linked to the virtual network, so clients there resolve the app's name.
- The identity, the workspace, the Key Vault and the database, as in the basic example.

## When to choose it

Your clients post messages over HTTPS and nothing sends MLLP: FHIR, HL7 v2 over HTTP, or an application's webhook.

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- The private DNS zone, by the month, and the queries it answers.

## What it does not cover

- MLLP beside HTTP: an app takes one or the other in this release of the module.
- Your own domain name and certificate: clients use the app's address in the environment's default domain.
- Who may post: the address guard admits a range, and the HTTP source's own settings decide what it accepts.

## Files

Every file in `examples/http-only`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `README.md`

````markdown title="examples/http-only/README.md"
# examples/http-only

**Shape:** HTTP only.

Pathways taking messages over HTTP only, such as FHIR or HL7 v2 posted by an application on your network, behind HTTP ingress that ends TLS.

## What it builds

- The module with `http_port = 8080` and no MLLP port: the app gets HTTP ingress. Container Apps ends TLS on port 443 of the app's address and passes plain HTTP to the engine's HTTP source on 8080; plain HTTP from outside the environment is refused, and only `10.20.0.0/16` gets through.
- A private DNS zone named for the environment's default domain, with a record for every name in it pointing at the environment's static address, linked to the virtual network, so clients there resolve the app's name.
- The identity, the workspace, the Key Vault and the database, as in the basic example.

## When to choose it

Your clients post messages over HTTPS and nothing sends MLLP: FHIR, HL7 v2 over HTTP, or an application's webhook.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- The private DNS zone, by the month, and the queries it answers.

## What it does not cover

- MLLP beside HTTP: an app takes one or the other in this release of the module.
- Your own domain name and certificate: clients use the app's address in the environment's default domain.
- Who may post: the address guard admits a range, and the HTTP source's own settings decide what it accepts.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
````

### `main.tf`

```hcl title="examples/http-only/main.tf"
# Pathways taking messages over HTTP only, such as FHIR or HL7 v2 posted by an application on your
# network: no MLLP, no storage account and no SFTP. The app gets HTTP ingress: Container Apps ends
# TLS on port 443 of the app's address and passes plain HTTP to the engine's HTTP source on 8080,
# and plain HTTP from outside the environment is refused. The environment is internal to your
# virtual network, so the example adds the private DNS zone that resolves the app's name there.
# Every name, id and range here is a placeholder: replace them with your own. Nothing in this example
# is applied by our CI.

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
  description = "The virtual network the environment runs in, which the app's private DNS zone is linked to."
  type        = string
  default     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example"
}

locals {
  resource_group_name = "rg-pathways-example"
  slot                = module.pathways.slots["blue"]
}

module "pathways" {
  source = "../.."

  name                = "pw-http"
  resource_group_name = local.resource_group_name
  location            = "eastus2"

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = "${var.virtual_network_id}/subnets/snet-pathways-blue"
    }
  }

  # The channel's HTTP source listens on 0.0.0.0:8080 with plaintext: true, since TLS ends at the
  # ingress; pathways.yaml's probes block listens on 0.0.0.0:9091. Only the clients' range reaches it.
  http_port             = 8080
  ingress_allowed_cidrs = ["10.20.0.0/16"]

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = "${var.virtual_network_id}/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/pathways-http.postgres.database.azure.com"
  }

  key_vault = {
    private_endpoint_subnet_id = "${var.virtual_network_id}/subnets/snet-endpoints"
    private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  tags = {
    environment = "example"
  }
}

# An internal environment's default domain resolves nowhere until a private zone of that name points
# every name in it at the environment's static address.
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
  name                  = "link-pw-http-blue"
  resource_group_name   = local.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.environment.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
}

output "http_endpoint" {
  description = "Where clients on the virtual network send their requests, over HTTPS on port 443."
  value       = "https://${local.slot.fqdn}"
}
```

### `tests/example.tftest.hcl`

```hcl title="examples/http-only/tests/example.tftest.hcl"
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

run "plans_http_ingress_and_the_environment_zone" {
  command = plan

  assert {
    condition     = azurerm_private_dns_a_record.apps.name == "*"
    error_message = "Every name in the environment's zone must point at its static address."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.environment.registration_enabled == false
    error_message = "The zone must be linked to the network without registration."
  }
}
```

### `versions.tf`

```hcl title="examples/http-only/versions.tf"
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
