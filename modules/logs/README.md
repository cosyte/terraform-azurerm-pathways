# logs

A Log Analytics workspace that keeps the engine's logs for 30 to 730 days (90 by default). The
Container Apps environments and the Key Vault's audit log write to it.

To use it on its own:

```hcl
module "logs" {
  source = "github.com/cosyte/terraform-azurerm-pathways//modules/logs"

  name                = "pw-example"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"
  retention_days      = 90
}
```

The workspace keeps Azure's default public endpoints for ingestion and query; see Security in the
repo's README.

Inputs are in [variables.tf](variables.tf) and outputs in [outputs.tf](outputs.tf). Its tests are
in [tests/](tests), run by `tests/run.sh` at the repo root.
