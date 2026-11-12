#!/usr/bin/env bash
#
# The pages in docs-content/ that the code owns: the reference of every input and output (the root
# module's and each module's) and the Files section of each example's page. scripts/docs.py says
# what each holds and what the check refuses.
#
#   scripts/docs.sh           write them
#   scripts/docs.sh --check   write nothing; exit 1 when a page differs from what the code gives,
#                             when an example has no page, or when a page breaks a rule docs.py names
#
# terraform-docs is pinned in mise.toml and this script reads the pin from there. If the binary on
# PATH is the pinned version it is used; otherwise the pinned release is downloaded from GitHub into
# a cache folder and checked against the checksums file the same release publishes. It reads the .tf
# files only: no credentials, no state, no terraform init.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
cd "$root"

fail() {
  echo "scripts/docs.sh: $*" >&2
  exit 1
}

mode=generate
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) fail "unknown argument ${1}: run it with no argument to write the pages, or --check" ;;
esac

version=$(awk -F'"' '/^terraform-docs[[:space:]]*=/ {print $(NF-1)}' mise.toml)
[ -n "$version" ] || fail "no terraform-docs pin in mise.toml"

if command -v terraform-docs > /dev/null 2>&1 && terraform-docs --version 2> /dev/null | grep -qF "v${version} "; then
  TFDOCS="$(command -v terraform-docs)"
else
  dir="${XDG_CACHE_HOME:-$HOME/.cache}/cosyte-terraform-docs/terraform-docs-${version}"
  asset="terraform-docs-v${version}-linux-amd64.tar.gz"
  if [ ! -x "${dir}/terraform-docs" ]; then
    echo "Fetching terraform-docs ${version}" >&2
    base="https://github.com/terraform-docs/terraform-docs/releases/download/v${version}"
    rm -rf "$dir"
    mkdir -p "$dir"
    curl -fsSL --retry 3 -o "${dir}/${asset}" "${base}/${asset}"
    curl -fsSL --retry 3 -o "${dir}/checksums.txt" "${base}/terraform-docs-v${version}.sha256sum"
    (cd "$dir" && grep -E "[[:space:]]\*?${asset}\$" checksums.txt | sha256sum -c - >&2)
    tar -xzf "${dir}/${asset}" -C "$dir" terraform-docs
    [ -x "${dir}/terraform-docs" ] || fail "terraform-docs ${version}: the download held no binary"
  fi
  TFDOCS="${dir}/terraform-docs"
fi

"$TFDOCS" --version
exec python3 "${here}/docs.py" "$mode" --terraform-docs "$TFDOCS"
