output "collector_config" {
  description = "The OpenTelemetry collector's configuration, in YAML: scrape /metrics at 127.0.0.1 on the health port, keep the five families, fold their labels away, turn the counters into deltas, and send them to Application Insights. It names the token and the connection string only as the variables they are read from."
  value       = local.collector_config
}

output "health_token_variable" {
  description = "The environment variable the engine's health endpoint and the collector read the token from."
  value       = local.token_variable
}

output "health_token_secret_id" {
  description = "The versionless id of the Key Vault secret that holds the health endpoint's bearer token. The app reads it into the engine and the collector as PATHWAYS_HEALTH_TOKEN. The token itself is in no output, no plan and no state."
  value       = azurerm_key_vault_secret.health_token.versionless_id
}

output "connection_string_variable" {
  description = "The environment variable the collector reads the Application Insights connection string from."
  value       = local.connection_string_variable
}

output "connection_string_secret_id" {
  description = "The versionless id of the Key Vault secret that holds the Application Insights connection string, which only the collector reads."
  value       = azurerm_key_vault_secret.connection_string.versionless_id
}

output "application_insights" {
  description = "The Application Insights resource the collector sends the metrics to: its id and name. The metrics are custom metrics in its azure.applicationinsights namespace."
  value = {
    id   = azurerm_application_insights.this.id
    name = azurerm_application_insights.this.name
  }
}

output "alarm_ids" {
  description = "The ids of the five metric alerts, by key: store_down, oldest_pending_age, queue_depth, refused_messages and settled_failed."
  value       = { for k, a in azurerm_monitor_metric_alert.this : k => a.id }
}
