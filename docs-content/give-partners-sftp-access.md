---
id: give-partners-sftp-access
title: Give partners SFTP access
sidebar_label: Give partners SFTP access
description: "Add an SFTP user per partner, each signing in with an SSH key to a container of its own, open the account to their addresses, and pick their permissions."
---

# Give partners SFTP access

With storage on, the account takes SFTP, and each partner gets a local user of its own. This page
assumes [storage is on](./store-files-in-blob-storage.md).

## Add a user

Each entry of `storage.sftp_users` is a partner. Name it, give it one to ten SSH public keys, and
say what it may do:

```hcl
  storage = {
    enabled                    = true
    private_endpoint_subnet_id = "<a subnet for private endpoints>"
    private_dns_zone_id        = "<the privatelink.blob.core.windows.net zone>"

    sftp_users = {
      lab = {
        ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleExampleExampleExampleExample lab"]
        permissions     = ["read", "list", "delete"]
      }
    }
  }
```

- A user's name is 3 to 32 lowercase letters and digits, starting with a letter.
- It signs in with an SSH key, never a password. Each key is one public key on one line in
  OpenSSH form; the plan refuses a private key.
- It gets a container of its own, `sftp-` followed by its name, as its home directory, and its
  permissions on that container alone.
- The default permissions, create, write and list, let a partner drop files. A partner that fetches
  files needs read, list and delete.

## Open the account to partners outside your network

A partner on your virtual network reaches the account through its private endpoint. A partner on
the internet needs the public endpoint, opened to its addresses only:

```hcl
    public_network_access_enabled = true
    allowed_ip_ranges             = ["198.51.100.0/24", "203.0.113.7"]
```

Each entry is a public IPv4 address or range. The plan refuses an IPv6 range, a `/31` or `/32`
(write the address alone), a private range, a range wider than a `/8`, and a list that adds up to
more addresses than one `/8` holds. Azure Storage's IP rules take public IPv4 only.

## Tell the partner how to connect

The `storage` output gives the host and each user's sign-in name:

```bash
terraform output -json storage
```

The partner connects to `sftp_host` on port 22, as the user's `username`, which is the account's
name, a dot and the user's name:

```bash
sftp -i ~/.ssh/lab_ed25519 -o User=stpwexample.lab stpwexample.blob.core.windows.net
```

## Read what a partner sent

The app gets `PATHWAYS_SFTP_<USER>_CONTAINER` for each user, the name in capitals. A source that
takes each file the lab drops:

```yaml
source:
  file:
    dir: inbox
    minAge: 1m
    azblob:
      account: { env: PATHWAYS_AZBLOB_ACCOUNT }
      container: { env: PATHWAYS_SFTP_LAB_CONTAINER }
```

Give it a `minAge` longer than an upload takes: nothing we found hides a file from the engine until
its upload ends.

## Rotate a key, remove a user

Change `ssh_public_keys` and apply: the user's keys are replaced. Remove the user's entry and apply
to remove the user; its container goes with it, and the blobs in it are kept for the soft-delete
retention.

## Stop SFTP while no one uses it

SFTP is billed by the hour while it is on, whether anyone connects or not. With no users, set
`storage.sftp_enabled = false` to stop it; the plan refuses users while SFTP is off.

## What SFTP on Blob Storage cannot do

- No Microsoft Entra ID sign-in: a local user is not an Entra identity, so there is no conditional
  access or multi-factor sign-in for it.
- A home directory is not a jail: it sets where a session starts. That is why each user has a
  container of its own.
- It needs hierarchical namespace, which is set when the account is made; turning it off replaces
  the account.
- SFTP only: no FTP and no FTPS.

[Limits we rely on](./limits-we-rely-on.md#sftp-on-blob-storage) has the list with Microsoft's pages.

## Related

- [The storage module](./module-storage.md): every setting and what the plan refuses.
- [The complete example](./example-complete.md): one partner, end to end.
