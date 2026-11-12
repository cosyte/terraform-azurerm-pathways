variable "name" {
  description = "Short name the workspace's name is built from (log-<name>): 3 to 16 lowercase letters, digits and hyphens, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "resource_group_name" {
  description = "The existing resource group the workspace is created in."
  type        = string
}

variable "location" {
  description = "The Azure region, such as eastus2."
  type        = string
}

variable "tags" {
  description = "Tags added to the workspace."
  type        = map(string)
  default     = {}
}

variable "retention_days" {
  description = "How long the workspace keeps the engine's logs: 30 to 730 days."
  type        = number
  default     = 90

  validation {
    condition     = var.retention_days >= 30 && var.retention_days <= 730 && floor(var.retention_days) == var.retention_days
    error_message = "retention_days must be a whole number from 30 to 730."
  }
}
