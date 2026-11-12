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
- An optional storage account with SFTP, off unless `storage.enabled` is true, in a new `storage`
  module: hierarchical namespace and SFTP on, shared keys off, a blob private endpoint, no public
  network access unless you name public IPv4 ranges (the plan refuses `0.0.0.0/0`, any range wider
  than a `/8` and a list adding up to more than one `/8`), a customer-managed key from the Key Vault,
  SFTP users with SSH keys only, each in a container of its own, the blob logs in the workspace,
  and blob data access for the app's identity, which gets the account and container names as
  environment variables. `examples/complete` stands Pathways up end to end with the network, the
  database, storage, SFTP and one channel. The README says what SFTP on Blob Storage cannot do and
  what drives the cost.
- Documentation for docs.cosyte.com, in `docs-content/`: a tutorial that deploys the basic example,
  how-to guides for the network, storage, SFTP and upgrades, the deployment shapes and the limits we
  rely on, troubleshooting, testing and performance, a page per example that shows its files and
  says what it deploys and what it costs to leave running, and the reference of every input and
  output of the root module and of each module, generated from the code by `scripts/docs.sh`. CI
  fails when the reference or an example's files differ from the code, or when an example has no
  page. A tag `v<version>` on main now makes a GitHub release with `docs-content.tar.gz` and
  `source.tar.gz`, the archives the docs site reads. The README links to the documentation. No input
  or output changes.
