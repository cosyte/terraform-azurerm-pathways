# Plan-only tests of the storage module used on its own, against mocked providers: no Azure
# account, no credentials. Every id, name and key below is synthetic: the SSH public keys are made
# from fixed numbers in OpenSSH's format, never generated, so nobody holds a private key for them.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}

variables {
  name                = "pw-example"
  resource_group_name = "rg-example"
  location            = "eastus2"

  private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-endpoints"
  private_dns_zone_id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"

  key_vault_id               = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.KeyVault/vaults/kv-pw-example"
  blob_data_principal_id     = "00000000-0000-0000-0000-000000000005"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/log-pw-example"

  sftp_users = {
    lab = {
      ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f lab-uploader"]
    }
  }
}

# What the defaults create: private, encrypted with the vault's key, SFTP on with key-only users.

run "defaults_are_private_encrypted_and_logged" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.name == "stpwexample"
    error_message = "The account must be named st<name> with the hyphens removed."
  }

  assert {
    condition     = azurerm_storage_account.this.is_hns_enabled && azurerm_storage_account.this.sftp_enabled && azurerm_storage_account.this.local_user_enabled
    error_message = "The account must have hierarchical namespace, SFTP and local users on: SFTP on Blob needs all three."
  }

  assert {
    condition     = azurerm_storage_account.this.public_network_access_enabled == false
    error_message = "The account must have no public network access by default."
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny" && length(azurerm_storage_account.this.network_rules[0].ip_rules) == 0
    error_message = "The account's network rules must deny by default and admit no address range."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false && azurerm_storage_account.this.default_to_oauth_authentication
    error_message = "The account must refuse its shared keys: Pathways reads it with its managed identity."
  }

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "No container may be made public."
  }

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled && azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "The account must take HTTPS only, TLS 1.2 at least."
  }

  assert {
    condition     = azurerm_storage_account.this.infrastructure_encryption_enabled
    error_message = "The account must have infrastructure encryption on."
  }

  assert {
    condition     = azurerm_storage_account.this.cross_tenant_replication_enabled == false
    error_message = "The account must not replicate to another tenant."
  }

  assert {
    condition     = azurerm_storage_account.this.account_replication_type == "LRS"
    error_message = "The account's default redundancy must be LRS."
  }

  assert {
    condition     = length(azurerm_key_vault_key.storage) == 1 && azurerm_key_vault_key.storage[0].key_vault_id == var.key_vault_id
    error_message = "The customer-managed key must be created in the vault given."
  }

  assert {
    condition     = length(azurerm_storage_account.this.customer_managed_key) == 1
    error_message = "The account must be encrypted with the customer-managed key by default."
  }

  assert {
    condition     = azurerm_role_assignment.key_user[0].role_definition_name == "Key Vault Crypto Service Encryption User" && azurerm_role_assignment.key_user[0].principal_type == "ServicePrincipal"
    error_message = "The account's identity must get Key Vault Crypto Service Encryption User on its key, and nothing more."
  }

  assert {
    condition     = azurerm_private_endpoint.blob.private_service_connection[0].subresource_names == tolist(["blob"])
    error_message = "The private endpoint must connect to the blob service, which SFTP uses too."
  }

  assert {
    condition     = azurerm_private_endpoint.blob.private_dns_zone_group[0].private_dns_zone_ids == tolist([var.private_dns_zone_id])
    error_message = "The private endpoint must register in the zone given."
  }

  assert {
    condition     = azurerm_storage_container.this["pathways"].container_access_type == "private"
    error_message = "The engine's container must be private."
  }

  assert {
    condition     = azurerm_storage_container.this["sftp-lab"].container_access_type == "private"
    error_message = "Each SFTP user must get a private container of its own."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.blob.log_analytics_workspace_id == var.log_analytics_workspace_id
    error_message = "The blob service's logs must go to the workspace given."
  }

  assert {
    condition     = toset([for l in azurerm_monitor_diagnostic_setting.blob.enabled_log : l.category]) == toset(["StorageRead", "StorageWrite", "StorageDelete"])
    error_message = "The blob service's diagnostic setting must send the read, write and delete logs."
  }

  assert {
    condition     = toset(keys(azurerm_role_assignment.blob_data)) == toset(["pathways", "sftp-lab"])
    error_message = "The app's identity must get blob data access on the engine's container and on each SFTP user's container."
  }

  assert {
    condition     = alltrue([for r in values(azurerm_role_assignment.blob_data) : r.role_definition_name == "Storage Blob Data Contributor" && r.principal_id == var.blob_data_principal_id])
    error_message = "The app's identity must get Storage Blob Data Contributor, scoped to each container."
  }
}

