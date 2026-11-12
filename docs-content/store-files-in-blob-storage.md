---
id: store-files-in-blob-storage
title: Store the engine's files in Blob Storage
sidebar_label: Turn on storage
description: "Turn on the optional storage account, so the engine's channels read and write blobs as its managed identity, through a private endpoint."
---

# Store the engine's files in Blob Storage

The module can create a storage account for the engine's own blobs and for files partners send and
fetch. It is off unless you turn it on. With it on, the engine reads and writes the account as its
managed identity, through a private endpoint, and no key is ever handed to it.

## Turn it on

Add a `storage` block to the module call, with the blob private endpoint's subnet and the
`privatelink.blob.core.windows.net` zone:

```hcl
module "pathways" {
  source = "github.com/cosyte/terraform-azurerm-pathways?ref=v0.0.1"

  # The other inputs, as before.

  storage = {
    enabled                    = true
    private_endpoint_subnet_id = "<a subnet for private endpoints>"
    private_dns_zone_id        = "<the privatelink.blob.core.windows.net zone>"
  }
}
```

The endpoint is required: the engine reaches the account through it, since Azure Storage's IP
rules do not apply to traffic from the same region. [Prepare the network](./prepare-the-network.md#the-private-dns-zones)
says how to make the zone.

With storage on, the provider writes to the account's data plane with Microsoft Entra ID, since the
account's shared keys are off. Set it on the provider:

```hcl
provider "azurerm" {
  features {}
  storage_use_azuread = true
}
```

## What it creates

- A StorageV2 account named `st` followed by your `name` without its hyphens, unless you set
  `storage.account_name`, with hierarchical namespace on, shared keys off, HTTPS only, TLS 1.2 at
  least, no public containers and no public network access.
- The engine's container, `pathways` unless you set `storage.container_name`.
- A customer-managed key in the module's Key Vault, rotated every year, and an identity of the
  account's own that reads it. Set `storage.customer_managed_key_enabled = false` to use
  Microsoft-managed keys instead. Whoever applies gets Key Vault Crypto Officer on the vault, to
  create the key.
- Storage Blob Data Contributor for the engine's identity on each container.
- The blob service's read, write and delete logs, sent to the Log Analytics workspace. They name
  blobs and callers, never what a blob holds, so keep patient data out of blob names.

## Read the names from a channel

The app gets these plain environment variables, so a channel names the account and its containers
without a key:

| Variable                         | Value                                                          |
| -------------------------------- | -------------------------------------------------------------- |
| `AZURE_CLIENT_ID`                | the client id of the app's identity, for Azure's default chain |
| `PATHWAYS_AZBLOB_ACCOUNT`        | the account's name                                             |
| `PATHWAYS_AZBLOB_CONTAINER`      | the engine's own container                                     |
| `PATHWAYS_SFTP_<USER>_CONTAINER` | each SFTP user's container, the user's name in capitals        |

A destination that writes each output as a blob in the engine's container:

```yaml
destinations:
  - file:
      dir: outbox
      azblob:
        account: { env: PATHWAYS_AZBLOB_ACCOUNT }
        container: { env: PATHWAYS_AZBLOB_CONTAINER }
```

Your project's image needs the `@azure/storage-blob` and `@azure/identity` packages for the
`azblob` block: see [Read and write Azure Blob Storage](https://docs.cosyte.com/pathways/read-and-write-azure-blob-storage)
in the Pathways docs. The plan refuses these variable names in `environment_variables` while
storage is on, since the module sets them.

## Keep deleted blobs for longer, or shorter

Deleted blobs and containers are kept for `storage.soft_delete_retention_days`, 7 by default and
up to 365, and are billed while they are kept. Redundancy is `storage.replication_type`, `LRS` by
default.

## Related

- [Give partners SFTP access](./give-partners-sftp-access.md): users, keys and containers.
- [The storage module](./module-storage.md): every setting, generated from the code.
- [Inputs and outputs](./inputs-and-outputs.md#storage): the root module's `storage` input.
