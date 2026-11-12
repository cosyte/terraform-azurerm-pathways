# cosyte/terraform-azurerm-pathways

A Terraform module that provisions Cosyte Pathways on Azure Container Apps. It follows the public registry's
layout for one module per repository: `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, an
`examples/` directory and a `tests/` directory. Tools pin in `mise.toml`.

## Gate

From the repo root, on the pinned versions (`mise install`):

```sh
terraform fmt -check -recursive
```

Add each further check here in the same change that adds it: `terraform validate`, `terraform test`
with mocked providers, tflint, trivy config and actionlint.

## Hazard: this module creates infrastructure that carries PHI

A consumer applies this module in their own cloud account to run an engine that moves PHI-bearing
messages. A wrong default (a public endpoint, an unencrypted volume, a broad role, logs that carry
message bodies) exposes patient data in someone else's account, and they may not notice.

- Secure by default: private networking, encryption at rest and in transit, least privilege.
- No test or example applies to a real account. Tests plan against mocked providers only.
- No secret, account id or real hostname in any file. Synthetic values only.
- We, not third person. Cosyte with a capital C. No em or en dashes. The only compliance claim is that
  we sign Business Associate Agreements; never call software HIPAA compliant.
