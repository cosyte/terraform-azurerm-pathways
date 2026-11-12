# Plan-only tests of the root module's optional storage account and SFTP, against mocked providers:
# no Azure account, no credentials. Every id, name and key below is synthetic: the SSH public key is
# made from fixed numbers in OpenSSH's format, never generated, so nobody holds a private key for it.
# What the storage module creates is tested in modules/storage/tests; these test that the root keeps
# it off by default, wires it to the app, and refuses the same unsafe inputs at its storage input.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }

  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    override_during = plan
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-pw-example"
      client_id    = "00000000-0000-0000-0000-000000000006"
      principal_id = "00000000-0000-0000-0000-000000000007"
    }
  }
}

mock_provider "azapi" {}

variables {
  name                = "pw-example"
  resource_group_name = "rg-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = "registry.example.com/integration/project:1a2b3c4@sha256:0000000000000000000000000000000000000000000000000000000000000000"
      infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-blue"
    }
  }

  mllp_ports = [2575]

  postgres = {
    delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-postgres"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/example.postgres.database.azure.com"
  }

  key_vault = {
    private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
    private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }
}

run "storage_is_off_by_default" {
  command = plan

  assert {
    condition     = output.storage == null
    error_message = "No storage account may be created unless storage.enabled is true."
  }
}

run "storage_on_is_wired_to_the_app" {
  command = plan

  variables {
    storage = {
      enabled                    = true
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      sftp_users = {
        lab = {
          ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f lab-uploader"]
        }
      }
    }
  }

  assert {
    condition     = output.storage.account_name == "stpwexample" && output.storage.container == "pathways"
    error_message = "The storage output must give the account and the engine's container."
  }

  assert {
    condition     = output.storage.sftp_host == "stpwexample.blob.core.windows.net"
    error_message = "The storage output must give the SFTP host."
  }

  assert {
    condition     = output.storage.sftp_users["lab"].username == "stpwexample.lab" && output.storage.sftp_users["lab"].container == "sftp-lab"
    error_message = "The storage output must give each SFTP user's sign-in name and container."
  }

  assert {
    condition = output.storage.app_environment == tomap({
      AZURE_CLIENT_ID             = "00000000-0000-0000-0000-000000000006"
      PATHWAYS_AZBLOB_ACCOUNT     = "stpwexample"
      PATHWAYS_AZBLOB_CONTAINER   = "pathways"
      PATHWAYS_SFTP_LAB_CONTAINER = "sftp-lab"
    })
    error_message = "The app must get the identity's client id and the account and container names, never a key."
  }
}

run "storage_with_a_public_endpoint_for_named_senders_plans" {
  command = plan

  variables {
    storage = {
      enabled                       = true
      private_endpoint_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      public_network_access_enabled = true
      allowed_ip_ranges             = ["198.51.100.0/24", "203.0.113.7"]
      customer_managed_key_enabled  = false
      sftp_enabled                  = false
    }
  }

  assert {
    condition     = output.storage.account_name == "stpwexample"
    error_message = "Storage with a public endpoint for named ranges must plan."
  }
}

# Unsafe inputs, refused at plan time at the root's storage input.

run "refuses_storage_with_no_private_endpoint" {
  command = plan

  variables {
    storage = { enabled = true }
  }

  expect_failures = [var.storage]
}

run "refuses_the_ipv4_any_address_range" {
  command = plan

  variables {
    storage = {
      enabled                       = true
      private_endpoint_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      public_network_access_enabled = true
      allowed_ip_ranges             = ["0.0.0.0/0"]
    }
  }

  expect_failures = [var.storage]
}

run "refuses_an_ipv6_range" {
  command = plan

  variables {
    storage = {
      enabled                       = true
      private_endpoint_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      public_network_access_enabled = true
      allowed_ip_ranges             = ["::/0"]
    }
  }

  expect_failures = [var.storage]
}

run "refuses_ranges_that_add_up_to_every_address" {
  command = plan

  variables {
    storage = {
      enabled                       = true
      private_endpoint_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      public_network_access_enabled = true
      allowed_ip_ranges             = concat([for i in range(256) : "${i}.0.0.0/8" if !contains([10, 172, 192], i)], ["1.0.0.0/9", "1.128.0.0/9", "2.0.0.0/9", "2.128.0.0/9", "3.0.0.0/9", "3.128.0.0/9"])
    }
  }

  expect_failures = [var.storage]
}

run "refuses_a_private_range" {
  command = plan

  variables {
    storage = {
      enabled                       = true
      private_endpoint_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      public_network_access_enabled = true
      allowed_ip_ranges             = ["192.168.10.0/24"]
    }
  }

  expect_failures = [var.storage]
}

run "refuses_allowed_ranges_on_a_closed_public_endpoint" {
  command = plan

  variables {
    storage = {
      enabled                    = true
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      allowed_ip_ranges          = ["198.51.100.0/24"]
    }
  }

  expect_failures = [var.storage]
}

run "refuses_a_public_endpoint_with_no_ranges" {
  command = plan

  variables {
    storage = {
      enabled                       = true
      private_endpoint_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      public_network_access_enabled = true
    }
  }

  expect_failures = [var.storage]
}

run "refuses_a_private_key_for_an_sftp_user" {
  command = plan

  variables {
    storage = {
      enabled                    = true
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      sftp_users                 = { lab = { ssh_public_keys = ["-----BEGIN OPENSSH PRIVATE KEY----- ExampleOnly"] } }
    }
  }

  expect_failures = [var.storage]
}

run "refuses_an_sftp_user_with_no_key" {
  command = plan

  variables {
    storage = {
      enabled                    = true
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      sftp_users                 = { lab = { ssh_public_keys = [] } }
    }
  }

  expect_failures = [var.storage]
}

run "refuses_an_unknown_sftp_permission" {
  command = plan

  variables {
    storage = {
      enabled                    = true
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      sftp_users                 = { lab = { ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"], permissions = ["chmod"] } }
    }
  }

  expect_failures = [var.storage]
}

run "refuses_storage_app_variables_passed_by_hand" {
  command = plan

  variables {
    environment_variables = { PATHWAYS_AZBLOB_ACCOUNT = "stsomethingelse" }
    storage = {
      enabled                    = true
      private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
      private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    }
  }

  expect_failures = [var.storage]
}
