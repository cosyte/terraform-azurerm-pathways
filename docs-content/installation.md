---
id: installation
title: Install the module
sidebar_label: Installation
description: "What you need before you call the module: Terraform, the providers, the Azure roles, a network and an image, and the source line to use."
---

# Install the module

A Terraform module is not installed: a configuration names it in a `module` block's `source`, and
`terraform init` downloads it. This page says what that configuration needs around it.

## What you need

- **Terraform 1.11 or later.** The module's variable checks read other variables, which 1.9 added,
  and the alarms write their health token to the Key Vault through a write-only argument, which 1.11
  added, so the token is never in the plan or the state. Our CI runs the version pinned in the
  repository's `mise.toml`.
- **The providers,** which `terraform init` installs: `hashicorp/azurerm` 4.42 or later below 5,
  `azure/azapi` 2 or later below 3, and `hashicorp/random` 3.7 or later below 4. The app is written
  through `azapi`, since `azurerm_container_app` does not expose TCP ingress with additional ports.
- **An Azure subscription, and a sign-in that can assign roles in it.** The module creates role
  assignments (Key Vault Secrets User for the engine's identity, Key Vault Secrets Officer for
  whoever applies, and more with storage on), so the identity that applies needs Owner, or
  Contributor with User Access Administrator, on the resource group.
- **A virtual network,** with a delegated subnet per slot, a delegated subnet for the database, a
  subnet for private endpoints and the private DNS zones. [Prepare the network](./prepare-the-network.md)
  lists them, and the [complete example](./example-complete.md) creates them.
- **Your project's image, pinned by digest,** built on the Pathways image. See
  [Deploy the image](https://docs.cosyte.com/pathways/deploy-the-image) in the Pathways docs. The
  plan refuses an image without a digest.
- **A machine that can reach the Key Vault** when you apply: inside the virtual network, or peered
  with it, since the vault is reached only through its private endpoint by default.

## The source line

Until the module is published to a registry, name it on GitHub, at a release tag. `v0.0.1` is the
first; the [releases page](https://github.com/cosyte/terraform-azurerm-pathways/releases) lists
each one with what changed.

```hcl
module "pathways" {
  source = "github.com/cosyte/terraform-azurerm-pathways?ref=v0.0.1"

  # The inputs: see the quickstart and the reference.
}
```

Pin the tag. Without `?ref=`, `terraform init` takes whatever the default branch holds that day.
Each module under `modules/` can also be used on its own, with a double slash before its path:

```hcl
module "database" {
  source = "github.com/cosyte/terraform-azurerm-pathways//modules/database?ref=v0.0.1"

  # Its inputs: see its page under Reference.
}
```

Then, in the folder of your configuration:

```bash
az login
terraform init
```

`terraform init` downloads the module and the three providers. The `azurerm` provider signs in the
way `az login` did, unless you give it other credentials.

## Next

- [Quickstart](./quickstart.md): deploy the basic example.
- [Inputs and outputs](./inputs-and-outputs.md): every input the module takes.
