terraform {
  # 1.9 for variable validations that read other variables.
  required_version = ">= 1.9.0"

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
  }
}
