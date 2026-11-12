# database

A PostgreSQL flexible server with private access only (a delegated subnet and a private DNS zone),
TLS required at version 1.2 or later, password and Microsoft Entra authentication on, an optional
Entra administrator and an optional zone-redundant standby, and the `pathways` database. It
generates the administrator password and puts it in the `database_url` output, which is sensitive:
store it as a secret, never as a plain value.

The password is in the Terraform state, so keep the state encrypted and private.

To use it on its own:

```hcl
module "database" {
  source = "github.com/cosyte/terraform-azurerm-pathways//modules/database"

  name                = "pw-example"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  delegated_subnet_id = "<a subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers>"
  private_dns_zone_id = "<a private DNS zone ending in .postgres.database.azure.com>"
}
```

Inputs are in [variables.tf](variables.tf) and outputs in [outputs.tf](outputs.tf). Its tests are
in [tests/](tests), run by `tests/run.sh` at the repo root.
