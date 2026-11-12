# Plan-only tests of the metrics collector the container_apps module runs beside the engine when
# it is given one, against mocked providers: no Azure account, no credentials. Every id and name
# below is synthetic.

mock_provider "azurerm" {
  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example"
    }
  }
}

mock_provider "azapi" {}

variables {
  name                = "pw-example"
  resource_group_name = "rg-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = "registry.example.com/integration/project:1a2b3c4@sha256:0000000000000000000000000000000000000000000000000000000000000000"
      infrastructure_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-blue"
    }
  }

  mllp_ports = [2575]

  identity_id                = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-pw-example"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/log-pw-example"
  key_vault_uri              = "https://kv-pw-example.vault.azure.net/"
  database_url_secret_id     = "https://kv-pw-example.vault.azure.net/secrets/database-url"
}

run "without_a_collector_the_app_runs_the_engine_alone" {
  command = plan

  assert {
    condition     = [for c in azapi_resource.app["blue"].body.properties.template.containers : c.name] == ["pathways"]
    error_message = "Without metrics_collector the app must run the engine alone."
  }

  assert {
    condition     = [for s in azapi_resource.app["blue"].body.properties.configuration.secrets : s.name] == ["database-url"]
    error_message = "Without metrics_collector the app must read no secret but its own."
  }

  assert {
    condition     = !contains([for e in azapi_resource.app["blue"].body.properties.template.containers[0].env : e.name], "PATHWAYS_HEALTH_TOKEN")
    error_message = "Without metrics_collector the engine must get no health token."
  }
}

run "a_collector_runs_beside_the_engine_with_the_token_and_the_connection_string" {
  command = plan

  variables {
    metrics_collector = {
      image                       = "registry.example.com/otel/collector:0.0.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"
      config                      = "receivers: {}"
      health_token_secret_id      = "https://kv-pw-example.vault.azure.net/secrets/pathways-health-token"
      connection_string_secret_id = "https://kv-pw-example.vault.azure.net/secrets/pathways-metrics-connection-string"
    }
  }

  assert {
    condition     = [for c in azapi_resource.app["blue"].body.properties.template.containers : c.name] == ["pathways", "metrics-collector"]
    error_message = "With metrics_collector the app must run the collector beside the engine."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.template.containers[1].image == var.metrics_collector.image
    error_message = "The collector must run the image given."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.template.containers[1].args == ["--config=env:PATHWAYS_COLLECTOR_CONFIG"]
    error_message = "The collector must read its configuration from PATHWAYS_COLLECTOR_CONFIG."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.template.containers[1].resources.cpu == 0.25 && azapi_resource.app["blue"].body.properties.template.containers[1].resources.memory == "0.5Gi"
    error_message = "The collector must take 0.25 vCPU and 0.5Gi."
  }

  assert {
    condition = (
      [for e in azapi_resource.app["blue"].body.properties.template.containers[1].env : try(e.value, null) if e.name == "PATHWAYS_COLLECTOR_CONFIG"] == ["receivers: {}"] &&
      [for e in azapi_resource.app["blue"].body.properties.template.containers[1].env : try(e.secretRef, null) if e.name == "PATHWAYS_HEALTH_TOKEN"] == ["health-token"] &&
      [for e in azapi_resource.app["blue"].body.properties.template.containers[1].env : try(e.secretRef, null) if e.name == "APPLICATIONINSIGHTS_CONNECTION_STRING"] == ["metrics-connection-string"]
    )
    error_message = "The collector must get its configuration as a value and the token and the connection string from Key Vault secrets."
  }

  assert {
    condition     = [for e in azapi_resource.app["blue"].body.properties.template.containers[0].env : try(e.secretRef, null) if e.name == "PATHWAYS_HEALTH_TOKEN"] == ["health-token"]
    error_message = "The engine must read the same health token, from the Key Vault secret."
  }

  assert {
    condition     = !contains([for e in azapi_resource.app["blue"].body.properties.template.containers[0].env : e.name], "APPLICATIONINSIGHTS_CONNECTION_STRING")
    error_message = "Only the collector may read the connection string."
  }

  assert {
    condition = (
      [for s in azapi_resource.app["blue"].body.properties.configuration.secrets : s.keyVaultUrl if s.name == "health-token"] == [var.metrics_collector.health_token_secret_id] &&
      [for s in azapi_resource.app["blue"].body.properties.configuration.secrets : s.keyVaultUrl if s.name == "metrics-connection-string"] == [var.metrics_collector.connection_string_secret_id] &&
      alltrue([for s in azapi_resource.app["blue"].body.properties.configuration.secrets : s.identity == var.identity_id])
    )
    error_message = "The token and the connection string must be Key Vault references read with the app's identity."
  }

  assert {
    condition     = [for c in azurerm_container_app_job.migrate["blue"].template[0].container : c.name] == ["migrate"]
    error_message = "The migrate job must not run the collector."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.configuration.ingress.targetPort == 2575 && azapi_resource.app["blue"].body.properties.configuration.ingress.additionalPortMappings == []
    error_message = "The collector must add no ingress: the health port stays inside the replica."
  }
}

run "a_collector_image_without_a_digest_is_refused" {
  command = plan

  variables {
    metrics_collector = {
      image                       = "registry.example.com/otel/collector:latest"
      config                      = "receivers: {}"
      health_token_secret_id      = "https://kv-pw-example.vault.azure.net/secrets/pathways-health-token"
      connection_string_secret_id = "https://kv-pw-example.vault.azure.net/secrets/pathways-metrics-connection-string"
    }
  }

  expect_failures = [var.metrics_collector]
}

run "a_health_token_passed_by_hand_is_refused_with_a_collector" {
  command = plan

  variables {
    environment_variables = {
      PATHWAYS_HEALTH_TOKEN = "not-a-real-token"
    }
    metrics_collector = {
      image                       = "registry.example.com/otel/collector:0.0.0@sha256:1111111111111111111111111111111111111111111111111111111111111111"
      config                      = "receivers: {}"
      health_token_secret_id      = "https://kv-pw-example.vault.azure.net/secrets/pathways-health-token"
      connection_string_secret_id = "https://kv-pw-example.vault.azure.net/secrets/pathways-metrics-connection-string"
    }
  }

  expect_failures = [var.metrics_collector]
}
