#!/bin/sh
# platform: host-agnostic
#   usage: assert_sparkle_pristine.sh EMBEDDED PINNED
#          Asserts an updater's embedded Sparkle.framework is the pinned upstream one: the same entries,
#          the same types, the same symlink targets, the same file bytes. Upstream's code signature seals
#          every file, so pristine is what keeps that seal valid -- a flattened symlink or a thinned
#          binary is exactly how it broke. Exit 0 identical, 1 different, 2 on a usage error.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning"
set -eu
[ "$#" -eq 2 ] && [ -d "$1" ] && [ -d "$2" ] || { echo "usage: assert_sparkle_pristine.sh EMBEDDED PINNED (two framework dirs)" >&2; exit 2; }
_tmp="${TMPDIR:-/tmp}"
t="$(mktemp -d "${_tmp%/}/sparkle-pristine.XXXXXX")"; trap 'rm -rf "$t"' EXIT
list() {  # $1 = dir; one line per entry: its type, path, and symlink target
  ( cd "$1" && find . | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then printf 'l %s -> %s\n' "$p" "$(readlink "$p")"
      elif [ -d "$p" ]; then printf 'd %s\n' "$p"
      else printf 'f %s\n' "$p"; fi
    done )
}
list "$1" > "$t/e"; list "$2" > "$t/p"
if ! cmp -s "$t/e" "$t/p"; then
  echo "assert_sparkle_pristine: $1 is not the pinned Sparkle -- entries differ:" >&2
  diff "$t/p" "$t/e" | sed -n '1,10p' | sed 's/^/  /' >&2
  exit 1
fi
bad=0
while read -r ty p; do
  [ "$ty" = f ] || continue
  cmp -s "$1/$p" "$2/$p" || { echo "assert_sparkle_pristine: $p differs from the pinned bytes" >&2; bad=1; }
done < "$t/p"
[ "$bad" -eq 0 ] || exit 1
echo "assert_sparkle_pristine: $1 is the pinned Sparkle"
