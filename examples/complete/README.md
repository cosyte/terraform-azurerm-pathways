# examples/complete

**Shape:** SFTP and storage.

Pathways stood up end to end with a storage account and SFTP for one partner: the network, the module and, in `project/`, a channel that takes orders over MLLP and writes each to the partner's SFTP container.

## What it builds

- The resource group `rg-pw-example`, the virtual network `vnet-pw-example` (`10.40.0.0/16`) with a delegated subnet for the slot, one for the database and one for private endpoints, and the private DNS zones for the database, the Key Vault and Blob Storage, each linked to the network.
- The module, as in the basic example, with a storage account: hierarchical namespace and SFTP on, shared keys off, a customer-managed key from the Key Vault, a blob private endpoint, and its public endpoint open only to the lab's ranges for SFTP.
- The SFTP user `lab`, signing in with an SSH key to its own container, with read, list and delete.
- In `project/`, the Pathways project the image is built from: one channel that takes orders over MLLP on 2575 and writes each as a file to the lab's container.

## When to choose it

Partners send or fetch files over SFTP, or the engine keeps its own files in Blob Storage, or you are starting with no network at all.

## What it costs

We give what Azure bills for, not prices: the pricing pages for your region, and your agreement
with Microsoft, set those.

- Everything the basic example bills for.
- SFTP, by the hour while it is enabled, whether anyone connects or not.
- The storage account's data, soft-deleted data included, its read, write and list operations, and the blob private endpoint by the hour.
- Key Vault operations for the customer-managed key, and Log Analytics ingestion for the account's read, write and delete logs.

## What it does not cover

- No standby and no zone-redundant database.
- SFTP signs in local users with SSH keys only: there is no Microsoft Entra sign-in for them.
- Partners outside the network reach SFTP through the account's public endpoint, open to their named public IPv4 ranges; nothing else in the example is public.

## Run it

Every name, id and range in it is a placeholder: replace them with your own. Our CI validates it
and plans it against mocked providers (`tests/`), and never applies it.

```sh
terraform init
terraform plan
```
