<a href="https://cosyte.com">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://cosyte.com/tile/cosyte-lockup-tile-on-dark-1200x300.png">
    <img alt="The Cosyte logo on its own white ground: the icon beside the word Cosyte." src="https://cosyte.com/tile/cosyte-lockup-tile-on-light-1200x300.png">
  </picture>
</a>

# terraform-azurerm-pathways

> Run Cosyte Pathways on Azure Container Apps, private by default, with its database, its secrets and its logs.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Terraform module that runs [Cosyte Pathways](https://github.com/cosyte/pathways), our open-source
healthcare integration engine, on Azure Container Apps.

**Documentation: [docs.cosyte.com/terraform-azurerm-pathways](https://docs.cosyte.com/terraform-azurerm-pathways)**,
with a tutorial, how-to guides, a page per example and the reference of every input and output.

---

## Contents

- [Why this exists](#why-this-exists)
- [Status](#status)
- [What it creates](#what-it-creates)
- [Layout](#layout)
- [Use it](#use-it)
- [Examples](#examples)
- [Storage and SFTP](#storage-and-sftp)
- [Alarms on the engine's metrics](#alarms-on-the-engines-metrics)
- [What it costs](#what-it-costs)
- [Limits we rely on](#limits-we-rely-on)
- [Documentation](#documentation)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

---

## Why this exists

Pathways carries messages that hold patient data, and running it on Azure takes more than the app:
a Container Apps environment on your virtual network, a managed identity, a Key Vault, a PostgreSQL
server and a migrate job, wired together, and often a place partners drop and fetch files over SFTP. This module creates them with private networking, TLS to
the database, secrets only in Key Vault and least-privilege roles as the defaults, and it checks the
Container Apps limits it relies on when you plan rather than when you apply.

---

## Status

**Not released.** The module is built and tested against mocked providers, and has not yet been
applied to a real Azure subscription by us. Nothing here is published to a registry or tagged.

The alarms on the engine's own metrics are off by default, and their collector's configuration
has not yet been run against a live collector: see
[Alarms on the engine's metrics](#alarms-on-the-engines-metrics) for what is and is not alarmed.

---

## What it creates

- A Container Apps environment per slot, on your virtual network, with an internal load balancer by
  default, sending its logs to a Log Analytics workspace with the retention you set.
- The Pathways app in each environment, with TCP ingress for MLLP: the first port in `mllp_ports` is
  the main ingress port, and up to five more are additional port mappings. Startup, liveness and
  readiness probes ask the engine's probe listener (`/livez`, `/livez` and `/readyz`), and the
  termination grace period is `drain_seconds`. It runs one replica: one engine per database. With
  `http_port` in place of `mllp_ports`, the app takes HTTP instead, behind HTTP ingress that ends
  TLS on port 443. With `standby_replica = true`, a second replica waits as the engine's warm
  standby.
- A user-assigned managed identity the apps and jobs run as. It reads Key Vault secrets and, with
  `container_registry_server`, pulls your images.
- A Key Vault with RBAC authorization, purge protection and a deny-by-default network rule, its
  audit log sent to the workspace, and a private endpoint when you name a subnet for it. The
  database URL is a secret there, and so is each master key you name. The apps read them through
  `secretRef`, never as plain values.
- A PostgreSQL flexible server with private access only, TLS required (1.2 at least), password and
  Microsoft Entra authentication on, and an optional Entra administrator. With `existing_postgres`
  instead, no server: the app reads the URL of one you already run from a Key Vault secret you put
  there.
- A Container Apps job per slot that runs `pathways migrate`, started by hand or from your pipeline.
- Optionally, off unless `storage.enabled` is true: a storage account with SFTP for partners' files
  and the engine's own blobs, private by default, encrypted with a key from the Key Vault, with one
  container per SFTP user and blob data access for the app's identity. See
  [Storage and SFTP](#storage-and-sftp).
- Optionally, off unless `alarms_enabled` is true: an OpenTelemetry collector beside the engine in
  each replica, an Application Insights resource, and five Azure Monitor metric alerts on the
  engine's own metrics that call your action group. See
  [Alarms on the engine's metrics](#alarms-on-the-engines-metrics).

It does not create the virtual network, its subnets or the private DNS zones: you pass their ids.
[`examples/complete`](examples/complete) creates them too.

---

## Layout

The root module is the composition: it calls one module per concern and wires them together. Each
module under `modules/` can also be used on its own; its README says what it needs.

```text
.
├── main.tf              the composition: calls the modules below
├── variables.tf         the root module's inputs
├── outputs.tf           the root module's outputs
├── versions.tf          Terraform and provider versions
├── modules/
│   ├── alarms/          optional: the health token, Application Insights, the collector's
│   │                    configuration and five metric alerts
│   ├── container_apps/  per slot: the environment, the Pathways app and the migrate job
│   ├── database/        the PostgreSQL flexible server and the database URL
│   ├── identity/        the managed identity the app and the jobs run as
│   ├── key_vault/       the Key Vault, its secret, its roles and its audit log
│   ├── logs/            the Log Analytics workspace
│   └── storage/         optional: the storage account with SFTP, its key, users and logs
├── examples/
│   └── <shape>/         one folder per deployment shape: see Examples below
├── docs-content/        the pages docs.cosyte.com renders: guides, a page per example, the reference
├── tests/               the root module's tests, and run.sh, which runs every module's
└── scripts/             validate.sh, policy.sh, check-no-emdash.sh and docs.sh, run by the gate and CI
```

Each module has the same four files as the root, a README and a `tests/` folder of its own.

---

## Use it

```hcl
module "pathways" {
  source = "github.com/cosyte/terraform-azurerm-pathways"

  name                = "pw-example"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  slots = {
    blue = {
      image                    = "registry.example.com/integration/my-project:3f2a91c@sha256:<digest>"
      infrastructure_subnet_id = "<a subnet delegated to Microsoft.App/environments, /27 or larger>"
    }
  }

  mllp_ports    = [2575]
  drain_seconds = 30 # Above 30 is unconfirmed: see "Limits we rely on".

  encryption_key_secrets = {
    PATHWAYS_KEY_2026_11 = "pathways-key-2026-11"
  }

  postgres = {
    delegated_subnet_id = "<a subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers>"
    private_dns_zone_id = "<a private DNS zone ending in .postgres.database.azure.com>"
  }

  key_vault = {
    private_endpoint_subnet_id = "<a subnet for private endpoints>"
    private_dns_zone_id        = "<the privatelink.vaultcore.azure.net zone>"
  }
}
```

[`examples/basic`](examples/basic) is the same call as a full configuration.
[`examples/complete`](examples/complete) stands Pathways up end to end: the resource group, the
virtual network, its subnets and private DNS zones, the module with its database, storage and SFTP
for one partner, and, in `project/`, the Pathways project with one channel that takes orders over
MLLP and writes each to the partner's SFTP container.

### What your project needs

- An image built on the Pathways image (see Deploy the image in the Pathways docs), pinned by digest.
  The module refuses an image without one.
- A `probes` block in `pathways.yaml` that listens where the probes ask:

  ```yaml
  probes:
    port: 9091
    host: 0.0.0.0
    plaintext: true
  ```

- `storage` set to `postgres`, which reads `PATHWAYS_DATABASE_URL` by default, with `tls` set: the
  server refuses a connection without TLS.
- Each master key in the Key Vault under the name you give in `encryption_key_secrets`, before the
  app's revision starts. The module never generates or reads a key.

### Blue and green

A TCP port is unique across one Container Apps environment, so two apps cannot expose the same MLLP
port in one environment. Each slot in `slots` gets its own environment, on its own subnet, so `blue`
and `green` both expose the same ports. Point your senders, or the DNS name they use, at one slot's
`static_ip` (an output) and move it when you switch. Both slots share the database: give the second
engine `lease.standby: true` in `pathways.yaml`, so it waits instead of being refused.

### Schema changes

`pathways start` applies the expand steps of a schema change itself. To leave every schema change to
the migrate job, set `app_start_args = ["start", "-C", "/project", "--no-migrate"]` and start the job
before the new revision:

```sh
az containerapp job start --name pw-example-blue-migrate --resource-group rg-pathways-example
```

### Applying

The Key Vault denies every network, and both the apps (which read their secrets) and the machine
that applies (Terraform writes the database URL secret) need a way in. The plan refuses a vault
nothing could reach, which is the default, so set one of two:

- a private endpoint, `key_vault.private_endpoint_subnet_id` and `key_vault.private_dns_zone_id`, and
  run the apply from inside the virtual network. This is the one we recommend.
- `key_vault.public_network_access_enabled = true` with `key_vault.allowed_ip_ranges` naming the
  runner and the environments' outbound addresses.

Container Apps is not one of Azure's trusted services, so the vault's `AzureServices` bypass does not
let the apps in. Whoever applies gets the Key Vault Secrets Officer role on the vault.

The database password is generated by Terraform, so it is in the state: keep the state encrypted and
private, as you would the database itself.

---

## Examples

One folder per deployment shape under [`examples/`](examples). Each has a README that says what it
builds, when to choose it, what it costs and what it does not cover, and a page on
[docs.cosyte.com](https://docs.cosyte.com/terraform-azurerm-pathways). CI validates each one and
plans it against mocked providers; nothing is applied.

| Folder                                                  | Shape                                                   |
| ------------------------------------------------------- | ------------------------------------------------------- |
| [`basic`](examples/basic)                               | minimal: one private slot in a network you already have |
| [`production`](examples/production)                     | a warm standby, zone-redundant database, alarms on      |
| [`existing-network`](examples/existing-network)         | your own virtual network, looked up by name             |
| [`existing-postgres`](examples/existing-postgres)       | a PostgreSQL server you already run                     |
| [`mllp-only`](examples/mllp-only)                       | MLLP only, over TCP ingress, from named public senders  |
| [`http-only`](examples/http-only)                       | HTTP only, TLS ended at the ingress                     |
| [`complete`](examples/complete)                         | storage and SFTP, end to end with the network           |
| [`internal-only`](examples/internal-only)               | no public ingress anywhere                              |
| [`geo-redundant-backup`](examples/geo-redundant-backup) | backups in a second region, with the restore steps      |
| [`multi-node`](examples/multi-node)                     | several active nodes: not yet supported by the engine   |
| [`blue-green`](examples/blue-green)                     | blue and green with a handover: not yet supported       |
| [`disaster-recovery`](examples/disaster-recovery)       | a second region with promotion: not yet supported       |

The last three hold a README alone, which names what each waits on, and no Terraform: CI refuses
Terraform there until the engine supports the shape.

---

## Storage and SFTP

Set `storage.enabled = true` for a storage account with SFTP. It needs a blob private endpoint: the
engine reads the account through it, since Azure Storage's IP rules do not apply to traffic from the
same region.

```hcl
  storage = {
    enabled                    = true
    private_endpoint_subnet_id = "<a subnet for private endpoints>"
    private_dns_zone_id        = "<the privatelink.blob.core.windows.net zone>"

    # Only for SFTP clients outside your virtual network: their public IPv4 addresses or ranges.
    public_network_access_enabled = true
    allowed_ip_ranges             = ["198.51.100.0/24"]

    sftp_users = {
      lab = {
        ssh_public_keys = ["ssh-ed25519 AAAA... lab"]
        permissions     = ["read", "list", "delete"]
      }
    }
  }
```

The account has hierarchical namespace and SFTP on, its shared keys off, HTTPS and TLS 1.2 at least,
no public containers and no public network access unless you open it. Unless
`customer_managed_key_enabled = false`, it is encrypted with a key the module creates in the Key
Vault and rotates every year; whoever applies gets Key Vault Crypto Officer on the vault to create
it. Its read, write and delete logs go to the Log Analytics workspace; they name blobs and callers,
never what a blob holds, so keep patient data out of file names.

Each SFTP user gets a container of its own, `sftp-<user>`, as its home directory, and a permission on
that container alone. It signs in with an SSH key, never a password, as `<account>.<user>` at
`<account>.blob.core.windows.net`, port 22: the `storage` output gives both. The default
permissions, create, write and list, let a partner drop files; a partner that fetches files needs
read, list and delete.

The app's identity gets Storage Blob Data Contributor on each container, and the app gets these
environment variables, so a channel names the account and containers without a key:

| Variable                         | Value                                                          |
| -------------------------------- | -------------------------------------------------------------- |
| `AZURE_CLIENT_ID`                | the client id of the app's identity, for Azure's default chain |
| `PATHWAYS_AZBLOB_ACCOUNT`        | the account's name                                             |
| `PATHWAYS_AZBLOB_CONTAINER`      | the engine's own container                                     |
| `PATHWAYS_SFTP_<USER>_CONTAINER` | each SFTP user's container, the user's name in capitals        |

```yaml
source:
  file:
    dir: inbox
    minAge: 1m
    azblob:
      account: { env: PATHWAYS_AZBLOB_ACCOUNT }
      container: { env: PATHWAYS_SFTP_LAB_CONTAINER }
```

See Read and write Azure Blob Storage in the Pathways docs for the `azblob` block; the engine's image
needs the `@azure/storage-blob` and `@azure/identity` packages it names.

### What SFTP on Blob Storage cannot do

From Microsoft's pages on
[SFTP support for Blob Storage](https://learn.microsoft.com/azure/storage/blobs/secure-file-transfer-protocol-support),
[authorizing SFTP access](https://learn.microsoft.com/azure/storage/blobs/secure-file-transfer-protocol-support-authorize-access),
[its known issues](https://learn.microsoft.com/azure/storage/blobs/secure-file-transfer-protocol-known-issues)
and [network security for Azure Storage](https://learn.microsoft.com/azure/storage/common/storage-network-security).
Check them before you rely on a point: the service changes.

- **No Microsoft Entra ID sign-in.** SFTP clients sign in only as local users of the account, with a
  password or an SSH key. This module turns passwords off. A local user is not a Microsoft Entra
  identity: there is no conditional access or multi-factor sign-in for it, and you rotate its keys
  yourself by changing `ssh_public_keys`.
- **A home directory is not a jail.** It only sets where a session starts; a user can reach any path
  in a container its permissions cover. That is why each user has a container of its own here.
- **It needs hierarchical namespace,** which is set when the account is created: turning it off
  replaces the account. Some Blob Storage features are not available on such an account; Microsoft's
  Blob Storage feature support page lists them.
- **SFTP only:** no FTP and no FTPS.
- **Nothing we found hides a file until its upload ends.** Give a source that reads an SFTP
  container a `minAge` longer than an upload takes, so the engine does not take a file half written.
- **IP rules take public IPv4 only:** no IPv6, a single address rather than a `/31` or `/32`, no
  private range, and no effect on traffic from the account's own region. The plan refuses the
  first three; the private endpoint covers the last.
- **SFTP is billed by the hour while it is on,** whether anyone connects or not. Set
  `storage.sftp_enabled = false` to stop it while no partner needs it.

---

## Alarms on the engine's metrics

Off by default. Set `alarms_enabled = true` with `alarms_action_group_id` (an action group you
create) and `alarms_collector_image` (an OpenTelemetry collector with the `prometheus` receiver, the
`filter`, `metricstransform` and `cumulativetodelta` processors and the `azuremonitor` exporter,
such as the OpenTelemetry Collector Contrib image, pinned by digest):

```hcl
  alarms_enabled         = true
  alarms_action_group_id = "<an action group id>"
  alarms_collector_image = "otel/opentelemetry-collector-contrib:<version>@sha256:<digest>"
```

Your `pathways.yaml` then needs a health block on `alarms_health_port` (9090), with
`plaintext: true`, no `host` (so it binds to 127.0.0.1) and no `auth` (so it reads its token from
`PATHWAYS_HEALTH_TOKEN`, which the module sets):

```yaml
health:
  port: 9090
  plaintext: true
```

The module generates the health endpoint's bearer token with an ephemeral resource and writes it
to the Key Vault in a write-only argument, so neither the plan nor the state holds it, and the app
gives it to the engine and to the collector. The collector runs beside the engine in each replica,
reads `/metrics` at 127.0.0.1 every 30 seconds, keeps five metrics, folds away every channel,
destination and outcome label, and sends them to a workspace-based Application Insights resource
with a connection string it reads from a second Key Vault secret. Five metric alerts call your
action group when they fire and when they resolve.

What is alarmed:

| Alert                | Fires when                                                                                     | Input, default                          |
| -------------------- | ---------------------------------------------------------------------------------------------- | --------------------------------------- |
| `store-down`         | no reading of `pathways_store_up` was 1 for that many minutes                                  | `alarms_store_down_minutes`, 5          |
| `oldest-pending-age` | every reading of `pathways_oldest_pending_age_seconds` was above that for 5 minutes            | `alarms_oldest_pending_age_seconds`, 600 |
| `queue-depth`        | every reading of `pathways_queue_depth`, over every destination, was above that for 5 minutes  | `alarms_queue_depth_threshold`, 1000    |
| `refused-messages`   | more refused bodies than that in 15 minutes, all channels together                             | `alarms_refused_messages_threshold`, 0  |
| `settled-failed`     | more messages than that settled as failed with a destination in 15 minutes                     | `alarms_settled_failed_threshold`, 0    |

What is not alarmed, and where this differs from our AWS module:

- **A stopped engine or collector.** Azure does not fire a metric alert on missing data, so
  `store-down` fires only while the engine reports that it cannot read its database. Our AWS module
  counts a missing minute as down; Azure Monitor's metric alerts cannot, and we do not fake it.
- **A 2 minute store down window.** Azure takes a metric alert's window only from a fixed list, so
  `alarms_store_down_minutes` is 1, 5, 15, 30 or 60, and defaults to 5 where the AWS module's is 2.
- **Anything per channel or destination,** and the platform's own metrics: replica restarts, the
  database server, the Key Vault.

The collector's configuration is tested as data and has not yet been run against a live collector
and Application Insights resource: check that the five `pathways_` metrics arrive before you rely
on the alerts. [Turn on the alarms](https://docs.cosyte.com/terraform-azurerm-pathways/turn-on-the-alarms)
says what to check, what each line costs and how to turn them off.

---

## What it costs

We give the drivers, not prices: Azure's pricing pages and your agreement with Microsoft set those.

- **Container Apps:** the vCPU and memory of one always-on replica per slot (`cpu`, `memory`), and
  the migrate job while it runs.
- **PostgreSQL flexible server:** its compute (`postgres.sku_name`), storage (`postgres.storage_mb`),
  backups past the included amount, geo-redundant backup, and a high-availability standby, which
  doubles the compute.
- **Log Analytics:** each GB the environments, the Key Vault and the storage account send, and
  retention past the included days (`log_retention_days`).
- **Key Vault:** its operations, the engine's secret reads and, with a customer-managed key, each
  wrap and unwrap the storage account makes.
- **Storage, when on:** the data stored (soft-deleted data included, for
  `storage.soft_delete_retention_days`), the read, write and list operations, the redundancy
  (`storage.replication_type`), and **SFTP by the hour while it is enabled**.
- **Private endpoints:** each one by the hour, and the data through it: one for the Key Vault when
  you use one, one for the storage account.
- **Data transfer** out of the region.
- **The alarms, when on:** the collector's 0.25 vCPU and 0.5 GiB beside each replica, five metric
  alert rules (each billed per monitored time series per month), the metrics' rows in the
  workspace (a few a minute per replica), the two Key Vault secrets' reads, and what your action
  group sends, such as SMS. Nothing of it exists, or bills, with `alarms_enabled` off.

---

## Limits we rely on

The module checks these when you plan, from Microsoft's Container Apps ingress documentation (read
November 2026): at most five additional TCP ports beside the main one; every exposed port, main or
additional, unique across an environment; port 36985 reserved for the platform's health checks; and
ports 80 and 443 never exposed as TCP ports. They have not yet been confirmed against a live
environment.

The app's address restrictions (`ingress_allowed_cidrs`) are set once, on its ingress, and we expect
them to cover the additional TCP ports as well as the main one. The documentation does not say so
for additional port mappings, so a live test should confirm that a denied address cannot reach an
additional port either.

The termination grace period is not one of them. The documentation gives no maximum for it, only a
default of 30 seconds, and its application lifecycle page still says a container is killed 30
seconds after SIGTERM. `drain_seconds` defaults to 30 and stops at 600, a bound of our own. Until a
live test shows a longer grace period is honored, plan for a drain of 30 seconds at most.

---

## Documentation

- [docs.cosyte.com/terraform-azurerm-pathways](https://docs.cosyte.com/terraform-azurerm-pathways)
  is the full documentation: a tutorial that deploys the basic example, how-to guides for the
  network, storage, SFTP and upgrades, the deployment shapes, a page per example with what it
  deploys and what it costs to leave running, and the reference of every input and output, generated
  from the code. Its source is [`docs-content/`](docs-content).
- Each module's own README, under [`modules/`](modules), says what that module needs and creates
  when you use it on its own.
- [`examples/`](#examples) holds one full configuration per deployment shape.
- Every input is described in [`variables.tf`](variables.tf), with what the plan refuses, and every
  output in [`outputs.tf`](outputs.tf).
- [Cosyte Pathways](https://github.com/cosyte/pathways) documents the engine itself, including
  Deploy the image.

---

## Security

Report a vulnerability privately, as the
[security policy](https://github.com/cosyte/.github/blob/main/SECURITY.md) describes, never in a
public issue.

### PHI and safety

This module carries messages that hold patient data. Its defaults are private networking, TLS to the
database, secrets only in Key Vault and least-privilege roles. We sign Business Associate
Agreements. Your use of Azure itself is between you and Microsoft: you need Microsoft's own Business
Associate Agreement terms, which Microsoft offers through its Product Terms, and should check that
they cover each service this module creates. A safe default here is a starting point, not a finding
about your deployment: how you run it is yours to review.

- MLLP has no authentication of its own. With `internal_load_balancer_enabled = false` the
  environment has a public address, so the plan refuses it unless `ingress_allowed_cidrs` names the
  senders' ranges, and every other address is denied. Each range must be a plain CIDR range, with
  no spaces and no leading zero in its prefix length. Unless you set
  `unsafe_allow_mllp_from_any_address = true`, the plan refuses any range wider than an IPv4 `/8`
  or an IPv6 `/32`, which includes `0.0.0.0/0` and `::/0`; an IPv4-mapped IPv6 range
  (`::ffff:0:0/96`, or any range holding it) wider than an IPv4 `/8`; and a list whose IPv4 ranges
  add up to every IPv4 address, such as 256 ranges of `/8`. The opt-in opens the engine's intake to
  anyone who can reach it: leave it off. Every range the plan accepts is trusted as written, so name
  your senders' ranges as narrowly as you can.
- The Log Analytics workspace keeps Azure's default public endpoints for ingestion and query. Reading
  its logs still needs a Microsoft Entra identity with a role on the workspace; to close those
  endpoints, put the workspace behind an Azure Monitor Private Link Scope, which this module does not
  create.
- The Key Vault's network rule lets Azure's trusted services through (`bypass = AzureServices`), as
  most vaults do; every other caller still needs a role on the vault.
- The storage account, when on, has no public network access unless `storage.allowed_ip_ranges`
  names the SFTP clients, and the plan refuses `0.0.0.0/0`, any range wider than a `/8`, and a list
  that adds up to more addresses than one `/8` holds (16,777,216). That limit sits well under the
  public IPv4 space on purpose: private ranges are refused, so a list of narrow ranges covering every
  public address would never add up to all of IPv4, yet would open the account as widely as
  `0.0.0.0/0`. The firewall also lets Azure's trusted services through (`bypass = AzureServices`);
  each still needs a role on the account to read or write. Its SFTP users sign in with SSH keys only, each to its own
  container, and the engine with its managed identity: the account's shared keys are off.
- With alarms on, the Application Insights resource keeps Azure's default public endpoints for
  ingestion and query, as the workspace does. The collector sends with a connection string that
  can only write telemetry; it is a Key Vault secret only the collector reads, and it is in the
  Terraform state. The metrics it sends carry no channel or destination name and no message
  content. The health endpoint listens on 127.0.0.1 inside each replica and asks for the token.
- The database password is in the Terraform state (see [Applying](#applying)): keep the state
  encrypted and private.
- No test or example applies to a real account: the tests plan against mocked providers and never
  reach Azure, and every value in them is synthetic.

---

## Contributing

The organization's [contributing guide](https://github.com/cosyte/.github/blob/main/CONTRIBUTING.md)
and [code of conduct](https://github.com/cosyte/.github/blob/main/CODE_OF_CONDUCT.md) apply here. The
checks are in [CLAUDE.md](CLAUDE.md#gate) and run on every pull request. Tests plan against mocked
providers and never reach Azure. A new resource goes in the module for its concern, never at the
root.

---

## License

MIT, Copyright (c) 2026 Cosyte LLC. See [LICENSE](LICENSE).

---

_Built by [Cosyte](https://cosyte.com)._
