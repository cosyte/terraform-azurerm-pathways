output "slots" {
  description = "Per slot: the environment's id and static IP address (where senders connect for MLLP), the app's id and name, and the migrate job's name."
  value = {
    for k in keys(var.slots) : k => {
      environment_id   = azurerm_container_app_environment.this[k].id
      static_ip        = azurerm_container_app_environment.this[k].static_ip_address
      app_id           = azapi_resource.app[k].id
      app_name         = azapi_resource.app[k].name
      migrate_job_name = azurerm_container_app_job.migrate[k].name
    }
  }
}

output "mllp_ports" {
  description = "The MLLP ports each slot exposes."
  value       = var.mllp_ports
}
