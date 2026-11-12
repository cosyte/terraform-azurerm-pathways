# Plans the example against mocked providers: no Azure account, no credentials. tests/run.sh at the
# repository root runs it. Every id and value below is synthetic.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-pathways-example"
    }
  }
}

mock_provider "azapi" {}

variables {
  subscription_id    = "00000000-0000-0000-0000-000000000000"
  image              = "registry.example.com/integration/my-project:3f2a91c@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  lab_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f lab"
  lab_sftp_ip_ranges = ["198.51.100.0/24"]
}

run "plans_the_network_the_module_and_sftp_for_the_lab" {
  command = plan

  assert {
    condition     = contains(azurerm_virtual_network.this.address_space, "10.40.0.0/16")
    error_message = "The example must make its virtual network."
  }

  assert {
    condition     = output.slots["blue"].app_name == "pw-example-blue"
    error_message = "The example must plan its one slot."
  }
}
