output "slots" {
  description = "Per slot: the environment's id, static IP address (where senders connect for MLLP) and default domain, the app's id, name and address (fqdn, where senders connect for HTTP over TLS), and the migrate job's name."
  value = {
    for k in keys(var.slots) : k => {
      environment_id   = azurerm_container_app_environment.this[k].id
      static_ip        = azurerm_container_app_environment.this[k].static_ip_address
      default_domain   = azurerm_container_app_environment.this[k].default_domain
      app_id           = azapi_resource.app[k].id
      app_name         = azapi_resource.app[k].name
      fqdn             = try(azapi_resource.app[k].output.properties.configuration.ingress.fqdn, null)
      migrate_job_name = azurerm_container_app_job.migrate[k].name
    }
  }
}

output "http_port" {
  description = "The port the engine's HTTP source listens on behind HTTP ingress, or null for MLLP over TCP ingress."
  value       = var.http_port
}

output "mllp_ports" {
  description = "The MLLP ports each slot exposes."
  value       = var.mllp_ports
}
