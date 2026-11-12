# cosyte/terraform-azurerm-pathways

A Terraform module that provisions Cosyte Pathways on Azure Container Apps. It follows the public registry's
layout for one module per repository: `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, an
`examples/` directory and a `tests/` directory. Tools pin in `mise.toml`.

## Gate

From the repo root, on the pinned versions. `mise exec` puts them on the path; it skips tflint,
whose mise backend fails its attestation check, and `scripts/policy.sh` downloads the pinned tflint
and checks its checksum instead:

```sh
MISE_DISABLE_TOOLS=tflint mise exec -- terraform fmt -check -recursive
scripts/check-no-emdash.sh
MISE_DISABLE_TOOLS=tflint mise exec -- scripts/validate.sh
MISE_DISABLE_TOOLS=tflint mise exec -- actionlint .github/workflows/*.yml
MISE_DISABLE_TOOLS=tflint mise exec -- scripts/policy.sh
MISE_DISABLE_TOOLS=tflint mise exec -- tests/run.sh
```

`scripts/validate.sh` runs `terraform init -backend=false` and `terraform validate` in the module and
in each example. `scripts/policy.sh` runs tflint with the azurerm ruleset (pinned in `.tflint.hcl`)
and `trivy config` at HIGH and CRITICAL. `tests/run.sh` runs `terraform test` against mocked azurerm
and azapi providers, plan only, with every Azure credential variable unset; it refuses a run block
that does not plan. None of them needs or reads an Azure credential.

CI runs the same checks on every pull request: `fmt`, `validate`, `test`, `policy` and `actionlint`
in `ci.yml`, `no-emdash` (the tracked files, the PR title and body, and the commit messages) in
`no-emdash.yml`, and `pr-title` in `pr-title.yml`.

## Hazard: this module creates infrastructure that carries PHI

A consumer applies this module in their own cloud account to run an engine that moves PHI-bearing
messages. A wrong default (a public endpoint, an unencrypted volume, a broad role, logs that carry
message bodies) exposes patient data in someone else's account, and they may not notice.

- Secure by default: private networking, encryption at rest and in transit, least privilege.
- No test or example applies to a real account. Tests plan against mocked providers only.
- No secret, account id or real hostname in any file. Synthetic values only.
- We, not third person. Cosyte with a capital C. No em or en dashes. The only compliance claim is that
  we sign Business Associate Agreements; never call software HIPAA compliant.
