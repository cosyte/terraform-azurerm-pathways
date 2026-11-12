data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  tags = merge(var.tags, { "pathways-module" = "terraform-azurerm-pathways" })

  # The one workload profile every environment has; the app and the job run on it.
  workload_profile = "Consumption"

  database_url_secret = "database-url"

  # Container App secret names: lowercase letters, digits and hyphens.
  key_secrets = {
    for env_name, kv_name in var.encryption_key_secrets :
    env_name => {
      app_secret_name = "key-${lower(kv_name)}"
      url             = "${azurerm_key_vault.this.vault_uri}secrets/${kv_name}"
    }
  }

  app_secrets = concat(
    [{
      name        = local.database_url_secret
      keyVaultUrl = azurerm_key_vault_secret.database_url.versionless_id
      identity    = azurerm_user_assigned_identity.this.id
    }],
    [for k in values(local.key_secrets) : {
      name        = k.app_secret_name
      keyVaultUrl = k.url
      identity    = azurerm_user_assigned_identity.this.id
    }],
  )

  app_env = concat(
    [{ name = "PATHWAYS_DATABASE_URL", secretRef = local.database_url_secret }],
    [for env_name, k in local.key_secrets : { name = env_name, secretRef = k.app_secret_name }],
    [for name, value in var.environment_variables : { name = name, value = value }],
  )

  ip_restrictions = [
    for i, cidr in var.ingress_allowed_cidrs : {
      name           = "allow-${i}"
      action         = "Allow"
      ipAddressRange = cidr
    }
  ]

  main_port        = var.mllp_ports[0]
  additional_ports = slice(var.mllp_ports, 1, length(var.mllp_ports))
}

# The identity the apps and the jobs run as: it reads the Key Vault secrets and, with
# container_registry_server, pulls the images.
resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}
