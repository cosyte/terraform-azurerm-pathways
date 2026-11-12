---
id: troubleshooting
title: Troubleshooting
sidebar_label: Troubleshooting
description: "What to do when a plan is refused, an apply cannot reach the Key Vault, a revision does not start, a name is taken, or a partner cannot sign in over SFTP."
---

# Troubleshooting

## The plan stops with an error from a variable's check

Each input checks its value when you plan, and its message says what is wrong and what to do.
[Inputs and outputs](./inputs-and-outputs.md) lists every check of every input, with its message.
The ones people meet first:

- **The image is not pinned by digest.** Each slot's `image` ends in `@sha256:` and 64 hex digits.
  Look the digest up after you push the image, and use the whole reference.
- **Nothing could reach the Key Vault.** Set `key_vault.private_endpoint_subnet_id` and
  `key_vault.private_dns_zone_id`, or open the vault's public endpoint to named addresses. See
  [Prepare the network](./prepare-the-network.md#how-you-apply).
- **A public environment with no allowed ranges.** `internal_load_balancer_enabled = false` needs
  `ingress_allowed_cidrs`. See [Deployment shapes](./deployment-shapes.md#public-intake).
- **A port Container Apps keeps for itself.** 80, 443 and 36985 cannot be MLLP ports, nor can
  `probes_port`. See [Limits we rely on](./limits-we-rely-on.md#container-apps-ingress).

## The apply cannot write the database URL secret

The apply writes `database-url` into the Key Vault, and fails with a forbidden or a connection
error when the machine that applies cannot reach the vault. With the private endpoint, apply from
inside the virtual network, or a network peered with it, where `privatelink.vaultcore.azure.net`
resolves the vault to its private address. A role is not the problem: the module gives whoever
applies Key Vault Secrets Officer on the vault.

## The revision does not start

See its state and its log:

```bash
az containerapp revision list --name pw-example-blue --resource-group rg-pathways-example \
  --query "[].{name:name, health:properties.healthState, running:properties.runningState}" --output tsv
az containerapp logs show --name pw-example-blue --resource-group rg-pathways-example --tail 100
```

The usual causes:

- **A master key is not in the vault yet.** Each secret named in `encryption_key_secrets` must
  exist before the revision starts. Put it there, then make a new revision by applying again.
- **The engine refuses its configuration.** The log names the file, the key and why: a missing
  `PATHWAYS_KEY_*`, or a database URL without TLS. `pathways validate` on your project, before you
  build the image, finds most of these: see
  [Check configuration](https://docs.cosyte.com/pathways/check-configuration) in the Pathways docs.
- **The probes ask where the engine does not listen.** The project's `pathways.yaml` needs a
  `probes` block with `port` equal to `probes_port` (9091 by default) and `host: 0.0.0.0`.
- **The image cannot be pulled.** For a private registry, set `container_registry_server` and give
  the module's identity AcrPull on it; the `identity` output gives its principal id.

## The name is already taken

The Key Vault and the PostgreSQL server have names that are global across Azure, built from `name`:
`kv-` and `psql-` followed by it. A destroyed Key Vault stays soft-deleted, with its name taken,
for its retention, 90 days by default, and purge protection stops anyone purging it sooner. Pick a
`name` nobody else uses, and a new one after a destroy.

## A sender cannot connect

- Check the address: the `slots` output gives each slot's `static_ip`. With the internal load
  balancer it is a private address, reachable only from your network.
- Check the range: with `ingress_allowed_cidrs` set, every other address is denied. Add the
  sender's range.
- Check the port: the sender's port is one of `mllp_ports`, and the engine's MLLP source listens on
  the same port, on `0.0.0.0`.

## A partner cannot sign in over SFTP

- The sign-in name is the account's name, a dot and the user's name, such as `stpwexample.lab`, at
  the account's blob host. The `storage` output gives both.
- The partner signs in with the private half of one of the keys in `ssh_public_keys`, never a
  password.
- From the internet, the account's public endpoint must be open
  (`storage.public_network_access_enabled = true`) and the partner's public IPv4 address within one
  of `storage.allowed_ip_ranges`.
- SFTP must be on: `storage.sftp_enabled` is true by default.

## Related

- [Limits we rely on](./limits-we-rely-on.md)
- [Troubleshooting](https://docs.cosyte.com/pathways/troubleshooting) in the Pathways docs, for the
  engine's own messages.
