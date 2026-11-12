# key_vault

A Key Vault with RBAC authorization, purge protection and a deny-by-default network rule, a private
endpoint when you name a subnet for it, the engine's database URL as the `database-url` secret, Key
Vault Secrets User for the principal that reads the secrets, Key Vault Secrets Officer for whoever
applies (Terraform writes the secret), and the vault's audit log sent to a Log Analytics workspace.

The plan refuses a vault nothing could reach: set `private_endpoint_subnet_id` and
`private_dns_zone_id` (recommended), or `public_network_access_enabled = true` with
`allowed_ip_ranges`.

The root module calls it with the identity, workspace and database URL it creates. To use it on its
own:

```hcl
module "key_vault" {
  source = "github.com/cosyte/terraform-azurerm-pathways//modules/key_vault"

  name                = "pw-example"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  private_endpoint_subnet_id = "<a subnet for private endpoints>"
  private_dns_zone_id        = "<the privatelink.vaultcore.azure.net zone>"

  secrets_reader_principal_id = "<the principal id of the identity the engine runs as>"
  log_analytics_workspace_id  = "<a Log Analytics workspace id>"
  database_url                = var.database_url # sensitive
}
```

`database_url_secret_id` is ready only once the reader holds its role, so pass it to whatever reads
the secret.

Inputs are in [variables.tf](variables.tf) and outputs in [outputs.tf](outputs.tf). Its tests are
in [tests/](tests), run by `tests/run.sh` at the repo root.
