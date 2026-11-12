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
