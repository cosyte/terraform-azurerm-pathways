#!/usr/bin/env bash
# scripts/check-no-emdash.sh
#
# We never use the em dash or the en dash, in any file, commit message, PR title or PR body. This
# gate refuses both, as the literal character and in the encoded forms the pattern lists.
#
#   scripts/check-no-emdash.sh                 scan every tracked file
#   scripts/check-no-emdash.sh --stdin LABEL   scan text on stdin (CI feeds it the PR title and body,
#                                              and the commit messages; see no-emdash.yml)
#
# Write a range with "to"; rewrite a pause with a period, a colon, a comma or parentheses.
#
# The pattern and the probe text are assembled from pieces, so this file holds no banned form whole
# and is scanned with the full pattern like every other file. The scanner is probed before each run:
# a grep that cannot see a known dash, or that goes silent on a file with a bad byte (the sign of a
# forced -I), refuses to report green.
set -euo pipefail

unset -f grep xargs git cat mktemp 2> /dev/null || true
unalias grep xargs git cat mktemp 2> /dev/null || true

for c in grep xargs git; do
  t=$(type -t "$c" 2> /dev/null || echo missing)
  if [ "$t" != file ]; then
    echo "ERROR: check-no-emdash - '$c' resolves to '$t', not to a binary on disk. Refusing to run." >&2
    exit 1
  fi
done

# grep -P reads a \x{...} code point only in UTF-8 mode, which the locale turns on.
export LC_ALL=C.UTF-8

# The two code points, in hex: em is 20 then 14, en is 20 then 13.
em='14'
en='13'
amp='&'
pct='%E2%80%'
esc='\\u20'
# For each dash: the character, the URL form, the JavaScript escape and the three HTML entities.
PATTERN="\\x{20${em}}|${pct}94|${esc}${em}|${amp}mdash;|${amp}#8212;|${amp}#x20${em};"
PATTERN+="|\\x{20${en}}|${pct}93|${esc}${en}|${amp}ndash;|${amp}#8211;|${amp}#x20${en};"

# The UTF-8 bytes of each dash, in octal escapes for printf: a shared lead, then the last byte.
lead='\342\200'
EM_BYTES="${lead}\\224"
EN_BYTES="${lead}\\223"

ERRLOG=$(mktemp)
FILELIST=$(mktemp)
STDINBUF=$(mktemp)
PROBEDIR=$(mktemp -d)
trap 'rm -f "$ERRLOG" "$FILELIST" "$STDINBUF"; rm -rf "$PROBEDIR"' EXIT

probe() {
  local a="$PROBEDIR/a.txt" b="$PROBEDIR/b.txt" c="$PROBEDIR/c.txt" d="$PROBEDIR/d.txt"

  # shellcheck disable=SC2059 # the format holds the octal escapes on purpose
  printf "clean ${EM_BYTES} line\n" > "$a"
  grep -H -nP -e "$PATTERN" -- "$a" > "$PROBEDIR/a.out" 2> "$PROBEDIR/a.err" || true
  if [ ! -s "$PROBEDIR/a.out" ]; then
    echo "ERROR: check-no-emdash - the scanner cannot match a known em dash. Refusing to run." >&2
    exit 1
  fi

  # shellcheck disable=SC2059
  printf "broken \377 ${EM_BYTES} line\n" > "$b"
  grep -H -nP -e "$PATTERN" -- "$b" > "$PROBEDIR/b.out" 2> "$PROBEDIR/b.err" || true
  if [ ! -s "$PROBEDIR/b.out" ] && [ ! -s "$PROBEDIR/b.err" ]; then
    echo "ERROR: check-no-emdash - the scanner went silent on a file with a bad byte and a dash" >&2
    echo "       (grep -I forced by a wrapper or GREP_OPTIONS). Refusing to run." >&2
    exit 1
  fi

  {
    # shellcheck disable=SC2059
    printf "a ${EN_BYTES} b\n"
    printf '%s93\n' "$pct"
    printf '%s%s\n' '\u20' "$en"
    printf '%sndash;\n' "$amp"
    printf '%s#8211;\n' "$amp"
    printf '%s#x20%s;\n' "$amp" "$en"
  } > "$c"
  grep -H -nP -e "$PATTERN" -- "$c" > "$PROBEDIR/c.out" 2> "$PROBEDIR/c.err" || true
  if [ "$(grep -c '' "$PROBEDIR/c.out")" -ne 6 ] || [ -s "$PROBEDIR/c.err" ]; then
    echo "ERROR: check-no-emdash - the scanner did not match all six forms of an en dash. Refusing to run." >&2
    exit 1
  fi

  printf 'a-b, pages 2 to 3, \342\210\2221\n' > "$d"
  grep -H -nP -e "$PATTERN" -- "$d" > "$PROBEDIR/d.out" 2> "$PROBEDIR/d.err" || true
  if [ -s "$PROBEDIR/d.out" ] || [ -s "$PROBEDIR/d.err" ]; then
    echo "ERROR: check-no-emdash - the scanner matched clean text (a hyphen, a minus sign). Refusing to run." >&2
    exit 1
  fi
}
probe

fail_with_hits() {
  echo "$2" >&2
  echo "" >&2
  echo "ERROR: check-no-emdash - an em or en dash, or an encoded form of one, found in $1." >&2
  echo "       Write a range with \"to\"; rewrite a pause with a period, colon, comma or parentheses." >&2
  exit 1
}

refuse_if_incomplete() {
  [ -s "$ERRLOG" ] || return 0
  cat "$ERRLOG" >&2
  echo "ERROR: check-no-emdash - the scan reported errors, so it did not read all of its input." >&2
  echo "       A 'binary file matches' line is a text file with a broken encoding and a dash in it." >&2
  exit 1
}

if [ "${1:-}" = "--stdin" ]; then
  LABEL="${2:-stdin}"
  cat > "$STDINBUF"
  if [ ! -s "$STDINBUF" ]; then
    echo "ERROR: check-no-emdash - nothing arrived on stdin for ${LABEL}." >&2
    exit 1
  fi
  HITS=$(grep -nP -e "$PATTERN" -- "$STDINBUF" 2>> "$ERRLOG" || true)
  refuse_if_incomplete
  if [ -n "$HITS" ]; then
    fail_with_hits "$LABEL" "$HITS"
  fi
  echo "check-no-emdash: OK (no em or en dashes in ${LABEL})"
  exit 0
fi

cd "$(git rev-parse --show-toplevel)"

git ls-files -z > "$FILELIST"
if [ ! -s "$FILELIST" ]; then
  echo "ERROR: check-no-emdash - no tracked files to scan." >&2
  exit 1
fi

HITS=$(xargs -0 -r grep -H -nP -e "$PATTERN" -- < "$FILELIST" 2>> "$ERRLOG" || true)
refuse_if_incomplete
if [ -n "$HITS" ]; then
  fail_with_hits "the tracked files listed above" "$HITS"
fi

echo "check-no-emdash: OK (no em or en dashes in the tracked files)"
