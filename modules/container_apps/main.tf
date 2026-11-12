data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  # The one workload profile every environment has; the app and the job run on it.
  workload_profile = "Consumption"

  # The Container App secret that holds the database URL; the Key Vault secret is
  # var.database_url_secret_id.
  database_url_secret = "database-url"

  # Container App secret names: lowercase letters, digits and hyphens.
  key_secrets = {
    for env_name, kv_name in var.encryption_key_secrets :
    env_name => {
      app_secret_name = "key-${lower(kv_name)}"
      url             = "${var.key_vault_uri}secrets/${kv_name}"
    }
  }

  # With a metrics collector, two more Container App secrets from Key Vault: the health endpoint's
  # token, which the engine and the collector read, and the Application Insights connection string,
  # which only the collector reads.
  collector                  = var.metrics_collector != null
  health_token_secret        = "health-token"
  connection_string_secret   = "metrics-connection-string"
  health_token_variable      = "PATHWAYS_HEALTH_TOKEN"
  connection_string_variable = "APPLICATIONINSIGHTS_CONNECTION_STRING"
  collector_config_variable  = "PATHWAYS_COLLECTOR_CONFIG"
  collector_secrets = local.collector ? [
    {
      name        = local.health_token_secret
      keyVaultUrl = var.metrics_collector.health_token_secret_id
      identity    = var.identity_id
    },
    {
      name        = local.connection_string_secret
      keyVaultUrl = var.metrics_collector.connection_string_secret_id
      identity    = var.identity_id
    },
  ] : []

  app_secrets = concat(
    [{
      name        = local.database_url_secret
      keyVaultUrl = var.database_url_secret_id
      identity    = var.identity_id
    }],
    [for k in values(local.key_secrets) : {
      name        = k.app_secret_name
      keyVaultUrl = k.url
      identity    = var.identity_id
    }],
    local.collector_secrets,
  )

  app_env = concat(
    [{ name = "PATHWAYS_DATABASE_URL", secretRef = local.database_url_secret }],
    [for env_name, k in local.key_secrets : { name = env_name, secretRef = k.app_secret_name }],
    [for name, value in var.environment_variables : { name = name, value = value }],
    local.collector ? [{ name = local.health_token_variable, secretRef = local.health_token_secret }] : [],
  )

  # The metrics collector, beside the engine in each replica: it reads its configuration from
  # PATHWAYS_COLLECTOR_CONFIG, the health token from PATHWAYS_HEALTH_TOKEN and the connection
  # string from APPLICATIONINSIGHTS_CONNECTION_STRING, and scrapes the engine's /metrics over the
  # replica's loopback. It has no ingress and no probe; its logs go to the environment's workspace
  # with the engine's. Without it, the app runs the engine alone, as it always did.
  collector_container = local.collector ? [{
    name  = "metrics-collector"
    image = var.metrics_collector.image
    args  = ["--config=env:${local.collector_config_variable}"]
    resources = {
      cpu    = 0.25
      memory = "0.5Gi"
    }
    env = [
      { name = local.collector_config_variable, value = var.metrics_collector.config },
      { name = local.health_token_variable, secretRef = local.health_token_secret },
      { name = local.connection_string_variable, secretRef = local.connection_string_secret },
    ]
  }] : []

  ip_restrictions = [
    for i, cidr in var.ingress_allowed_cidrs : {
      name           = "allow-${i}"
      action         = "Allow"
      ipAddressRange = cidr
    }
  ]

  http_ingress     = var.http_port != null
  main_port        = local.http_ingress ? var.http_port : var.mllp_ports[0]
  additional_ports = local.http_ingress ? [] : slice(var.mllp_ports, 1, length(var.mllp_ports))

  # With a warm standby, both replicas start with --standby: the first to ask takes the engine lease
  # at once, and the other waits for it. The image's own command is pathways start -C /project.
  start_args = var.standby_replica ? concat(
    coalesce(var.app_start_args, ["start", "-C", "/project"]),
    contains(coalesce(var.app_start_args, ["start"]), "--standby") ? [] : ["--standby"],
  ) : var.app_start_args
  replicas = var.standby_replica ? 2 : 1
}

# One environment per slot. A TCP port is unique across an environment, so blue and green each get
# their own and can expose the same MLLP ports at once. TCP ingress needs an environment on a
# virtual network: each slot names its own infrastructure subnet.
resource "azurerm_container_app_environment" "this" {
  for_each = var.slots

  name                           = "cae-${var.name}-${each.key}"
  resource_group_name            = var.resource_group_name
  location                       = var.location
  infrastructure_subnet_id       = each.value.infrastructure_subnet_id
  internal_load_balancer_enabled = var.internal_load_balancer_enabled
  logs_destination               = "log-analytics"
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  tags                           = var.tags

  workload_profile {
    name                  = local.workload_profile
    workload_profile_type = "Consumption"
  }

  lifecycle {
    # Azure names the infrastructure resource group itself when none is given.
    ignore_changes = [infrastructure_resource_group_name]
  }
}

