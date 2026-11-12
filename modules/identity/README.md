# identity

The user-assigned managed identity the Pathways app and its migrate job run as. It creates the
identity only: the key_vault module grants it Key Vault Secrets User, and you grant it AcrPull on a
private registry.

To use it on its own:

```hcl
module "identity" {
  source = "github.com/cosyte/terraform-azurerm-pathways//modules/identity"

  name                = "pw-example"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"
}
```

Inputs are in [variables.tf](variables.tf) and outputs in [outputs.tf](outputs.tf). Its tests are
in [tests/](tests), run by `tests/run.sh` at the repo root.
