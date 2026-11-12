# Pathways on a PostgreSQL server you already run. The module makes no server: the app and the
# migrate job read the database URL from a Key Vault secret you put there yourself, so the URL and
# its password never pass through Terraform or its state. Every name, id and range here is a
# placeholder: replace them with your own. Nothing in this example is applied by our CI.
#
# Apply in two steps. The first makes the Key Vault, the identity and the logs; put the database URL
# secret and the master key in the vault; the second makes the app, which reads both as it starts:
#
#   terraform apply -target=module.pathways.module.key_vault
#   az keyvault secret set --vault-name kv-pw-example --name pathways-database-url --file database-url.txt
#   az keyvault secret set --vault-name kv-pw-example --name pathways-key-2026-11 --file key.txt
#   terraform apply

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

  # One MLLP source on 2575; pathways.yaml's probes block listens on 0.0.0.0:9091, and its storage
  # block reads PATHWAYS_DATABASE_URL with tls set.
  mllp_ports            = [2575]
  ingress_allowed_cidrs = ["10.20.0.0/16"]

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  # Your server: the URL is in the vault secret pathways-database-url, in the form
  # postgres://<user>:<password>@<host>:5432/<database>. The server must take TLS, and the app's
  # subnet must reach it.
  existing_postgres = {
    database_url_secret_name = "pathways-database-url"
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
  description = "The slot's environment address (where senders connect for MLLP), app and migrate job."
  value       = module.pathways.slots
}

output "database_url_secret_name" {
  description = "The Key Vault secret the app reads the database URL from."
  value       = module.pathways.database_url_secret_name
}