resource "azapi_resource" "app" {
  for_each = var.slots

  type      = "Microsoft.App/containerApps@2024-03-01"
  name      = "${var.name}-${each.key}"
  parent_id = data.azurerm_resource_group.this.id
  location  = var.location
  tags      = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  body = {
    properties = {
      environmentId       = azurerm_container_app_environment.this[each.key].id
      workloadProfileName = local.workload_profile
      configuration = {
        activeRevisionsMode = "Single"
        # TCP for MLLP, each port exposed on its own number; or HTTP, where Container Apps ends TLS on
        # 443 and passes plain HTTP to http_port, and refuses plain HTTP from outside. A key set to
        # null is left out of the request.
        ingress = {
          # external means reachable from outside the environment: from the virtual network when the
          # environment's load balancer is internal, the default.
          external      = true
          transport     = local.http_ingress ? "http" : "tcp"
          targetPort    = local.main_port
          exposedPort   = local.http_ingress ? null : local.main_port
          allowInsecure = local.http_ingress ? false : null
          additionalPortMappings = local.http_ingress ? null : [
            for p in local.additional_ports : {
              external    = true
              targetPort  = p
              exposedPort = p
            }
          ]
          ipSecurityRestrictions = local.ip_restrictions
        }
        secrets = local.app_secrets
        registries = var.container_registry_server == null ? [] : [{
          server   = var.container_registry_server
          identity = var.identity_id
        }]
      }
      template = {
        terminationGracePeriodSeconds = var.drain_seconds
        containers = concat([{
          name  = "pathways"
          image = each.value.image
          args  = local.start_args
          resources = {
            cpu    = var.cpu
            memory = var.memory
          }
          env = local.app_env
          # All three probes are declared: a probe left out defaults to a TCP check on the MLLP port.
          probes = [
            {
              # The probe listener answers from the first moment, and /livez is live while the engine
              # starts, so this passes as soon as the listener is up; up to 150 seconds after the delay.
              type = "Startup"
              httpGet = {
                path   = "/livez"
                port   = var.probes_port
                scheme = "HTTP"
              }
              initialDelaySeconds = 5
              periodSeconds       = 15
              timeoutSeconds      = 5
              failureThreshold    = 10
            },
            {
              # A restart policy points at /livez: it answers stalled only when the engine loop has
              # made no step within its bound, and an engine still starting or stopping is live.
              type = "Liveness"
              httpGet = {
                path   = "/livez"
                port   = var.probes_port
                scheme = "HTTP"
              }
              initialDelaySeconds = 10
              periodSeconds       = 10
              timeoutSeconds      = 5
              failureThreshold    = 3
            },
            {
              # /readyz turns 503 draining at once on SIGTERM, and while storage or a source is down.
              type = "Readiness"
              httpGet = {
                path   = "/readyz"
                port   = var.probes_port
                scheme = "HTTP"
              }
              initialDelaySeconds = 5
              periodSeconds       = 5
              timeoutSeconds      = 3
              failureThreshold    = 3
              successThreshold    = 1
            },
          ]
        }], local.collector_container)
        # One engine per database: the engine lease refuses a second, or holds it as a standby. With
        # standby_replica the second replica is that standby, started with --standby.
        scale = {
          minReplicas = local.replicas
          maxReplicas = local.replicas
        }
      }
    }
  }

  response_export_values = ["properties.latestRevisionName", "properties.configuration.ingress.fqdn"]
}

# pathways migrate, run by hand or from a pipeline before a slot's new revision takes traffic:
# az containerapp job start --name <job> --resource-group <group>
resource "azurerm_container_app_job" "migrate" {
  for_each = var.slots

  name                         = "${var.name}-${each.key}-migrate"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  container_app_environment_id = azurerm_container_app_environment.this[each.key].id
  workload_profile_name        = local.workload_profile
  replica_timeout_in_seconds   = var.migrate_timeout_seconds
  replica_retry_limit          = 0
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  secret {
    name                = local.database_url_secret
    identity            = var.identity_id
    key_vault_secret_id = var.database_url_secret_id
  }

  dynamic "registry" {
    for_each = var.container_registry_server == null ? [] : [var.container_registry_server]
    content {
      server   = registry.value
      identity = var.identity_id
    }
  }

  template {
    container {
      name   = "migrate"
      image  = each.value.image
      args   = var.migrate_args
      cpu    = var.cpu
      memory = var.memory

      env {
        name        = "PATHWAYS_DATABASE_URL"
        secret_name = local.database_url_secret
      }

      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}
