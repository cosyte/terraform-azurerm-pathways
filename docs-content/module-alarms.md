---
id: module-alarms
title: The alarms module
sidebar_label: alarms
description: "Every input and output of the alarms module, generated from its code."
---

# The alarms module

Azure Monitor metric alerts on five of the metrics Pathways serves at `/metrics` on its health endpoint, and what it takes to read them on Container Apps: a health token and a connection string in the Key Vault, a workspace-based Application Insights resource, and the configuration of an OpenTelemetry collector that runs beside the engine. The root module calls it when `alarms_enabled` is true, and gives the collector to the container_apps module, which runs it in each replica.

Use it on its own with `source = "github.com/cosyte/terraform-azurerm-pathways//modules/alarms"`.

This page is generated from the code in `modules/alarms/` by `scripts/docs.sh`, and CI fails when it no longer matches. Change `modules/alarms/variables.tf` or its `outputs.tf`, then run `scripts/docs.sh`.

## Requirements

| Name | Version |
| --- | --- |
| `terraform` | `>= 1.11.0` |
| `azurerm` | `>= 4.42.0, < 5.0.0` |
| `random` | `>= 3.7.0, < 4.0.0` |

## Resources

- `azurerm_application_insights.this`
- `azurerm_key_vault_secret.connection_string`
- `azurerm_key_vault_secret.health_token`
- `azurerm_monitor_metric_alert.this`

## Inputs

14 inputs, 6 of them required. The required ones come first, then the rest by name.

### `action_group_id`

Required.

The resource id of the Azure Monitor action group each alert calls when it fires and when it resolves. You create the action group and its receivers.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- action\_group\_id must be the resource id of an action group, such as /subscriptions/\<id\>/resourceGroups/\<group\>/providers/Microsoft.Insights/actionGroups/\<name\>.

### `key_vault_id`

Required.

The resource id of the Key Vault the health token and the connection string are written to, as two secrets: pathways-health-token and pathways-metrics-connection-string. Whoever applies must be able to write secrets there, and reach the vault, before this module runs: the key\_vault module's secrets\_writer\_id output waits for both.

Type:

```hcl
string
```

### `location`

Required.

The Azure region, such as eastus2.

Type:

```hcl
string
```

### `log_analytics_workspace_id`

Required.

The Log Analytics workspace the Application Insights resource keeps its data in, under the workspace's retention.

Type:

```hcl
string
```

### `name`

Required.

Short name the resources are named from: the Application Insights resource appi-\<name\>, the alerts pathways-\<name\>-\<alert\>, and each metric's Deployment label. 3 to 16 lowercase letters, digits and hyphens, starting with a letter.

Type:

```hcl
string
```

The plan refuses a value that breaks this rule, with this message:

- name must be 3 to 16 lowercase letters, digits and single hyphens, starting with a letter and not ending with a hyphen.

### `resource_group_name`

Required.

The existing resource group the Application Insights resource and the alerts are created in.

Type:

```hcl
string
```

### `health_port`

Optional.

The port of the engine's health endpoint, the health block of your pathways.yaml, which serves /metrics. The collector reads it at 127.0.0.1 inside the replica, so the block can keep its default host, 127.0.0.1.

Type:

```hcl
number
```

Default: `9090`

The plan refuses a value that breaks this rule, with this message:

- health\_port must be a whole port from 1 to 65535.

### `health_token_version`

Optional.

Raise this by one to write a new health token: the module generates one and writes it to its secret, and neither the plan nor the state ever holds it. The engine and the collector read it when a replica starts, so restart the app's revision after you raise it.

Type:

```hcl
number
```

Default: `1`

The plan refuses a value that breaks this rule, with this message:

- health\_token\_version must be a whole number, 1 or more.

### `oldest_pending_age_seconds`

Optional.

The oldest pending age alert fires when the oldest delivery waiting on any destination has waited longer than this, in seconds, in every reading for 5 minutes.

Type:

```hcl
number
```

Default: `600`

The plan refuses a value that breaks this rule, with this message:

- oldest\_pending\_age\_seconds must be 0 or more.

### `queue_depth_threshold`

Optional.

The queue depth alert fires when the deliveries pending, over every destination, number more than this in every reading for 5 minutes.

Type:

```hcl
number
```

Default: `1000`

The plan refuses a value that breaks this rule, with this message:

- queue\_depth\_threshold must be a whole number, 0 or more.

### `refused_messages_threshold`

Optional.

The refused messages alert fires when the bodies the sources refused (unreadable or rejected, all channels together) number more than this in 15 minutes. 0 fires on the first one.

Type:

```hcl
number
```

Default: `0`

The plan refuses a value that breaks this rule, with this message:

- refused\_messages\_threshold must be a whole number, 0 or more.

### `settled_failed_threshold`

Optional.

The settled destinations failing alert fires when the messages that settled as failed with a destination (all channels and destinations together) number more than this in 15 minutes. 0 fires on the first one.

Type:

```hcl
number
```

Default: `0`

The plan refuses a value that breaks this rule, with this message:

- settled\_failed\_threshold must be a whole number, 0 or more.

### `store_down_minutes`

Optional.

The store down alert fires when no reading of pathways\_store\_up was 1 for this many minutes: 1, 5, 15, 30 or 60, the windows Azure Monitor takes. Missing readings do not count: Azure does not fire a metric alert on missing data, so an engine or a collector that stopped reporting does not fire it.

Type:

```hcl
number
```

Default: `5`

The plan refuses a value that breaks this rule, with this message:

- store\_down\_minutes must be 1, 5, 15, 30 or 60: Azure Monitor takes a metric alert's window only from a fixed list.

### `tags`

Optional.

Tags added to every resource that takes them.

Type:

```hcl
map(string)
```

Default: `{}`

## Outputs

7 outputs, by name.

### `alarm_ids`

The ids of the five metric alerts, by key: store\_down, oldest\_pending\_age, queue\_depth, refused\_messages and settled\_failed.

### `application_insights`

The Application Insights resource the collector sends the metrics to: its id and name. The metrics are custom metrics in its azure.applicationinsights namespace.

### `collector_config`

The OpenTelemetry collector's configuration, in YAML: scrape /metrics at 127.0.0.1 on the health port, keep the five families, fold their labels away, turn the counters into deltas, and send them to Application Insights. It names the token and the connection string only as the variables they are read from.

### `connection_string_secret_id`

The versionless id of the Key Vault secret that holds the Application Insights connection string, which only the collector reads.

### `connection_string_variable`

The environment variable the collector reads the Application Insights connection string from.

### `health_token_secret_id`

The versionless id of the Key Vault secret that holds the health endpoint's bearer token. The app reads it into the engine and the collector as PATHWAYS\_HEALTH\_TOKEN. The token itself is in no output, no plan and no state.

### `health_token_variable`

The environment variable the engine's health endpoint and the collector read the token from.
