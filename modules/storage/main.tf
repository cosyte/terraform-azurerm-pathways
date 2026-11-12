# A storage account for files partners send and fetch over SFTP, and for the engine's own blobs. SFTP
# on Blob Storage needs hierarchical namespace; it signs users in as local users of the account, with
# an SSH key here, never a password, and never with Microsoft Entra ID. The engine reads and writes
# with its managed identity, so the account's shared keys are off.

data "azurerm_client_config" "current" {}

locals {
  account_name = coalesce(var.account_name, "st${replace(var.name, "-", "")}")

  # The engine's container, and one per SFTP user. A local user's home directory only sets where its
  # session starts; its permission scopes, one per container, are what it can reach. So each user
  # gets a container of its own and a permission on that container alone.
  user_containers = { for u in keys(var.sftp_users) : u => "sftp-${u}" }
  containers      = toset(concat([var.container_name], values(local.user_containers)))

  # Azure takes a key as its type and data; the comment, when there is one, becomes its description.
  user_keys = {
    for u, user in var.sftp_users : u => [
      for i, k in user.ssh_public_keys : {
        key         = join(" ", slice(split(" ", k), 0, 2))
        description = length(split(" ", k)) > 2 ? join(" ", slice(split(" ", k), 2, length(split(" ", k)))) : "key-${i + 1}"
      }
    ]
  }
}

# The account's own identity, which reads its customer-managed key and nothing else.
resource "azurerm_user_assigned_identity" "storage" {
  count = var.customer_managed_key_enabled ? 1 : 0

  name                = "id-${var.name}-storage"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Whoever applies creates the key and sets its rotation policy.
resource "azurerm_role_assignment" "deployer_crypto_officer" {
  count = var.customer_managed_key_enabled ? 1 : 0

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_key" "storage" {
  count = var.customer_managed_key_enabled ? 1 : 0

  name         = "storage-${var.name}"
  key_vault_id = var.key_vault_id
  key_type     = "RSA"
  key_size     = 3072
  key_opts     = ["wrapKey", "unwrapKey"]
  tags         = var.tags

  # The vault makes a new version every year, and each version expires after two. The account names
  # the key without a version, so Azure Storage moves to each new version on its own.
  rotation_policy {
    expire_after         = "P2Y"
    notify_before_expiry = "P30D"

    automatic {
      time_after_creation = "P1Y"
    }
  }

  depends_on = [azurerm_role_assignment.deployer_crypto_officer]
}

resource "azurerm_role_assignment" "key_user" {
  count = var.customer_managed_key_enabled ? 1 : 0

  scope                = azurerm_key_vault_key.storage[0].resource_versionless_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.storage[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_storage_account" "this" {
  name                     = local.account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"
  tags                     = var.tags

  is_hns_enabled     = true
  sftp_enabled       = var.sftp_enabled
  local_user_enabled = var.sftp_enabled
  nfsv3_enabled      = false

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = var.public_network_access_enabled

  network_rules {
    default_action = "Deny"
    # The trusted services on Azure's list, such as Azure Backup; every other caller needs the
    # private endpoint or an allowed range, and a role or a local user besides.
    bypass   = ["AzureServices"]
    ip_rules = var.allowed_ip_ranges
  }

  blob_properties {
    delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  dynamic "identity" {
    for_each = var.customer_managed_key_enabled ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.storage[0].id]
    }
  }

  dynamic "customer_managed_key" {
    for_each = var.customer_managed_key_enabled ? [1] : []
    content {
      key_vault_key_id          = azurerm_key_vault_key.storage[0].versionless_id
      user_assigned_identity_id = azurerm_user_assigned_identity.storage[0].id
    }
  }

  depends_on = [azurerm_role_assignment.key_user]
}

resource "azurerm_private_endpoint" "blob" {
  name                = "pe-st-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "st-${var.name}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

# Containers are created through Azure Resource Manager (storage_account_id), so the apply needs no
# account key and no way into the account's data plane.
resource "azurerm_storage_container" "this" {
  for_each = local.containers

  name                  = each.key
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_storage_account_local_user" "this" {
  for_each = var.sftp_users

  name                 = each.key
  storage_account_id   = azurerm_storage_account.this.id
  home_directory       = local.user_containers[each.key]
  ssh_key_enabled      = true
  ssh_password_enabled = false

  permission_scope {
    service       = "blob"
    resource_name = azurerm_storage_container.this[local.user_containers[each.key]].name

    permissions {
      create = contains(each.value.permissions, "create")
      write  = contains(each.value.permissions, "write")
      list   = contains(each.value.permissions, "list")
      read   = contains(each.value.permissions, "read")
      delete = contains(each.value.permissions, "delete")
    }
  }

  dynamic "ssh_authorized_key" {
    for_each = local.user_keys[each.key]
    content {
      key         = ssh_authorized_key.value.key
      description = ssh_authorized_key.value.description
    }
  }
}

# The engine reads and writes blobs with its managed identity, on each container and nothing wider.
resource "azurerm_role_assignment" "blob_data" {
  for_each = azurerm_storage_container.this

  scope                = each.value.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.blob_data_principal_id
  principal_type       = "ServicePrincipal"
}

# Who read, wrote or deleted which blob, over SFTP or the Blob API, kept with the engine's logs. The
# logs name blobs and callers, never their contents.
resource "azurerm_monitor_diagnostic_setting" "blob" {
  name                       = "blob-logs"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}
