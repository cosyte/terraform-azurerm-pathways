---
id: testing-and-quality
title: Testing and quality
sidebar_label: Testing and quality
description: "How we test the module without an Azure account: terraform test on mocked providers, validate, tflint, trivy and the docs checks."
---

# Testing and quality

The module creates infrastructure that carries patient data in someone else's subscription, so a
wrong default is the failure we test hardest against: a public endpoint, a broad role, a secret
passed as a plain value. No test or check signs in to Azure or applies anything. Every one reads
the code, or plans against mocked providers, with every Azure credential unset. The numbers for the
current release are in [Current numbers](#current-numbers) below.

## What we run, and what each catches

| Check | What it does | What it catches | What it cannot catch |
| --- | --- | --- | --- |
| `terraform test` (`tests/run.sh`) | plans the root module, each module under `modules/` and each example under `examples/` against mocked `azurerm` and `azapi` providers, with assertions on what the plan would create | a default that changed, a resource that is or is not created, an input the plan should refuse but accepts, a wrong value wired from one module to another | anything Azure decides at apply time: a quota, a name taken, an API that refuses a setting, a limit the documentation does not state |
| `terraform validate` (`scripts/validate.sh`) | `terraform init` and `validate` in the root, each module and each example | a configuration that does not parse, an unknown argument, a type that does not fit, an example that no longer matches the module's inputs | whether a valid configuration does what we meant |
| tflint, with the azurerm ruleset (`scripts/policy.sh`) | lints every module and example | a value the ruleset knows Azure refuses, such as an unknown SKU, a deprecated argument, an unused declaration | a setting that is valid and unsafe |
| trivy, at HIGH and CRITICAL (`scripts/policy.sh`) | scans the configuration for known misconfigurations; a finding we accept is marked in the code with its reason | a public endpoint, encryption off, a network rule that allows everything | a risk no rule of its own names |
| `terraform fmt -check` | the layout of every file | a file not in the canonical layout | anything else |
| The docs checks (`scripts/docs.sh --check`, `cosyte-docs-content`) | regenerate the reference and each example's files, and read the pages' shape | a reference page out of date with the code, an example with no page, a page whose files drifted, a broken link between pages | whether a page's prose is right |
| actionlint, and the dash check | lint the workflows, and scan every file and the pull request's text | a workflow that would fail to start; a character our style forbids | anything else |

`tests/run.sh` also refuses to run a test that could reach Azure: a run block that does not say
`command = plan`, a test file that does not mock a provider its module requires, and a module
without tests.

## What no check here can catch

The module has not yet been applied to a real Azure subscription by us. Mocked providers return
what the test tells them to, so a plan that passes here can still fail at apply time, and a
behavior Azure documents can differ from what it does. [Limits we rely on](./limits-we-rely-on.md)
lists the behaviors a live test still has to confirm.

## Run them yourself

The tools are pinned in `mise.toml`. From a clone, with [mise](https://mise.jdx.dev) installed:

```bash
mise install
MISE_DISABLE_TOOLS=tflint mise exec -- tests/run.sh
MISE_DISABLE_TOOLS=tflint mise exec -- scripts/validate.sh
MISE_DISABLE_TOOLS=tflint mise exec -- scripts/policy.sh
MISE_DISABLE_TOOLS=tflint mise exec -- scripts/docs.sh --check
```

None of them needs or reads an Azure credential. `scripts/policy.sh` downloads the pinned tflint
and trivy and checks their checksums.

## Current numbers

The numbers for this section are measured on `main` at each release and filled in when the
release is built. They are never typed by hand.
