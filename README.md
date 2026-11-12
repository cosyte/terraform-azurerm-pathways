# terraform-azurerm-pathways

A Terraform module that runs [Cosyte Pathways](https://github.com/cosyte/pathways), our open-source
healthcare integration engine, on Azure Container Apps.

**Status: not released.** The module is built and tested against mocked providers, and has not yet
been applied to a real Azure subscription by us. Nothing here is published to a registry or tagged.

## What it creates

- A Container Apps environment per slot, on your virtual network, with an internal load balancer by
  default, sending its logs to a Log Analytics workspace with the retention you set.
- The Pathways app in each environment, with TCP ingress for MLLP: the first port in `mllp_ports` is
  the main ingress port, and up to five more are additional port mappings. Startup, liveness and
  readiness probes ask the engine's probe listener (`/livez`, `/livez` and `/readyz`), and the
  termination grace period is `drain_seconds`. It runs one replica: one engine per database.
- A user-assigned managed identity the apps and jobs run as. It reads Key Vault secrets and, with
  `container_registry_server`, pulls your images.
- A Key Vault with RBAC authorization, purge protection and a deny-by-default network rule, its
  audit log sent to the workspace, and a private endpoint when you name a subnet for it. The database URL is a secret
  there, and so is each master key you name. The apps read them through `secretRef`, never as plain
  values.
- A PostgreSQL flexible server with private access only, TLS required (1.2 at least), password and
  Microsoft Entra authentication on, and an optional Entra administrator.
- A Container Apps job per slot that runs `pathways migrate`, started by hand or from your pipeline.

It does not create the virtual network, its subnets or the private DNS zones: you pass their ids.

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

## Not in this release

Alerts on the engine's own metrics wait for the metric names Pathways will publish. There are no
alert rules yet.

## Security

This module carries messages that hold patient data. Its defaults are private networking, TLS to the
database, secrets only in Key Vault and least-privilege roles. We sign Business Associate
Agreements.

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

## Development

The checks are in [CLAUDE.md](CLAUDE.md#gate) and run on every pull request. Tests plan against
mocked providers and never reach Azure.

## License

MIT. See [LICENSE](LICENSE).
