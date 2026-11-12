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
