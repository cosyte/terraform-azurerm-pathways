# Pathways with its database backups copied to a second region, so the messages it holds can be
# restored there if the first region is lost. The engine itself runs in one region; the README says
# how to restore the database in the other and run Pathways on it. Every name, id and range here is
# a placeholder: replace them with your own. Nothing in this example is applied by our CI.

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

  name                = "pw-geo"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = var.image
      infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-pathways-blue"
    }
  }

  # pathways.yaml's probes block listens on 0.0.0.0:9091.
  mllp_ports            = [2575]
  ingress_allowed_cidrs = ["10.20.0.0/16"]

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/pathways-geo.postgres.database.azure.com"

    # Backups kept 35 days, the most the server allows, and copied to the region Azure pairs with
    # eastus2. Set this when the server is made: changing it on a server that exists can replace the
    # server, so read the plan.
    backup_retention_days        = 35
    geo_redundant_backup_enabled = true
  }

  key_vault = {
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
    private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }

  tags = {
    environment = "example"
  }
}

output "postgres" {
  description = "The PostgreSQL server to restore from: its id is the restore's source."
  value       = module.pathways.postgres
}

output "key_vault_name" {
  description = "The Key Vault that holds the master key. A restored database is unreadable without it: keep a copy of each key outside this region."
  value       = module.pathways.key_vault.name
}
