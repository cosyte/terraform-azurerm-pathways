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
