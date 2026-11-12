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
