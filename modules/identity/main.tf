# The identity the apps and the jobs run as: it reads the Key Vault secrets and, with a private
# registry, pulls the images.
resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
