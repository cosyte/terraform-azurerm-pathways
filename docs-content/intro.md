---
id: intro
title: Pathways on Azure Container Apps
sidebar_label: Overview
description: "A Terraform module that runs Cosyte Pathways on Azure Container Apps, private by default, with its database, its secrets and its logs."
---

# Pathways on Azure Container Apps

`terraform-azurerm-pathways` is a Terraform module that runs
[Cosyte Pathways](https://docs.cosyte.com/pathways/intro), our open-source healthcare integration
engine, on Azure Container Apps. It creates the engine and everything it needs to run: a Container
Apps environment on your virtual network, a managed identity, a Key Vault, a PostgreSQL flexible
server, a migrate job and a Log Analytics workspace, and, when you turn it on, a storage account
with SFTP for partners' files.

Pathways carries messages that hold patient data, so the defaults are private networking, TLS to
the database, secrets only in Key Vault and least-privilege roles. The module checks the Container
Apps limits it relies on when you plan, rather than when you apply.

## Status

The module is built and tested against mocked providers, and has not yet been applied to a real
Azure subscription by us. Every page here describes what the code asks Azure for; where a behavior
of Azure itself has not been confirmed live, the page says so. [Limits we rely on](./limits-we-rely-on.md)
lists those.

## Who it is for

Teams that run Pathways in their own Azure subscription and manage it with Terraform. You bring
the virtual network, its subnets and the private DNS zones, and an image of your Pathways project
pinned by digest; the module does the rest.

## What it is not

- It does not build your image. [Deploy the image](https://docs.cosyte.com/pathways/deploy-the-image)
  in the Pathways docs says how.
- It does not create the virtual network, unless you start from the
  [complete example](./example-complete.md), which does.
- It does not create alert rules yet: they wait for the metric names Pathways will publish.
- It is not released to a registry yet. Until it is, use it from GitHub by tag, as
  [Installation](./installation.md) shows.

## Where to go next

- [Installation](./installation.md): what you need, and the `source` line.
- [Quickstart](./quickstart.md): deploy the basic example, one slot, from start to a running
  engine.
- [Deployment shapes](./deployment-shapes.md): one slot or two, private or public intake, with or
  without storage.
- [Inputs and outputs](./inputs-and-outputs.md): every input and output, generated from the code.