run "each_sftp_user_is_locked_to_its_own_container_with_keys_only" {
  command = plan

  assert {
    condition     = azurerm_storage_account_local_user.this["lab"].home_directory == "sftp-lab"
    error_message = "A user's home directory must be its own container."
  }

  assert {
    condition     = [for s in azurerm_storage_account_local_user.this["lab"].permission_scope : s.resource_name] == ["sftp-lab"]
    error_message = "A user must hold a permission on its own container and on no other."
  }

  assert {
    condition     = azurerm_storage_account_local_user.this["lab"].permission_scope[0].service == "blob"
    error_message = "A user's permission must be on the blob service."
  }

  assert {
    condition = (
      azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].create
      && azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].write
      && azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].list
      && !azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].read
      && !azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].delete
    )
    error_message = "A user's default permissions must be create, write and list: enough to drop files, and no more."
  }

  assert {
    condition     = azurerm_storage_account_local_user.this["lab"].ssh_key_enabled && !azurerm_storage_account_local_user.this["lab"].ssh_password_enabled
    error_message = "A user must sign in with an SSH key, never a password."
  }

  assert {
    condition     = [for k in azurerm_storage_account_local_user.this["lab"].ssh_authorized_key : k.key] == ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"]
    error_message = "A key must be passed as its type and data, without its comment."
  }

  assert {
    condition     = [for k in azurerm_storage_account_local_user.this["lab"].ssh_authorized_key : k.description] == ["lab-uploader"]
    error_message = "A key's comment must become its description."
  }

  assert {
    condition     = output.sftp_users["lab"].username == "stpwexample.lab" && output.sftp_users["lab"].container == "sftp-lab"
    error_message = "The sftp_users output must give each user's sign-in name and container."
  }

  assert {
    condition     = output.sftp_host == "stpwexample.blob.core.windows.net"
    error_message = "The SFTP host must be the account's blob endpoint."
  }
}

