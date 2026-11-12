# container_apps

Per slot: a Container Apps environment on its own infrastructure subnet, the Pathways app with TCP
ingress for MLLP (one main port and up to five additional ports, with the address guard on
`ingress_allowed_cidrs`), startup, liveness and readiness probes on the engine's probe listener, and
a Container Apps job that runs `pathways migrate`. The app and the job read the database URL and
each master key from Key Vault through `secretRef`, as the managed identity you pass.

The root module calls it with the identity, workspace and Key Vault it creates. To use it on its
own, bring those three yourself:

```hcl
module "container_apps" {
  source = "github.com/cosyte/terraform-azurerm-pathways//modules/container_apps"

  name                = "pw-example"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = "registry.example.com/integration/my-project:3f2a91c@sha256:<digest>"
      infrastructure_subnet_id = "<a subnet delegated to Microsoft.App/environments, /27 or larger>"
    }
  }
  mllp_ports = [2575]

  identity_id                = "<a user-assigned identity with Key Vault Secrets User on the vault>"
  log_analytics_workspace_id = "<a Log Analytics workspace id>"
  key_vault_uri              = "https://<your vault>.vault.azure.net/"
  database_url_secret_id     = "https://<your vault>.vault.azure.net/secrets/database-url"
}
```

Grant the identity its role on the vault before you apply this module: a revision that cannot read
its secrets does not start.

Inputs are in [variables.tf](variables.tf) and outputs in [outputs.tf](outputs.tf). Its tests are
in [tests/](tests), run by `tests/run.sh` at the repo root.
