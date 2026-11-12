terraform {
  # 1.11 for the write-only value of a Key Vault secret, so the health token is in no plan and no
  # state.
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.42.0, < 5.0.0"
    }
    # The ephemeral random_password that becomes the health token.
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.0, < 4.0.0"
    }
  }
}