run "the_inputs_reach_the_account" {
  command = plan

  variables {
    account_name                  = "stexamplepathways01"
    container_name                = "engine"
    replication_type              = "ZRS"
    public_network_access_enabled = true
    allowed_ip_ranges             = ["198.51.100.0/24", "203.0.113.7"]
    soft_delete_retention_days    = 14
    sftp_users = {
      lab = {
        ssh_public_keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f",
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCAAAAAAAAAAAAAHZhbQCcEPoU+2n9bJduWhBIQ3AgKOBGBx4s7Mzv342fQnyyHim7PMfS8+zztH44T+tMQ/K8Pj0cD9ux+xjbWmsGHEd3voZZydsConDa/KnNyvXy9DIejSnZ++fs5DiMzn2RHuGBH7PPOmhbGpyjlUCPx7m+saMyV1wPa4voLLViNSsWIgZ42fa7rwHFjaEeI9VjQf8yaLzSHl027OL+ZPZZXvZF1kF0KNI7no1PR2kahL6ikcmHU/fYZzHAvNwSgGfwNTRPD/A7MkNeJRSXJZz0dC/6ZBHFquzoug0475aAQJOLuJLOojK5TY+HmSiVHTKx/osjqdnGgSuLhQLuKkEwORV4LCOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOM= second key",
        ]
        permissions = ["read", "list", "delete"]
      }
      billing = {
        ssh_public_keys = ["ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCAAAAAAAAAAAAAHZhbQCcEPoU+2n9bJduWhBIQ3AgKOBGBx4s7Mzv342fQnyyHim7PMfS8+zztH44T+tMQ/K8Pj0cD9ux+xjbWmsGHEd3voZZydsConDa/KnNyvXy9DIejSnZ++fs5DiMzn2RHuGBH7PPOmhbGpyjlUCPx7m+saMyV1wPa4voLLViNSsWIgZ42fa7rwHFjaEeI9VjQf8yaLzSHl027OL+ZPZZXvZF1kF0KNI7no1PR2kahL6ikcmHU/fYZzHAvNwSgGfwNTRPD/A7MkNeJRSXJZz0dC/6ZBHFquzoug0475aAQJOLuJLOojK5TY+HmSiVHTKx/osjqdnGgSuLhQLuKkEwORV4LCOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOM= billing"]
      }
    }
  }

  assert {
    condition     = azurerm_storage_account.this.name == "stexamplepathways01" && azurerm_storage_account.this.account_replication_type == "ZRS"
    error_message = "account_name and replication_type must reach the account."
  }

  assert {
    condition     = azurerm_storage_account.this.public_network_access_enabled && toset(azurerm_storage_account.this.network_rules[0].ip_rules) == toset(["198.51.100.0/24", "203.0.113.7"])
    error_message = "With public access on, the account must admit only the ranges listed."
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 14 && azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy[0].days == 14
    error_message = "soft_delete_retention_days must reach the blob and container soft delete."
  }

  assert {
    condition     = toset(keys(azurerm_storage_container.this)) == toset(["engine", "sftp-lab", "sftp-billing"])
    error_message = "There must be the engine's container and one per SFTP user."
  }

  assert {
    condition     = length(azurerm_storage_account_local_user.this["lab"].ssh_authorized_key) == 2
    error_message = "Every key given must be authorized."
  }

  assert {
    condition     = [for k in azurerm_storage_account_local_user.this["lab"].ssh_authorized_key : k.description] == ["key-1", "second key"]
    error_message = "A key with no comment must get a numbered description."
  }

  assert {
    condition = (
      azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].read
      && azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].list
      && azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].delete
      && !azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].write
      && !azurerm_storage_account_local_user.this["lab"].permission_scope[0].permissions[0].create
    )
    error_message = "The permissions asked for must be the ones granted, and no others."
  }

  assert {
    condition     = [for s in azurerm_storage_account_local_user.this["billing"].permission_scope : s.resource_name] == ["sftp-billing"]
    error_message = "Each user must hold a permission on its own container only."
  }
}

run "sftp_can_be_switched_off_to_stop_its_hourly_charge" {
  command = plan

  variables {
    sftp_enabled = false
    sftp_users   = {}
  }

  assert {
    condition     = azurerm_storage_account.this.sftp_enabled == false && azurerm_storage_account.this.local_user_enabled == false
    error_message = "With sftp_enabled false, SFTP and local users must be off."
  }

  assert {
    condition     = azurerm_storage_account.this.is_hns_enabled
    error_message = "Hierarchical namespace stays on: turning it off would replace the account."
  }
}

run "microsoft_managed_keys_when_asked" {
  command = plan

  variables {
    customer_managed_key_enabled = false
    key_vault_id                 = null
  }

  assert {
    condition     = length(azurerm_key_vault_key.storage) == 0 && length(azurerm_storage_account.this.customer_managed_key) == 0
    error_message = "With customer_managed_key_enabled false, no key is created and the account uses Microsoft-managed keys."
  }
}

# The address guard on allowed_ip_ranges, refused at plan time.

