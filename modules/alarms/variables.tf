variable "name" {
  description = "Short name the resources are named from: the Application Insights resource appi-<name>, the alerts pathways-<name>-<alert>, and each metric's Deployment label. 3 to 16 lowercase letters, digits and hyphens, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "resource_group_name" {
  description = "The existing resource group the Application Insights resource and the alerts are created in."
  type        = string
}

variable "location" {
  description = "The Azure region, such as eastus2."
  type        = string
}

variable "tags" {
  description = "Tags added to every resource that takes them."
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "The Log Analytics workspace the Application Insights resource keeps its data in, under the workspace's retention."
  type        = string
}

variable "key_vault_id" {
  description = "The resource id of the Key Vault the health token and the connection string are written to, as two secrets: pathways-health-token and pathways-metrics-connection-string. Whoever applies must be able to write secrets there, and reach the vault, before this module runs: the key_vault module's secrets_writer_id output waits for both."
  type        = string
}

variable "action_group_id" {
  description = "The resource id of the Azure Monitor action group each alert calls when it fires and when it resolves. You create the action group and its receivers."
  type        = string

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Insights/actionGroups/[^/]+$", var.action_group_id))
    error_message = "action_group_id must be the resource id of an action group, such as /subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.Insights/actionGroups/<name>."
  }
}

variable "health_port" {
  description = "The port of the engine's health endpoint, the health block of your pathways.yaml, which serves /metrics. The collector reads it at 127.0.0.1 inside the replica, so the block can keep its default host, 127.0.0.1."
  type        = number
  default     = 9090

  validation {
    condition     = var.health_port >= 1 && var.health_port <= 65535 && floor(var.health_port) == var.health_port
    error_message = "health_port must be a whole port from 1 to 65535."
  }
}

variable "health_token_version" {
  description = "Raise this by one to write a new health token: the module generates one and writes it to its secret, and neither the plan nor the state ever holds it. The engine and the collector read it when a replica starts, so restart the app's revision after you raise it."
  type        = number
  default     = 1

  validation {
    condition     = var.health_token_version >= 1 && floor(var.health_token_version) == var.health_token_version
    error_message = "health_token_version must be a whole number, 1 or more."
  }
}

variable "store_down_minutes" {
  description = "The store down alert fires when no reading of pathways_store_up was 1 for this many minutes: 1, 5, 15, 30 or 60, the windows Azure Monitor takes. Missing readings do not count: Azure does not fire a metric alert on missing data, so an engine or a collector that stopped reporting does not fire it."
  type        = number
  default     = 5

  validation {
    condition     = contains([1, 5, 15, 30, 60], var.store_down_minutes)
    error_message = "store_down_minutes must be 1, 5, 15, 30 or 60: Azure Monitor takes a metric alert's window only from a fixed list."
  }
}

variable "oldest_pending_age_seconds" {
  description = "The oldest pending age alert fires when the oldest delivery waiting on any destination has waited longer than this, in seconds, in every reading for 5 minutes."
  type        = number
  default     = 600

  validation {
    condition     = var.oldest_pending_age_seconds >= 0
    error_message = "oldest_pending_age_seconds must be 0 or more."
  }
}

variable "queue_depth_threshold" {
  description = "The queue depth alert fires when the deliveries pending, over every destination, number more than this in every reading for 5 minutes."
  type        = number
  default     = 1000

  validation {
    condition     = var.queue_depth_threshold >= 0 && floor(var.queue_depth_threshold) == var.queue_depth_threshold
    error_message = "queue_depth_threshold must be a whole number, 0 or more."
  }
}

variable "refused_messages_threshold" {
  description = "The refused messages alert fires when the bodies the sources refused (unreadable or rejected, all channels together) number more than this in 15 minutes. 0 fires on the first one."
  type        = number
  default     = 0

  validation {
    condition     = var.refused_messages_threshold >= 0 && floor(var.refused_messages_threshold) == var.refused_messages_threshold
    error_message = "refused_messages_threshold must be a whole number, 0 or more."
  }
}

variable "settled_failed_threshold" {
  description = "The settled destinations failing alert fires when the messages that settled as failed with a destination (all channels and destinations together) number more than this in 15 minutes. 0 fires on the first one."
  type        = number
  default     = 0

  validation {
    condition     = var.settled_failed_threshold >= 0 && floor(var.settled_failed_threshold) == var.settled_failed_threshold
    error_message = "settled_failed_threshold must be a whole number, 0 or more."
  }
}
