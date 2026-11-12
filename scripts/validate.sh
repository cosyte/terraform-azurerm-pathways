#!/usr/bin/env bash
#
# terraform init -backend=false and terraform validate in the module root and in each folder under
# examples/. Needs no credentials: validate reads the configuration and the provider schemas only.
# Removes each .terraform/ and lock file it makes, so no lock file is committed.
#
#   scripts/validate.sh

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
cd "$root"

export TF_IN_AUTOMATION=1
export TF_INPUT=0

dirs=(.)
while IFS= read -r d; do
  dirs+=("$d")
done < <(find examples -mindepth 1 -maxdepth 1 -type d | sort)

if [ "${#dirs[@]}" -lt 2 ]; then
  echo "scripts/validate.sh: no example under examples/" >&2
  exit 1
fi

cleanup() {
  for d in "${dirs[@]}"; do
    rm -rf "${root}/${d}/.terraform" "${root}/${d}/.terraform.lock.hcl"
  done
}
trap cleanup EXIT INT TERM

failed=()
for d in "${dirs[@]}"; do
  echo "::group::${d}"
  if ! terraform -chdir="$d" init -backend=false -input=false -no-color; then
    failed+=("${d} (init)")
  elif ! terraform -chdir="$d" validate -no-color; then
    failed+=("${d} (validate)")
  fi
  echo "::endgroup::"
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "scripts/validate.sh: failed in ${#failed[@]} of ${#dirs[@]} folders:" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "Validated ${#dirs[@]} folders."
