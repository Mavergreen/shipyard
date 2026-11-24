#!/bin/sh
# platform: host-agnostic
#   usage: previous-release-tag.sh [--tags-file FILE] [--tag-glob PATTERN] [tag-to-exclude] [upstream-glob]
#          Prints the newest existing release tag (<upstream>-mavergreen.N by default), or nothing when
#          there is none. Generated release notes use it as the "changed since" baseline. upstream-glob
#          scopes the search to one upstream line ('1.26.*'); pass the tag being published so a
#          tag-triggered build compares against its PREDECESSOR, not itself. --tag-glob (same spelling
#          assert_appcast_upgradeable.sh uses) replaces the default "*-mavergreen.*" pattern VERBATIM,
#          for a product whose tags are not <upstream>-mavergreen.N (shipyard/magic-trackpad2 tag
#          vX.Y.Z, porthole tags YYYYMMDD.N) -- the two are mutually exclusive. --tags-file reads the
#          tags, one per line, from FILE in place of git tag --list, for a caller with no checkout.
# spec: scripts/lib/vercmp.sh "numeric()" -- ver_cmp/comparison_key are the one comparator this and
#       gen_appcast.sh both use, so "which tag is highest" cannot drift between them.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # numeric(), ver_cmp(), comparison_key()

pattern=""; tag_glob=no; tags_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tags-file) tags_file="${2:?previous-release-tag: --tags-file needs a file}"; shift 2 ;;
    --tag-glob) pattern="${2:?previous-release-tag: --tag-glob needs a pattern}"; tag_glob=yes; shift 2 ;;
    -*) echo "previous-release-tag: unknown argument: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

exclude="${1:-}"
if [ -z "$pattern" ]; then
  pattern="*-mavergreen.*"
  [ -z "${2:-}" ] || pattern="${2}-mavergreen.*"
else
  [ -z "${2:-}" ] || {
    echo "previous-release-tag: --tag-glob and a positional upstream-glob are mutually exclusive" >&2
    exit 2
  }
fi

best_tag=""; best_key=""
list_tags() {
  if [ -z "$tags_file" ]; then git tag --list "$pattern"; return; fi
  while IFS= read -r _lt || [ -n "$_lt" ]; do
    case "$_lt" in $pattern) printf '%s\n' "$_lt" ;; esac
  done < "$tags_file"
}
for t in $(list_tags); do
  [ "$t" = "$exclude" ] && continue
  # spec: tests/previous-release-tag-test.sh "v-collision" -- a leading "v" is stripped ONLY under
  #       --tag-glob; stripping it unconditionally would let a stray v-prefixed tag collide with the
  #       real -mavergreen.N tag it sits beside.
  if [ "$tag_glob" = yes ]; then k="$(comparison_key "${t#v}")"; else k="$(comparison_key "$t")"; fi
  numeric "$k" || continue
  if [ -z "$best_key" ] || [ "$(ver_cmp "$k" "$best_key")" = 1 ]; then best_key="$k"; best_tag="$t"; fi
done

[ -z "$best_tag" ] || printf '%s\n' "$best_tag"
