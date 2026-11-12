# Pathways on Azure Container Apps, one slot, in a virtual network you already have. Every name and
# id here is a placeholder: replace them with your own. Nothing in this example is applied by our CI.

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

module "pathways" {
  source = "../.."

  name                = "pw-example"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-pathways-blue"
    }
  }

  # One MLLP source on 2575; pathways.yaml's probes block listens on 0.0.0.0:9091.
  mllp_ports            = [2575]
  ingress_allowed_cidrs = ["10.20.0.0/16"]
  drain_seconds         = 60

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/pathways-example.postgres.database.azure.com"
  }

  key_vault = {
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
    private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  tags = {
    environment = "example"
  }
}

output "slots" {
  description = "Each slot's environment address, app and migrate job."
  value       = module.pathways.slots
}
