# Changelog

## Unreleased (patch)

- Alarms on the engine's own metrics, off by default (`alarms_enabled`): with it off the module plans
  what it did before. On, an OpenTelemetry collector runs beside the engine in each replica
  (`alarms_collector_image`, pinned by digest), reads `/metrics` on the engine's health endpoint at
  127.0.0.1 with a bearer token the module generates into the Key Vault secret
  `pathways-health-token` and gives to the engine as `PATHWAYS_HEALTH_TOKEN` and to the collector
  (neither the plan nor the state holds it), and sends five metrics with no channel or destination
  label to a workspace-based Application Insights resource. Five Azure Monitor metric alerts call
  `alarms_action_group_id`: store down, oldest pending age, queue depth, refused messages and
  settled destinations failing, each threshold an input. Azure does not fire a metric alert on
  missing data, so a stopped engine or collector does not fire store down, and its window is 1, 5,
  15, 30 or 60 minutes (5 by default). A new `modules/alarms`, a `metrics_collector` input on
  `modules/container_apps`, a `secrets_writer_id` output on `modules/key_vault`, the root output
  `alarms`, the alarms on in `examples/production`, and a "Turn on the alarms" page. To turn them
  on, add a `health:` block on `alarms_health_port` (9090) with `plaintext: true` to your
  `pathways.yaml`.
- What a caller must change: Terraform 1.11 or later (was 1.9), for the write-only argument that
  keeps the health token out of the state, and `hashicorp/random` 3.7 or later (was 3.6), for the
  ephemeral resource that generates it. No input or output a caller passes today changes.
- Examples, one folder per deployment shape, each with a README that says what it builds, when to
  choose it, what it costs and what it does not cover, a page on docs.cosyte.com, and a test that
  plans it against mocked providers in CI: `basic` (minimal), `production` (one engine with a warm
  standby and a zone-redundant database), `existing-network`, `existing-postgres`, `mllp-only`,
  `http-only`, `complete` (storage and SFTP), `internal-only` and `geo-redundant-backup` (with the
  restore steps). `multi-node`, `blue-green` and `disaster-recovery` hold a README alone: the engine
  does not support those shapes yet, and `tests/run.sh` refuses Terraform in a folder like them. The
  README has an index of every example.
- New inputs for those shapes. Nothing a caller must change: each is off or null by default, and
  every configuration that planned before plans the same way.
  - `standby_replica`: a second replica as the engine's warm standby. Both replicas start with
    `--standby`; the first takes the engine lease, and the other takes over once it stops.
  - `http_port`: HTTP ingress in place of TCP, for an engine whose only intake is HTTP. Container
    Apps ends TLS on port 443 and refuses plain HTTP from outside. `mllp_ports` now defaults to an
    empty list, and the plan refuses both or neither.
  - `existing_postgres`: a PostgreSQL server you already run, its database URL in a Key Vault
    secret you put there yourself. The module makes no server and never sees the URL. `postgres`
    now defaults to null, and the plan refuses both or neither. In the `key_vault` module, the new
    `existing_database_url_secret_name` does the same, and `database_url` defaults to null.
  - New outputs: `database_url_secret_name`, `http_port`, `standby_replica`, and each slot's
    `default_domain` and `fqdn`. `postgres` is null with `existing_postgres`.
- Fixed: a configuration that creates the Key Vault's private endpoint subnet in the same apply,
  as `examples/complete` does, could not plan: the `key_vault` module counted its private endpoint
  from the subnet's id, which is not known until apply. It now counts from
  `public_network_access_enabled`, which is known; the plan already refuses a closed vault without
  a subnet. The new example tests found it.
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
