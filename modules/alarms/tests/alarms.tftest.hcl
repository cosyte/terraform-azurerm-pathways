# Plan-only tests of the alarms module used on its own, against a mocked azurerm provider: no Azure
# account, no credentials. The health token comes from the random provider's ephemeral resource,
# which never leaves the machine. Every id and name below is synthetic.

mock_provider "azurerm" {}

variables {
  name                       = "pw-example"
  resource_group_name        = "rg-example"
  location                   = "eastus2"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/log-pw-example"
  key_vault_id               = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.KeyVault/vaults/kv-pw-example"
  action_group_id            = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Insights/actionGroups/ag-pathways-example"
}

run "five_alerts_on_the_engine_metrics_with_the_defaults" {
  command = plan

  assert {
    condition     = sort(keys(azurerm_monitor_metric_alert.this)) == tolist(["oldest_pending_age", "queue_depth", "refused_messages", "settled_failed", "store_down"])
    error_message = "The module must make the five alerts: store down, oldest pending age, queue depth, refused messages and settled destinations failing."
  }

  assert {
    condition     = alltrue([for k, a in azurerm_monitor_metric_alert.this : a.name == "pathways-pw-example-${replace(k, "_", "-")}"])
    error_message = "Each alert must be named pathways-<name>-<alert>."
  }

  assert {
    condition     = alltrue([for a in values(azurerm_monitor_metric_alert.this) : one(a.criteria).metric_namespace == "azure.applicationinsights" && one(a.criteria).skip_metric_validation])
    error_message = "Each alert must read a custom metric of Application Insights, which exists only once the collector has sent it."
  }

  assert {
    condition     = alltrue([for a in values(azurerm_monitor_metric_alert.this) : [for x in a.action : x.action_group_id] == [var.action_group_id] && a.auto_mitigate])
    error_message = "Each alert must call the action group given, and resolve on its own."
  }

  assert {
    condition = (
      one(azurerm_monitor_metric_alert.this["store_down"].criteria).metric_name == "pathways_store_up" &&
      one(azurerm_monitor_metric_alert.this["store_down"].criteria).aggregation == "Maximum" &&
      one(azurerm_monitor_metric_alert.this["store_down"].criteria).operator == "LessThan" &&
      one(azurerm_monitor_metric_alert.this["store_down"].criteria).threshold == 1 &&
      azurerm_monitor_metric_alert.this["store_down"].window_size == "PT5M" &&
      azurerm_monitor_metric_alert.this["store_down"].frequency == "PT1M"
    )
    error_message = "Store down must fire when no reading of pathways_store_up was 1 for 5 minutes, the default."
  }

  assert {
    condition = (
      one(azurerm_monitor_metric_alert.this["oldest_pending_age"].criteria).metric_name == "pathways_oldest_pending_age_seconds" &&
      one(azurerm_monitor_metric_alert.this["oldest_pending_age"].criteria).aggregation == "Minimum" &&
      one(azurerm_monitor_metric_alert.this["oldest_pending_age"].criteria).operator == "GreaterThan" &&
      one(azurerm_monitor_metric_alert.this["oldest_pending_age"].criteria).threshold == 600 &&
      azurerm_monitor_metric_alert.this["oldest_pending_age"].window_size == "PT5M"
    )
    error_message = "Oldest pending age must fire when every reading for 5 minutes was above 600 seconds, the default."
  }

  assert {
    condition = (
      one(azurerm_monitor_metric_alert.this["queue_depth"].criteria).metric_name == "pathways_queue_depth" &&
      one(azurerm_monitor_metric_alert.this["queue_depth"].criteria).aggregation == "Minimum" &&
      one(azurerm_monitor_metric_alert.this["queue_depth"].criteria).operator == "GreaterThan" &&
      one(azurerm_monitor_metric_alert.this["queue_depth"].criteria).threshold == 1000 &&
      azurerm_monitor_metric_alert.this["queue_depth"].window_size == "PT5M"
    )
    error_message = "Queue depth must fire when every reading for 5 minutes was above 1000 deliveries, the default."
  }

  assert {
    condition = (
      one(azurerm_monitor_metric_alert.this["refused_messages"].criteria).metric_name == "pathways_messages_refused_total" &&
      one(azurerm_monitor_metric_alert.this["refused_messages"].criteria).aggregation == "Total" &&
      one(azurerm_monitor_metric_alert.this["refused_messages"].criteria).threshold == 0 &&
      azurerm_monitor_metric_alert.this["refused_messages"].window_size == "PT15M"
    )
    error_message = "Refused messages must fire on more than 0 refused bodies in 15 minutes, the default."
  }

  assert {
    condition = (
      one(azurerm_monitor_metric_alert.this["settled_failed"].criteria).metric_name == "pathways_settled_destinations_total" &&
      one(azurerm_monitor_metric_alert.this["settled_failed"].criteria).aggregation == "Total" &&
      one(azurerm_monitor_metric_alert.this["settled_failed"].criteria).threshold == 0 &&
      azurerm_monitor_metric_alert.this["settled_failed"].window_size == "PT15M"
    )
    error_message = "Settled destinations failing must fire on more than 0 failed settlements in 15 minutes, the default."
  }

  assert {
    condition     = azurerm_application_insights.this.name == "appi-pw-example" && azurerm_application_insights.this.workspace_id == var.log_analytics_workspace_id
    error_message = "The Application Insights resource must be named from name and keep its data in the workspace given."
  }

  assert {
    condition     = azurerm_key_vault_secret.health_token.name == "pathways-health-token" && azurerm_key_vault_secret.health_token.key_vault_id == var.key_vault_id && azurerm_key_vault_secret.health_token.value_wo_version == 1
    error_message = "The health token must be the secret pathways-health-token in the vault given, written once until health_token_version is raised."
  }

  assert {
    condition     = azurerm_key_vault_secret.connection_string.name == "pathways-metrics-connection-string" && azurerm_key_vault_secret.connection_string.key_vault_id == var.key_vault_id
    error_message = "The connection string must be the secret pathways-metrics-connection-string in the vault given."
  }
}

