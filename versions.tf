terraform {
  # 1.9 for variable validations that read other variables, and 1.11 for the write-only value of a
  # Key Vault secret, which keeps the alarms' health token out of the plan and the state. The pin in
  # mise.toml is what CI runs.
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.42.0, < 5.0.0"
    }
    # The container app itself is written through azapi: TCP ingress with additional port mappings
    # is part of the Container Apps API that azurerm_container_app does not expose.
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0.0, < 3.0.0"
    }
    # 3.7 for the ephemeral random_password that becomes the alarms' health token.
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.0, < 4.0.0"
    }
  }
}
