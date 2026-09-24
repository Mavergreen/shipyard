#!/bin/sh
# platform: host-agnostic
#   usage: patch-notes.sh <prev-tag> [exclude-path[:KEY]...]
#          Describes which of OUR modifications to the upstream source changed between the previous
#          release and HEAD, as a markdown section for the release notes (the same register as
#          ingredient-notes.sh's "### Build ingredients"). A modification is any *.patch or *.diff at
#          any depth, or anything under a directory named patches/ or overlays/ at any depth
#          (golang/openssh/swift-runtime's root patches/, container-tools'
#          components/boot2docker/patches/, tailscale's overlays/) -- except release-notes/, which
#          is hand-written prose. An exclude-path (an ingredient pin, in ingredient-pins.sh's
#          "path" or "path:KEY" form) is left out, since ingredient-notes.sh already reports it.
#          Prints NOTHING when nothing matched or there is no previous release, so callers append
#          unconditionally. Exits non-zero when git cannot diff against <prev-tag>: an empty answer
#          must always mean "no change", never "could not tell".
# spec: tests/patch-notes-test.sh
set -eu

prev="${1:-}"
[ -n "$prev" ] || exit 0
shift

tmp="$(mktemp -d "${TMPDIR:-/tmp}/patch-notes.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
TAB="$(printf '\t')"

: > "$tmp/exclude"
for arg in "$@"; do
  printf '%s\n' "${arg%%:*}" >> "$tmp/exclude"
done

# platform: -M so a rename reads as one rename, not a removal plus an addition, whatever the
#           caller's diff.renames says; core.quotePath=false so a path is compared as written.
git -c core.quotePath=false diff --no-ext-diff --name-status -M "$prev" HEAD -- > "$tmp/diff" || {
  echo "patch-notes: git diff against $prev failed; cannot say whether our patches changed" >&2
  exit 1
}

is_ours() {
  case "$1" in
    release-notes/*) return 1 ;;
  esac
  grep -Fqx -- "$1" "$tmp/exclude" && return 1
  case "$1" in
    *.patch|*.diff) return 0 ;;
    patches/*|*/patches/*|overlays/*|*/overlays/*) return 0 ;;
  esac
  return 1
}

: > "$tmp/lines"
while IFS="$TAB" read -r st a b; do
  case "$st" in
    R*)
      is_ours "$a" || is_ours "$b" || continue
      printf '%s\t- Renamed `%s` to `%s`\n' "$a" "$a" "$b" >> "$tmp/lines" ;;
    C*)
      is_ours "$b" || continue
      printf '%s\t- Added `%s`\n' "$b" "$b" >> "$tmp/lines" ;;
    A)
      is_ours "$a" || continue
      printf '%s\t- Added `%s`\n' "$a" "$a" >> "$tmp/lines" ;;
    D)
      is_ours "$a" || continue
      printf '%s\t- Removed `%s`\n' "$a" "$a" >> "$tmp/lines" ;;
    *)
      is_ours "$a" || continue
      printf '%s\t- Changed `%s`\n' "$a" "$a" >> "$tmp/lines" ;;
  esac
done < "$tmp/diff"

if [ -s "$tmp/lines" ]; then
  printf '### Our patches\n\nChanged since %s:\n\n' "$prev"
  LC_ALL=C sort -t "$TAB" -k1,1 "$tmp/lines" | cut -f2-
fi