run "the_collector_scrapes_with_the_token_and_keeps_only_five_families" {
  command = plan

  assert {
    condition     = yamldecode(output.collector_config).receivers.prometheus.config.scrape_configs[0].static_configs[0].targets == ["127.0.0.1:9090"]
    error_message = "The collector must scrape the health endpoint at 127.0.0.1 on the health port, inside the replica."
  }

  assert {
    condition     = yamldecode(output.collector_config).receivers.prometheus.config.scrape_configs[0].metrics_path == "/metrics"
    error_message = "The collector must scrape /metrics."
  }

  assert {
    condition     = yamldecode(output.collector_config).receivers.prometheus.config.scrape_configs[0].authorization == { type = "Bearer", credentials = "$${env:PATHWAYS_HEALTH_TOKEN}" }
    error_message = "The collector must present the health token, read from PATHWAYS_HEALTH_TOKEN, as a bearer token, and never hold its value."
  }

  assert {
    condition     = yamldecode(output.collector_config).exporters.azuremonitor.connection_string == "$${env:APPLICATIONINSIGHTS_CONNECTION_STRING}"
    error_message = "The collector must read the connection string from its variable, never hold its value."
  }

  assert {
    condition = alltrue([
      for n in ["pathways_store_up", "pathways_oldest_pending_age_seconds", "pathways_queue_depth", "pathways_messages_refused_total", "pathways_settled_destinations_total"] :
      strcontains(yamldecode(output.collector_config).processors["filter/pathways"].metrics.metric[0], "name == \"${n}\"")
    ])
    error_message = "The filter must keep the five families the alerts read."
  }

  assert {
    condition     = startswith(yamldecode(output.collector_config).processors["filter/pathways"].metrics.metric[0], "not (")
    error_message = "The filter must drop every metric that is not one of the five."
  }

  assert {
    condition     = strcontains(yamldecode(output.collector_config).processors["filter/pathways"].metrics.datapoint[0], "attributes[\"outcome\"] != \"failed\"")
    error_message = "Of the settlements, only the failed ones may leave the replica."
  }

  assert {
    condition = alltrue([
      for t in yamldecode(output.collector_config).processors["metricstransform/pathways"].transforms :
      [for o in t.operations : try(o.label_set, null) if o.action == "aggregate_labels"] == [["Deployment"]]
    ])
    error_message = "Every family must fold its channel, destination and outcome labels away, keeping only Deployment."
  }

  assert {
    condition     = yamldecode(output.collector_config).processors["cumulativetodelta/pathways"].include.metrics == ["pathways_messages_refused_total", "pathways_settled_destinations_total"]
    error_message = "The two counters, and only they, must go to Application Insights as what was added since the previous scrape."
  }

  assert {
    condition     = yamldecode(output.collector_config).service.pipelines.metrics.exporters == ["azuremonitor"]
    error_message = "The collector must send to Azure Monitor and nowhere else."
  }
}

run "thresholds_and_the_store_down_window_are_inputs" {
  command = plan

  variables {
    health_port                = 9190
    health_token_version       = 3
    store_down_minutes         = 15
    oldest_pending_age_seconds = 120
    queue_depth_threshold      = 50
    refused_messages_threshold = 5
    settled_failed_threshold   = 7
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["store_down"].window_size == "PT15M"
    error_message = "The store down window must come from store_down_minutes."
  }

  assert {
    condition = (
      one(azurerm_monitor_metric_alert.this["oldest_pending_age"].criteria).threshold == 120 &&
      one(azurerm_monitor_metric_alert.this["queue_depth"].criteria).threshold == 50 &&
      one(azurerm_monitor_metric_alert.this["refused_messages"].criteria).threshold == 5 &&
      one(azurerm_monitor_metric_alert.this["settled_failed"].criteria).threshold == 7
    )
    error_message = "Each threshold must come from its input."
  }

  assert {
    condition     = azurerm_key_vault_secret.health_token.value_wo_version == 3
    error_message = "Raising health_token_version must write a new token."
  }

  assert {
    condition     = yamldecode(output.collector_config).receivers.prometheus.config.scrape_configs[0].static_configs[0].targets == ["127.0.0.1:9190"]
    error_message = "The collector must scrape the health port given."
  }
}

run "a_store_down_window_azure_does_not_take_is_refused" {
  command = plan

  variables {
    store_down_minutes = 2
  }

  expect_failures = [var.store_down_minutes]
}

run "an_action_group_id_that_is_not_one_is_refused" {
  command = plan

  variables {
    action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example"
  }

  expect_failures = [var.action_group_id]
}