run "refuses_the_ipv4_any_address_range" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = ["198.51.100.0/24", "0.0.0.0/0"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "refuses_a_range_wider_than_a_slash_8" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = ["64.0.0.0/2"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

# 231 ranges, none wider than a /8, none overlapping another or a private range, that together hold
# every public unicast IPv4 address but 127.0.0.0/8: as open as 0.0.0.0/0, since IP rules take
# public addresses only.
run "refuses_ranges_that_cover_every_public_address" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = concat([for i in range(1, 224) : "${i}.0.0.0/8" if !contains([10, 127, 172, 192], i)], ["172.0.0.0/12", "172.32.0.0/11", "172.64.0.0/10", "172.128.0.0/9", "192.0.0.0/9", "192.128.0.0/11", "192.160.0.0/13", "192.169.0.0/16", "192.170.0.0/15", "192.172.0.0/14", "192.176.0.0/12", "192.192.0.0/10"])
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "refuses_ranges_that_add_up_to_more_than_a_slash_8" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = ["11.0.0.0/8", "203.0.113.7"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "accepts_ranges_that_add_up_to_a_slash_8" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = ["11.0.0.0/9", "12.0.0.0/10", "13.0.0.0/10"]
  }

  assert {
    condition     = length(azurerm_storage_account.this.network_rules[0].ip_rules) == 3
    error_message = "Ranges that add up to exactly a /8 must plan."
  }
}

run "refuses_an_ipv6_range" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = ["::/0"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "refuses_a_slash_32" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = ["203.0.113.7/32"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "refuses_a_private_range" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = ["10.20.0.0/16"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "refuses_a_range_holding_a_private_range" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = ["172.0.0.0/8"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "refuses_a_range_with_a_leading_zero_prefix" {
  command = plan

  variables {
    public_network_access_enabled = true
    allowed_ip_ranges             = ["198.51.100.0/024"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "refuses_allowed_ranges_on_a_closed_public_endpoint" {
  command = plan

  variables {
    allowed_ip_ranges = ["198.51.100.0/24"]
  }

  expect_failures = [var.allowed_ip_ranges]
}

run "refuses_a_public_endpoint_with_no_ranges" {
  command = plan

  variables {
    public_network_access_enabled = true
  }

  expect_failures = [var.allowed_ip_ranges]
}

# The SFTP users, refused at plan time.

run "refuses_a_user_with_no_key" {
  command = plan

  variables {
    sftp_users = { lab = { ssh_public_keys = [] } }
  }

  expect_failures = [var.sftp_users]
}

run "refuses_a_private_key" {
  command = plan

  variables {
    sftp_users = { lab = { ssh_public_keys = ["-----BEGIN OPENSSH PRIVATE KEY----- ExampleOnly"] } }
  }

  expect_failures = [var.sftp_users]
}

run "refuses_a_key_that_is_not_one_line" {
  command = plan

  variables {
    sftp_users = { lab = { ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f\nssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"] } }
  }

  expect_failures = [var.sftp_users]
}

run "refuses_a_bad_user_name" {
  command = plan

  variables {
    sftp_users = { "Lab-User" = { ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"] } }
  }

  expect_failures = [var.sftp_users]
}

run "refuses_an_unknown_permission" {
  command = plan

  variables {
    sftp_users = { lab = { ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"], permissions = ["write", "chmod"] } }
  }

  expect_failures = [var.sftp_users]
}

run "refuses_a_user_with_no_permission" {
  command = plan

  variables {
    sftp_users = { lab = { ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f"], permissions = [] } }
  }

  expect_failures = [var.sftp_users]
}

run "refuses_users_while_sftp_is_off" {
  command = plan

  variables {
    sftp_enabled = false
  }

  expect_failures = [var.sftp_enabled]
}

# The account and its key, refused at plan time.

run "refuses_a_customer_managed_key_without_a_vault" {
  command = plan

  variables {
    key_vault_id = null
  }

  expect_failures = [var.key_vault_id]
}

run "refuses_a_bad_account_name" {
  command = plan

  variables {
    account_name = "st-pathways"
  }

  expect_failures = [var.account_name]
}

run "refuses_an_engine_container_named_like_a_user_container" {
  command = plan

  variables {
    container_name = "sftp-lab"
  }

  expect_failures = [var.container_name]
}

run "refuses_an_unknown_redundancy" {
  command = plan

  variables {
    replication_type = "ZZRS"
  }

  expect_failures = [var.replication_type]
}

run "refuses_a_soft_delete_retention_over_365_days" {
  command = plan

  variables {
    soft_delete_retention_days = 366
  }

  expect_failures = [var.soft_delete_retention_days]
}
