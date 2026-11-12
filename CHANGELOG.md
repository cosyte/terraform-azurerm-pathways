# Changelog

## Unreleased (patch)

- The module: Pathways on Azure Container Apps, with a Container Apps environment, app and migrate
  job per slot, TCP ingress for MLLP behind an address guard, PostgreSQL on a private flexible
  server with TLS required, the database URL and the master keys in Key Vault, a managed identity
  and a Log Analytics workspace. Tested with `terraform test` against mocked providers, tflint and
  trivy.
- Each concern is now a module of its own under `modules/` (`container_apps`, `database`,
  `identity`, `key_vault`, `logs`), each with its own README and tests and usable on its own. The
  root module only composes them; its inputs and outputs are unchanged. Nothing had been applied or
  released, so there are no `moved` blocks.
