---
id: deployment-shapes
title: Deployment shapes
sidebar_label: Deployment shapes
description: "The shapes the module stands up, from one private slot to two slots with storage and SFTP, what each adds, and why the module is split the way it is."
---

# Deployment shapes

The module stands up one engine per slot, its database, its Key Vault and its logs. A few inputs
change the shape around that core. This page says what each shape is, what it adds and what it
costs in exposure, so you can pick one before you read the how-to guides.

## The core

Every shape has these, from the [root module](./inputs-and-outputs.md):

- **A managed identity** the app and the migrate job run as. It reads the Key Vault's secrets and,
  with `container_registry_server`, pulls your images. No password or key is handed to the engine.
- **A Log Analytics workspace** the environments and the Key Vault's audit log write to.
- **A PostgreSQL flexible server** with private access only and TLS required, and the `pathways`
  database. Terraform generates its administrator password, which is therefore in the state.
- **A Key Vault** with RBAC authorization, purge protection and a network rule that denies by
  default. It holds the database URL and each master key you name; the app reads them through
  `secretRef`, never as plain values.
- **Per slot,** a Container Apps environment on its own subnet, the app with TCP ingress for MLLP
  and probes on the engine's probe listener, and a migrate job started by hand.

The app runs one replica. Pathways runs one engine per database: a second one, without
`lease.standby`, is refused.

## One private slot

One entry in `slots`, the internal load balancer on (the default), and the Key Vault's private
endpoint. The engine has a private address in your virtual network and no public one. Senders on
the network, or on a network connected to it, reach it; nothing on the internet does.

This is the [basic example](./example-basic.md), and the shape we recommend to start with. Its
weak point is an upgrade: with one slot, intake closes while the old revision stops and the new one
starts.

## Two slots, blue and green

Two entries in `slots`, each on its own subnet. A TCP port is unique across one Container Apps
environment, so two apps in one environment could not both expose port 2575. Giving each slot its
own environment lets both listen on the same ports at once, and you move senders from one slot's
`static_ip` to the other's when you switch.

Both slots use the one database. The second engine runs with `lease.standby: true` and takes the
engine lease when the first releases it, so there is never more than one engine working.
[Upgrade the engine and the module](./upgrade-the-engine-and-the-module.md#switch-between-two-slots)
gives the steps.

The plan refuses more than two slots.

## Public intake

`internal_load_balancer_enabled = false` gives each environment a public address, for senders that
reach the engine over the internet. MLLP has no authentication of its own, so the plan refuses this
unless `ingress_allowed_cidrs` names the senders' ranges, and it refuses any range wider than an
IPv4 `/8` or an IPv6 `/32`, an IPv4-mapped range wider than an IPv4 `/8`, and a list whose IPv4
ranges add up to every address. `unsafe_allow_mllp_from_any_address = true` lifts those checks;
it opens the engine's intake to anyone who can reach it, so leave it off.

Prefer a private connection to your senders (a VPN or ExpressRoute into the virtual network) over a
public address. If the address has to be public, require mutual TLS on the MLLP source as well.

## With storage, and SFTP

`storage.enabled = true` adds a storage account for the engine's blobs and partners' files, reached
through a private endpoint, with its shared keys off and a customer-managed key from the Key Vault.
`storage.sftp_users` adds a local user per partner, signing in with SSH keys to a container of its
own. Opening the account's public endpoint to named public IPv4 ranges lets partners outside your
network connect.

This is the [complete example](./example-complete.md), which also creates the network: the resource
group, the virtual network, the subnets and the private DNS zones.
[Store the engine's files in Blob Storage](./store-files-in-blob-storage.md) and
[Give partners SFTP access](./give-partners-sftp-access.md) say how.

## One module per concern

The root module only composes: it calls one module per concern under `modules/` and wires them
together. Each of those modules can be used on its own, with its own inputs and outputs:

| Module                                    | What it makes                                                    |
| ----------------------------------------- | ---------------------------------------------------------------- |
| [`identity`](./module-identity.md)        | the managed identity                                             |
| [`logs`](./module-logs.md)                | the Log Analytics workspace                                      |
| [`database`](./module-database.md)        | the PostgreSQL flexible server, its database and the URL         |
| [`key_vault`](./module-key-vault.md)      | the Key Vault, its secret, its roles and its audit log           |
| [`container_apps`](./module-container-apps.md) | per slot: the environment, the app and the migrate job     |
| [`storage`](./module-storage.md)          | the storage account with SFTP, its key, its users and its logs   |

Use one on its own when you already have the rest, such as a Key Vault or a workspace your platform
team runs, and compose it with yours. Each module's page says what it needs.

## Related

- [Prepare the network](./prepare-the-network.md): what each shape needs from your network.
- [Limits we rely on](./limits-we-rely-on.md): the Container Apps and Blob Storage behavior these
  shapes depend on.
