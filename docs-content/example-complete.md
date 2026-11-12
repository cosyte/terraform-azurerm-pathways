---
id: example-complete
title: The complete example
sidebar_label: complete
description: "Pathways on Azure end to end: the network, the module with storage and SFTP, and one channel. What it deploys, what it costs, and its files."
---

# The complete example

[`examples/complete`](https://github.com/cosyte/terraform-azurerm-pathways/tree/main/examples/complete)
stands Pathways up end to end from an empty subscription: the resource group, the virtual network,
its subnets and private DNS zones, then the module with its database, its Key Vault, a storage
account with SFTP for one partner, and one slot running the channel in `project/`. That channel
takes lab orders over MLLP and writes each as a file to the lab's SFTP container, where the lab
fetches it. Every name, id and range in it is a placeholder. Our CI validates it and never applies
it.

Apply it from a machine inside the virtual network, or peered with it: the Key Vault is reached only
through its private endpoint, and the apply writes the database URL secret and the storage key
there. The provider sets `storage_use_azuread = true`, since the account's shared keys are off.

## What it deploys

The network, in the resource group `rg-pw-example`:

- the virtual network `vnet-pw-example`, `10.40.0.0/16`;
- the subnet `snet-apps-blue`, `10.40.0.0/23`, delegated to `Microsoft.App/environments`;
- the subnet `snet-postgres`, `10.40.2.0/24`, delegated to `Microsoft.DBforPostgreSQL/flexibleServers`;
- the subnet `snet-endpoints`, `10.40.3.0/24`, for the two private endpoints;
- the private DNS zones `pathways-example.postgres.database.azure.com`,
  `privatelink.vaultcore.azure.net` and `privatelink.blob.core.windows.net`, each linked to the
  virtual network.

The module, in the same group, with what the [basic example](./example-basic.md#what-it-deploys)
deploys (the identity, the workspace, the database server, the Key Vault and the slot `blue`, named
from `pw-example`), taking MLLP on port 2575 from `10.40.0.0/16`, and also:

- the storage account `stpwexample`, with hierarchical namespace and SFTP on, its shared keys off,
  a blob private endpoint on `snet-endpoints`, and its public endpoint open only to
  `lab_sftp_ip_ranges`;
- a customer-managed key `storage-pw-example` in the Key Vault, with an identity of the account's own
  that reads it;
- the containers `pathways`, the engine's, and `sftp-lab`, the lab's;
- the SFTP user `lab`, signing in with `lab_ssh_public_key`, allowed to read, list and delete in
  `sftp-lab`;
- Storage Blob Data Contributor for the engine's identity on both containers, and the blob logs in
  the workspace.

The image you pass is built from `project/` on the Pathways image. You put the master key
`pathways-key-2026-11` in the vault before the app starts, as in the
[quickstart](./quickstart.md#5-make-the-key-vault-then-put-the-master-key-in-it).

## What it costs to leave running

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement with
Microsoft, set those.

Everything the [basic example](./example-basic.md#what-it-costs-to-leave-running) bills for, and:

Billed every hour it exists, whether a file moves or not:

- **SFTP on the storage account,** by the hour while `sftp_enabled` is true. Set
  `storage.sftp_enabled = false` and remove the user to stop it while the lab does not need it.
- **A second private endpoint,** the storage account's, by the hour, and the data through it.
- **The three private DNS zones,** each by the month, and the queries they answer.

Billed by use:

- **Storage:** the data stored, including deleted blobs kept for 7 days, the read, write and list
  operations, over SFTP and from the engine, at `LRS` redundancy.
- **Key Vault** key operations: the account wraps and unwraps its key with the vault.
- **Log Analytics:** the storage account's read, write and delete logs, on top of the basic
  example's.

The resource group, the virtual network and its subnets, the identities and the role assignments
cost nothing. `terraform destroy` removes every billed item; the Key Vault is then kept
soft-deleted, at no charge, for its retention.

## Files

Every file in `examples/complete`, as the repository holds it. `scripts/docs.sh` writes this section from the folder, and CI fails when the two differ.

### `main.tf`

```hcl title="examples/complete/main.tf"
# Pathways on Azure end to end: the resource group, the virtual network and its subnets, the private
# DNS zones, then the module with its database, its Key Vault, a storage account with SFTP for one
# partner, and one slot running the channel in project/. Every name, id and range here is a
# placeholder: replace them with your own. Nothing in this example is applied by our CI, which only
# validates it.
#
# Apply from a machine inside the virtual network (or peered with it): the Key Vault is reached only
# through its private endpoint, and the apply writes the database URL secret and the storage key there.

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  # The storage account's shared keys are off; the provider reaches its data plane with Microsoft
  # Entra ID instead. The module creates its containers through Azure Resource Manager.
  storage_use_azuread = true
}

variable "subscription_id" {
  description = "The subscription to deploy into."
  type        = string
}

variable "location" {
  description = "The Azure region."
  type        = string
  default     = "eastus2"
}

variable "image" {
  description = "Your project's image, built from project/ on the Pathways image and pinned by digest."
  type        = string
}

variable "lab_ssh_public_key" {
  description = "The lab's SSH public key, one line in OpenSSH form. The lab signs in to SFTP with it."
  type        = string
}

variable "lab_sftp_ip_ranges" {
  description = "The lab's public IPv4 addresses or ranges, allowed through the storage account's public endpoint for SFTP."
  type        = list(string)
}

locals {
  name = "pw-example"
  tags = { environment = "example" }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = ["10.40.0.0/16"]
  tags                = local.tags
}

# The Container Apps environment of the one slot: delegated, /27 at least.
resource "azurerm_subnet" "apps_blue" {
  name                 = "snet-apps-blue"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.40.0.0/23"]

  delegation {
    name = "container-apps"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.40.2.0/24"]

  delegation {
    name = "postgres"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# The private endpoints: the Key Vault's and the storage account's.
resource "azurerm_subnet" "endpoints" {
  name                 = "snet-endpoints"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.40.3.0/24"]
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "pathways-example.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = {
    postgres  = azurerm_private_dns_zone.postgres.name
    key_vault = azurerm_private_dns_zone.key_vault.name
    blob      = azurerm_private_dns_zone.blob.name
  }

  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = each.value
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = local.tags
}

module "pathways" {
  source = "../.."

  name                = local.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = azurerm_subnet.apps_blue.id
    }
  }

  # The channel in project/channels/orders-to-lab listens on 2575 for the hospital's MLLP sender, on
  # the virtual network only. pathways.yaml's probes block listens on 0.0.0.0:9091.
  mllp_ports            = [2575]
  ingress_allowed_cidrs = ["10.40.0.0/16"]

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = azurerm_subnet.postgres.id
    private_dns_zone_id = azurerm_private_dns_zone.postgres.id
  }

  key_vault = {
    private_endpoint_subnet_id = azurerm_subnet.endpoints.id
    private_dns_zone_id        = azurerm_private_dns_zone.key_vault.id
  }

  # The storage account, with SFTP for the lab. The lab fetches the orders the channel writes to its
  # container and removes each once fetched, so it reads, lists and deletes, and writes nothing.
  storage = {
    enabled                       = true
    private_endpoint_subnet_id    = azurerm_subnet.endpoints.id
    private_dns_zone_id           = azurerm_private_dns_zone.blob.id
    public_network_access_enabled = true
    allowed_ip_ranges             = var.lab_sftp_ip_ranges
    sftp_users = {
      lab = {
        ssh_public_keys = [var.lab_ssh_public_key]
        permissions     = ["read", "list", "delete"]
      }
    }
  }

  tags = local.tags

  # The server and the private endpoints resolve through the zones, so the links come first.
  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}

output "slots" {
  description = "Each slot's environment address (where the MLLP sender connects), app and migrate job."
  value       = module.pathways.slots
}

output "key_vault_name" {
  description = "The Key Vault: put the master key pathways-key-2026-11 there before the app starts."
  value       = module.pathways.key_vault.name
}

output "sftp" {
  description = "Where the lab connects with SFTP, on port 22, and the name it signs in with."
  value = {
    host     = module.pathways.storage.sftp_host
    username = module.pathways.storage.sftp_users["lab"].username
  }
}
```

### `project/channels/orders-to-lab/channel.yaml`

```yaml title="examples/complete/project/channels/orders-to-lab/channel.yaml"
# One channel: the hospital sends lab orders over MLLP, and each is written as a file to the lab's
# SFTP container, where the lab fetches it. The account and container names come from the
# environment the module sets; the engine signs in with its managed identity, so no key is here.
source:
  mllp:
    port: 2575
    host: 0.0.0.0
    # Your own server certificate and key, copied into the image. MLLP carries no credentials, so
    # mutual TLS (tls.ca) is how the source checks who is sending.
    tls:
      cert: ../../certs/server.pem
      key: ../../certs/server.key
destinations:
  - file:
      dir: outbox
      azblob:
        account: { env: PATHWAYS_AZBLOB_ACCOUNT }
        container: { env: PATHWAYS_SFTP_LAB_CONTAINER }
```

### `project/pathways.yaml`

```yaml title="examples/complete/project/pathways.yaml"
# The project the example's image is built from (see Deploy the image in the Pathways docs). The
# module sets every environment variable this file reads.

# The module's PostgreSQL server, whose URL the app reads from the Key Vault. The server refuses a
# connection without TLS.
storage:
  postgres:
    url: { env: PATHWAYS_DATABASE_URL }
    tls: {}

# The master key, read from the Key Vault secret named in encryption_key_secrets.
encryption:
  keys:
    - id: k2026-11
      env: PATHWAYS_KEY_2026_11
  current: k2026-11

# Where the app's startup, liveness and readiness probes ask.
probes:
  port: 9091
  host: 0.0.0.0
  plaintext: true
```

### `versions.tf`

```hcl title="examples/complete/versions.tf"
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
