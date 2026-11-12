#!/usr/bin/env bash
#
# Runs the plan-only tests against mocked providers: the root module's (tests/*.tftest.hcl), each
# module's under modules/ (modules/<name>/tests/*.tftest.hcl), each module as the root of its own
# run, the way a caller who uses it on its own would, and each example's under examples/
# (examples/<name>/tests/*.tftest.hcl), the example as a caller would apply it.
#
#   tests/run.sh
#
# What this script enforces before Terraform runs, because a test that can reach a real account is
# worse than none:
#   * every module under modules/ and every example under examples/ has tests;
#   * an example folder with no .tf file (a shape not supported yet) holds a README.md and nothing
#     else, so no Terraform for a shape the engine cannot run safely slips in beside it;
#   * every run block says `command = plan` (terraform test defaults to apply);
#   * every test file mocks each of azurerm and azapi that its module requires;
#   * no Azure credential reaches Terraform: the ARM_ and AZURE_ credential variables are unset,
#     and the Azure CLI's configuration points at an empty folder, so a provider that tried to reach
#     Azure would find nothing to sign in with.
#
# It leaves nothing behind: each .terraform/ and lock file `terraform init` writes is removed on
# every exit path, so no lock file is committed.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
cd "$root"

fail() {
  echo "tests/run.sh: $*" >&2
  exit 1
}

dirs=(.)
while IFS= read -r d; do
  dirs+=("$d")
done < <(find modules -mindepth 1 -maxdepth 1 -type d | sort)

while IFS= read -r d; do
  shopt -s nullglob
  tf=("${d}"/*.tf)
  shopt -u nullglob
  if [ "${#tf[@]}" -gt 0 ]; then
    dirs+=("$d")
  else
    others=$(find "$d" -mindepth 1 ! -name README.md -print | head -n 1)
    [ -f "${d}/README.md" ] && [ -z "$others" ] \
      || fail "${d} has no .tf file, so it must hold a README.md and nothing else"
  fi
done < <(find examples -mindepth 1 -maxdepth 1 -type d | sort)

# The providers that reach Azure, by local name; a module that requires one must mock it.
cloud_providers=(azurerm azapi)

for d in "${dirs[@]}"; do
  shopt -s nullglob
  files=("${d}"/tests/*.tftest.hcl)
  shopt -u nullglob
  [ "${#files[@]}" -gt 0 ] || fail "no .tftest.hcl file found in ${d}/tests/"

  required=()
  for p in "${cloud_providers[@]}"; do
    if grep -qE "^[[:space:]]+${p}[[:space:]]*=[[:space:]]*\{" "${d}/versions.tf"; then
      required+=("$p")
    fi
  done

  for f in "${files[@]}"; do
    runs=$(grep -cE '^run "' "$f" || true)
    plans=$(grep -cE '^[[:space:]]+command[[:space:]]*=[[:space:]]*plan[[:space:]]*$' "$f" || true)
    commands=$(grep -cE '^[[:space:]]*command[[:space:]]*=' "$f" || true)
    [ "$runs" -gt 0 ] || fail "${f} has no run block"
    [ "$plans" -eq "$runs" ] && [ "$commands" -eq "$runs" ] \
      || fail "${f}: ${runs} run block(s) but ${plans} 'command = plan' line(s) of ${commands} command line(s); every run block must plan, never apply"
    # A run block that points at another module would escape the mocks checked against this one.
    if grep -qE '^[[:space:]]+module[[:space:]]*\{' "$f"; then
      fail "${f} has a run block with a module block; test each module from its own tests/ folder"
    fi
    for p in "${required[@]}"; do
      grep -qE "^mock_provider \"${p}\"" "$f" || fail "${f} does not mock the ${p} provider"
    done
  done
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
  for d in "${dirs[@]}"; do
    rm -rf "${root}/${d}/.terraform" "${root}/${d}/.terraform.lock.hcl"
  done
  rm -rf "$empty_az"
}
trap cleanup EXIT INT TERM

failed=()
for d in "${dirs[@]}"; do
  echo "::group::terraform test in ${d}"
  if ! terraform -chdir="$d" init -backend=false -input=false -no-color; then
    failed+=("${d} (init)")
  elif ! terraform -chdir="$d" test -no-color; then
    failed+=("${d} (test)")
  fi
  echo "::endgroup::"
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "tests/run.sh: failed in ${#failed[@]} of ${#dirs[@]} folders:" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "Tested ${#dirs[@]} folders."
