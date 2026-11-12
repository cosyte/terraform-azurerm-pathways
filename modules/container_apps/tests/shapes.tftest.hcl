# Plan-only tests of the deployment shapes the container_apps module takes beyond MLLP on one
# replica: HTTP as the only intake, and a second replica as the engine's warm standby. Mocked
# providers: no Azure account, no credentials. Every id and name below is synthetic.

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

run "mllp_keeps_one_replica_and_the_image_command" {
  command = plan

  assert {
    condition     = azapi_resource.app["blue"].body.properties.template.scale.minReplicas == 1 && azapi_resource.app["blue"].body.properties.template.scale.maxReplicas == 1
    error_message = "Without a standby the app must run exactly one replica."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.template.containers[0].args == null
    error_message = "Without a standby or app_start_args the app must keep the image's own command."
  }

  assert {
    condition     = output.http_port == null
    error_message = "The http_port output must be null for MLLP over TCP ingress."
  }
}

run "http_only_gets_http_ingress_with_tls_at_the_edge" {
  command = plan

  variables {
    mllp_ports            = []
    http_port             = 8080
    ingress_allowed_cidrs = ["10.20.0.0/16"]
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.configuration.ingress.transport == "http"
    error_message = "With http_port the app's ingress must be HTTP."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.configuration.ingress.targetPort == 8080
    error_message = "HTTP ingress must pass requests to http_port."
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.configuration.ingress.allowInsecure == false
    error_message = "HTTP ingress must refuse plain HTTP from outside the environment."
  }

  assert {
    condition     = !can(azapi_resource.app["blue"].body.properties.configuration.ingress.exposedPort) && !can(azapi_resource.app["blue"].body.properties.configuration.ingress.additionalPortMappings)
    error_message = "HTTP ingress must carry no TCP port mapping."
  }

  assert {
    condition     = [for r in azapi_resource.app["blue"].body.properties.configuration.ingress.ipSecurityRestrictions : r.ipAddressRange] == ["10.20.0.0/16"]
    error_message = "ingress_allowed_cidrs must guard HTTP ingress as it guards MLLP."
  }

  assert {
    condition     = output.http_port == 8080
    error_message = "The http_port output must be the port asked for."
  }
}

run "a_standby_replica_runs_two_replicas_both_started_as_standby" {
  command = plan

  variables {
    standby_replica = true
  }

  assert {
    condition     = azapi_resource.app["blue"].body.properties.template.scale.minReplicas == 2 && azapi_resource.app["blue"].body.properties.template.scale.maxReplicas == 2
    error_message = "With standby_replica the app must run exactly two replicas."
  }

  assert {
    condition     = jsonencode(azapi_resource.app["blue"].body.properties.template.containers[0].args) == jsonencode(["start", "-C", "/project", "--standby"])
    error_message = "With standby_replica and no app_start_args, each replica must start as pathways start -C /project --standby."
  }
}

run "a_standby_replica_adds_standby_to_the_start_args_once" {
  command = plan

  variables {
    standby_replica = true
    app_start_args  = ["start", "-C", "/project", "--no-migrate"]
  }

  assert {
    condition     = jsonencode(azapi_resource.app["blue"].body.properties.template.containers[0].args) == jsonencode(["start", "-C", "/project", "--no-migrate", "--standby"])
    error_message = "With standby_replica, --standby must be added to app_start_args."
  }
}

run "a_standby_replica_keeps_standby_given_in_the_start_args" {
  command = plan

  variables {
    standby_replica = true
    app_start_args  = ["start", "-C", "/project", "--standby"]
  }

  assert {
    condition     = jsonencode(azapi_resource.app["blue"].body.properties.template.containers[0].args) == jsonencode(["start", "-C", "/project", "--standby"])
    error_message = "--standby already in app_start_args must not be added twice."
  }
}

run "refuses_neither_mllp_nor_http" {
  command = plan

  variables {
    mllp_ports = []
  }

  expect_failures = [var.mllp_ports]
}

run "refuses_mllp_and_http_together" {
  command = plan

  variables {
    http_port = 8080
  }

  expect_failures = [var.mllp_ports]
}

run "refuses_the_probe_port_as_the_http_port" {
  command = plan

  variables {
    mllp_ports = []
    http_port  = 9091
  }

  expect_failures = [var.http_port]
}

run "refuses_the_reserved_port_as_the_http_port" {
  command = plan

  variables {
    mllp_ports = []
    http_port  = 36985
  }

  expect_failures = [var.http_port]
}
