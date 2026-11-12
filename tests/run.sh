#!/usr/bin/env bash
#
# Runs the module's plan-only tests (tests/*.tftest.hcl) against mocked providers.
#
#   tests/run.sh
#
# What this script enforces before Terraform runs, because a test that can reach a real account is
# worse than none:
#   * every run block says `command = plan` (terraform test defaults to apply);
#   * every test file mocks the azurerm and azapi providers;
#   * no Azure credential reaches Terraform: the ARM_ and AZURE_ credential variables are unset,
#     and the Azure CLI's configuration points at an empty folder, so a provider that tried to reach
#     Azure would find nothing to sign in with.
#
# It leaves nothing behind: .terraform/ and the lock file `terraform init` writes are removed on
# every exit path, so no lock file is committed.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
cd "$root"

fail() {
  echo "tests/run.sh: $*" >&2
  exit 1
}

shopt -s nullglob
files=(tests/*.tftest.hcl)
shopt -u nullglob
[ "${#files[@]}" -gt 0 ] || fail "no .tftest.hcl file found in tests/"

for f in "${files[@]}"; do
  runs=$(grep -cE '^run "' "$f" || true)
  plans=$(grep -cE '^[[:space:]]+command[[:space:]]*=[[:space:]]*plan[[:space:]]*$' "$f" || true)
  commands=$(grep -cE '^[[:space:]]*command[[:space:]]*=' "$f" || true)
  [ "$runs" -gt 0 ] || fail "${f} has no run block"
  [ "$plans" -eq "$runs" ] && [ "$commands" -eq "$runs" ] \
    || fail "${f}: ${runs} run block(s) but ${plans} 'command = plan' line(s) of ${commands} command line(s); every run block must plan, never apply"
  grep -qE '^mock_provider "azurerm"' "$f" || fail "${f} does not mock the azurerm provider"
  grep -qE '^mock_provider "azapi"' "$f" || fail "${f} does not mock the azapi provider"
done

while IFS= read -r v; do
  unset "$v"
done < <(env | grep -oE '^(ARM|AZURE)_[A-Z0-9_]*' || true)
unset MSI_ENDPOINT IDENTITY_ENDPOINT IDENTITY_HEADER ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN
empty_az="$(mktemp -d)"
export AZURE_CONFIG_DIR="$empty_az"
export TF_IN_AUTOMATION=1
export TF_INPUT=0

cleanup() {
  rm -rf "${root}/.terraform" "${root}/.terraform.lock.hcl" "$empty_az"
}
trap cleanup EXIT INT TERM

terraform init -backend=false -input=false -no-color
terraform test -no-color
