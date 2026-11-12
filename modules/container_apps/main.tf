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
  )

  app_env = concat(
    [{ name = "PATHWAYS_DATABASE_URL", secretRef = local.database_url_secret }],
    [for env_name, k in local.key_secrets : { name = env_name, secretRef = k.app_secret_name }],
    [for name, value in var.environment_variables : { name = name, value = value }],
  )

  ip_restrictions = [
    for i, cidr in var.ingress_allowed_cidrs : {
      name           = "allow-${i}"
      action         = "Allow"
      ipAddressRange = cidr
    }
  ]

  main_port        = var.mllp_ports[0]
  additional_ports = slice(var.mllp_ports, 1, length(var.mllp_ports))
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
        ingress = {
          # external means reachable from outside the environment: from the virtual network when the
          # environment's load balancer is internal, the default.
          external    = true
          transport   = "tcp"
          targetPort  = local.main_port
          exposedPort = local.main_port
          additionalPortMappings = [
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
        containers = [{
          name  = "pathways"
          image = each.value.image
          args  = var.app_start_args
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
        }]
        # One engine per database: the engine lease refuses a second, or holds it as a standby.
        scale = {
          minReplicas = 1
          maxReplicas = 1
        }
      }
    }
  }

  response_export_values = ["properties.latestRevisionName"]
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
