# cosyte/terraform-azurerm-pathways

A Terraform module that provisions Cosyte Pathways on Azure Container Apps. It follows the public registry's
layout for one module per repository with nested modules: the root holds only `versions.tf`,
`variables.tf`, `main.tf` (the composition) and `outputs.tf`; each concern is a module under
`modules/<name>/` with the same four files, a short README and a `tests/` folder, usable on its own.
`examples/` holds full configurations and `tests/` the root module's tests. The README shows the
tree. A new resource goes in the module for its concern, never at the root. Tools pin in `mise.toml`.
`docs-content/` holds the pages docs.cosyte.com renders, after config's docs-content standard.

## Gate

From the repo root, on the pinned versions. `mise exec` puts them on the path; it skips tflint,
whose mise backend fails its attestation check, and `scripts/policy.sh` downloads the pinned tflint
and checks its checksum instead:

```sh
MISE_DISABLE_TOOLS=tflint mise exec -- terraform fmt -check -recursive
scripts/check-no-emdash.sh
python3 -m unittest discover -s scripts -p 'test_*.py'
MISE_DISABLE_TOOLS=tflint mise exec -- scripts/docs.sh --check
MISE_DISABLE_TOOLS=tflint mise exec -- scripts/validate.sh
MISE_DISABLE_TOOLS=tflint mise exec -- actionlint .github/workflows/*.yml
MISE_DISABLE_TOOLS=tflint mise exec -- scripts/policy.sh
MISE_DISABLE_TOOLS=tflint mise exec -- tests/run.sh
```

`scripts/docs.sh` (with `scripts/docs.py`, standard library Python, and the terraform-docs pinned in
`mise.toml`) writes the pages the code owns: the reference of every input and output, one page for
the root module and one per module, and the Files section of each example's page. `--check` writes
nothing and fails when one differs from the code, when a folder under `examples/` has no
`docs-content/example-<name>.md` with "What it deploys", "What it costs to leave running" and
"Files" sections, when a page is not in `sidebars.json`, or when a link between pages breaks. A
change to an input, an output or an example is committed with the pages `scripts/docs.sh` rewrites.
`scripts/test_docs.py` tests `docs.py`.

`scripts/validate.sh` runs `terraform init -backend=false` and `terraform validate` in the root module,
in each module under `modules/` and in each example. `scripts/policy.sh` runs tflint with the azurerm
ruleset (pinned in `.tflint.hcl`) and `trivy config` at HIGH and CRITICAL. `tests/run.sh` runs
`terraform test` in the root module, in each module under `modules/` and in each example under `examples/`, against mocked azurerm and
azapi providers, plan only, with every Azure credential variable unset; it refuses a run block that
does not plan, a module or an example without tests, an example folder with no Terraform that holds
anything but a README.md (a shape not supported yet), and a test file that does not mock a provider its module
requires. None of them needs or reads an Azure credential.

CI runs the same checks on every pull request: `fmt`, `validate`, `test`, `policy`, `actionlint` and
`docs` (which adds the standard's own structure check, `cosyte-docs-content`) in `ci.yml`, `no-emdash` (the tracked files, the PR title and body, and the commit messages) in
`no-emdash.yml`, and `pr-title` in `pr-title.yml`.

## Releasing

A release is a tag. Rename the `Unreleased` heading of `CHANGELOG.md` to the version, merge that,
then push the tag `v<version>` on that commit of main. `release.yml` refuses a tag that is not on
main or whose version has no CHANGELOG section, runs validate, the tests and the docs check, and
creates the GitHub release with `docs-content.tar.gz` (the quality pages' "Current numbers" filled
in from that run) and `source.tar.gz`, then asks cosyte/docs to rebuild.

## Hazard: this module creates infrastructure that carries PHI

A consumer applies this module in their own cloud account to run an engine that moves PHI-bearing
messages. A wrong default (a public endpoint, an unencrypted volume, a broad role, logs that carry
message bodies) exposes patient data in someone else's account, and they may not notice.

- Secure by default: private networking, encryption at rest and in transit, least privilege.
- No test or example applies to a real account. Tests plan against mocked providers only.
- No secret, account id or real hostname in any file. Synthetic values only.
- We, not third person. Cosyte with a capital C. No em or en dashes. The only compliance claim is that
  we sign Business Associate Agreements; never call software HIPAA compliant.
