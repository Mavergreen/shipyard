#!/bin/sh
# platform: host-agnostic
#   usage: check-release-notes.sh <file> <version> --short <short> --tag <tag>
#          Is this file the family's release body for this exact version? Used twice: release-notes.sh
#          self-checks what it just generated, and publish-release.yml checks what it is about to
#          publish -- so a repo that regresses to a hand-rolled body still cannot ship one.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Release notes" --
#       the shape is small on purpose (it has to pass for every product, from a Go toolchain to a
#       kext), so it asserts only what a reader is entitled to: the release says which version it is,
#       and says what changed. Six products once published "Automated release for Mac OS X 10.9
#       (Mavericks)." as their entire notes, for every release including Renovate-driven repackages
#       whose only reason to exist was an ingredient bump; that body passes no check here.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/lib.sh"
chk_ran notes-shape
usage() { echo "usage: check-release-notes.sh <file> <version> --short <short> --tag <tag>" >&2; exit 2; }
[ $# -ge 2 ] || usage
f="$1"; ver="$2"; shift 2
short=""; tag=""
while [ $# -gt 0 ]; do
  case "$1" in
    --short) [ $# -ge 2 ] || usage; short="$2"; shift 2 ;;
    --tag) [ $# -ge 2 ] || usage; tag="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$short" ] && [ -n "$tag" ] && [ -n "$ver" ] || usage

fail() {  # $1 = what is wrong, $2 = the fix (default: regenerate)
  chk_fail notes-shape "the release body is not the family shape" "$1" \
    "${2:-generate the body with release-notes.sh and publish exactly that file}"
  exit 1
}

[ -f "$f" ] || fail "no such file: $f"
[ -s "$f" ] || fail "$f is empty; a release body must say something"
[ -n "$(tr -d '[:space:]' < "$f")" ] || fail "$f is empty apart from whitespace"

awk '{ l = $0; sub(/\r$/, "", l); sub(/[ \t]+$/, "", l); if (l == "<!-- edited by a human -->") f = 1 } END { exit !f }' "$f" \
  && fail "$f still carries the human-edit mark '<!-- edited by a human -->'; release-notes.sh strips it, so this body was not composed by release-notes.sh"

want="$(mavergreen_name notes-heading "$short" "$ver" 2>&1)" \
  || fail "cannot derive the heading for $short: $want" "write .mavergreen/products/$short/noun"
first="$(sed -n '1p' "$f")"
[ "$first" = "$want" ] \
  || fail "the first line of $f is not the derived heading '$want': $first" \
          "generate the body with release-notes.sh; the heading is derived from .mavergreen/products/$short/noun"
second="$(sed -n '2p' "$f")"
case "$second" in
  "Release $tag") ;;
  "Release $tag · Requires Mac OS X "*" or later")
    floor="${second#"Release $tag · Requires Mac OS X "}"; floor="${floor% or later}"
    case "$floor" in ''|*[!0-9.]*) fail "the second line of $f has no install floor: $second" ;; esac ;;
  *) fail "the second line of $f is not 'Release $tag' (optionally with ' · Requires Mac OS X <x> or later'): $second" ;;
esac

grep -q '^### What changed[[:space:]]*$' "$f" \
  || fail "$f has no '### What changed' section; every release says what changed, even a repackage"

# spec: tests/check-release-notes-test.sh -- a heading with nothing under it is worse than no
#       heading: it promises a section and delivers none. The '## ' title line is not itself a
#       section requiring a body (validated separately above), so it only resets tracking; '### '
#       subsections are what must have non-blank content before the next heading, a '---' rule, or
#       end of file.
t="$(mktemp "${TMPDIR:-/tmp}/crn.XXXXXX")"
trap 'rm -f "$t"' EXIT
awk '
  /^### / {
    if (head != "" && body == 0) { print head; exit 1 }
    head = $0; body = 0; next
  }
  /^##[^#]/ { if (head != "" && body == 0) { print head; exit 1 } head = ""; body = 0; next }
  /^---[[:space:]]*$/ { if (head != "" && body == 0) { print head; exit 1 } head = ""; body = 0; next }
  /[^[:space:]]/ { body = 1 }
  END { if (head != "" && body == 0) { print head; exit 1 } }
' "$f" > "$t" || {
  empty="$(cat "$t" 2>/dev/null || true)"
  fail "section is empty: ${empty:-<unknown>}"
}

echo "check-release-notes: ok — $f is the family shape for $ver"
