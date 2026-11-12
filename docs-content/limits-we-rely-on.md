---
id: limits-we-rely-on
title: Limits we rely on
sidebar_label: Limits we rely on
description: "The Container Apps and Blob Storage limits the module checks when you plan, where each comes from, and which are not yet confirmed live."
---

# Limits we rely on

The module checks Azure's limits when you plan, so a configuration Azure would refuse, or would
accept and then not honor, fails before anything is created. Each check comes from Microsoft's
documentation, read in November 2026. None has yet been confirmed against a live environment by us.
The service changes: check Microsoft's pages before you rely on a point.

## Container Apps ingress

From Microsoft's Container Apps ingress documentation:

- At most five additional TCP ports beside the main one, so `mllp_ports` holds one to six ports.
- Every exposed port, main or additional, is unique across an environment. That is why each slot
  has an environment of its own: see [Deployment shapes](./deployment-shapes.md#two-slots-blue-and-green).
- Port 36985 is reserved for the platform's health checks, and ports 80 and 443 belong to the
  environment's HTTP ingress, so none of them can be an MLLP port.

The app's address restrictions, `ingress_allowed_cidrs`, are set once, on its ingress. We expect
them to cover the additional TCP ports as well as the main one, but the documentation does not say
so for additional port mappings. A live test should confirm that a denied address cannot reach an
additional port either.

## The termination grace period

`drain_seconds` sets how long the engine gets to stop after SIGTERM. The documentation gives no
maximum for it, only a default of 30 seconds, and its application lifecycle page still says a
container is killed 30 seconds after SIGTERM. `drain_seconds` defaults to 30 and stops at 600, a
bound of our own. Until a live test shows a longer grace period is honored, plan for a drain of 30
seconds at most.

## Key Vault access

Container Apps is not one of Azure's trusted services, so the vault's `AzureServices` bypass does
not let the apps in. The apps read their secrets through the vault's private endpoint, or through
its public endpoint with their outbound addresses in `key_vault.allowed_ip_ranges`. The plan
refuses a vault nothing could reach.

## SFTP on Blob Storage

From Microsoft's pages on
[SFTP support for Blob Storage](https://learn.microsoft.com/azure/storage/blobs/secure-file-transfer-protocol-support),
[authorizing SFTP access](https://learn.microsoft.com/azure/storage/blobs/secure-file-transfer-protocol-support-authorize-access),
[its known issues](https://learn.microsoft.com/azure/storage/blobs/secure-file-transfer-protocol-known-issues)
and [network security for Azure Storage](https://learn.microsoft.com/azure/storage/common/storage-network-security):

- **No Microsoft Entra ID sign-in.** SFTP clients sign in only as local users of the account, with
  a password or an SSH key, and the module turns passwords off. A local user has no conditional
  access or multi-factor sign-in, and you rotate its keys yourself.
- **A home directory is not a jail.** It only sets where a session starts; a user can reach any
  path in a container its permissions cover. So each user has a container of its own.
- **It needs hierarchical namespace,** which is set when the account is created: turning it off
  replaces the account. Some Blob Storage features are not available on such an account.
- **SFTP only:** no FTP and no FTPS.
- **Nothing we found hides a file until its upload ends.** A source that reads an SFTP container
  needs a `minAge` longer than an upload takes.
- **IP rules take public IPv4 only:** no IPv6, a single address rather than a `/31` or `/32`, no
  private range, and no effect on traffic from the account's own region. The plan refuses the
  first three; the private endpoint covers the last.
- **SFTP is billed by the hour while it is on,** whether anyone connects or not.

## Related

- [Troubleshooting](./troubleshooting.md): what each of these looks like when it bites.
- [Inputs and outputs](./inputs-and-outputs.md#mllp_ports): each check, with its message.
