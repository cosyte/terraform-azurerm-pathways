# tflint configuration, read by scripts/policy.sh (in the gate in CLAUDE.md and the policy job of
# .github/workflows/ci.yml). tflint itself is pinned in mise.toml; the rulesets are pinned here by
# exact version, and tflint verifies the azurerm ruleset's signature when it installs it.
#
# A rule switched off below names every place it fires and why it is not fixed.

config {
  # Lint the examples' calls into this module against the module.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.28.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
