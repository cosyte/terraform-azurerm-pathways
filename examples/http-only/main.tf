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
