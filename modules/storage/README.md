# storage

A StorageV2 account with hierarchical namespace and SFTP on, for files partners send and fetch over
SFTP and for the engine's own blobs:

- no public network access by default, a blob private endpoint (which SFTP uses too), and, when you
  open the public endpoint, an IP firewall of the public IPv4 ranges you name;
- shared keys off, HTTPS only, TLS 1.2 at least, no public containers, infrastructure encryption,
  and blob and container soft delete;
- encryption with a customer-managed key the module creates in your Key Vault, read by an identity
  of the account's own, unless `customer_managed_key_enabled = false`;
- the engine's container, and one container per SFTP user, `sftp-<user>`, as that user's home
  directory, with a permission on that container alone;
- each SFTP user signing in with SSH keys only, never a password;
- Storage Blob Data Contributor on each container for the engine's identity, so the engine needs no
  account key;
- the blob service's read, write and delete logs sent to a Log Analytics workspace.

The plan refuses an IP range wider than a `/8` (`0.0.0.0/0` included), a list of ranges that adds up
to every IPv4 address, an IPv6 range, a `/31` or `/32`, a private range, a public endpoint with no
ranges, a user with no key, a private key, and a permission other than create, write, list, read and
delete.

The root module calls it when `storage.enabled` is true, with its Key Vault, identity and workspace.
To use it on its own:

```hcl
module "storage" {
  source = "github.com/cosyte/terraform-azurerm-pathways//modules/storage"

  name                = "pw-example"
  resource_group_name = "rg-pathways-example"
  location            = "eastus2"

  private_endpoint_subnet_id = "<a subnet for private endpoints>"
  private_dns_zone_id        = "<the privatelink.blob.core.windows.net zone>"

  key_vault_id               = "<a Key Vault with purge protection and RBAC authorization>"
  blob_data_principal_id     = "<the principal id of the identity the engine runs as>"
  log_analytics_workspace_id = "<a Log Analytics workspace id>"

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

A user signs in as `<account>.<user>` at `<account>.blob.core.windows.net`, port 22, and lands in
its container. The root README's [Storage and SFTP](../../README.md#storage-and-sftp) section says
what SFTP on Blob Storage cannot do, and what the account costs.

Inputs are in [variables.tf](variables.tf) and outputs in [outputs.tf](outputs.tf). Its tests are
in [tests/](tests), run by `tests/run.sh` at the repo root.
