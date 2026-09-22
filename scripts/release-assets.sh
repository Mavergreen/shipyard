#!/bin/sh
#   usage: release-assets.sh <dir> [notes-name]
#          Prints the release assets in a downloaded artifact directory, one per line: everything
#          except the notes file and any pre-existing SHA256SUMS (the publish workflow regenerates
#          that).
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Publishing a
#       release" -- an empty Release body is not a degraded release, it is the defect this refuses to
#       publish: tailscale shipped one on every release, swift-runtime set no body at all.
set -eu
dir="${1:?release-assets: directory required}"
notes="${2:-RELEASE_NOTES.md}"

[ -d "$dir" ] || { echo "release-assets: no such directory: $dir" >&2; exit 1; }
[ -f "$dir/$notes" ] || { echo "release-assets: $notes missing from $dir -- the release would have an empty body" >&2; exit 1; }
[ -s "$dir/$notes" ] || { echo "release-assets: $notes is empty -- the release would have an empty body" >&2; exit 1; }

found=0
for f in "$dir"/*; do
  [ -f "$f" ] || continue
  b="${f##*/}"
  case "$b" in
    "$notes"|SHA256SUMS) continue ;;
  esac
  printf '%s\n' "$f"
  found=1
done
[ "$found" -eq 1 ] || { echo "release-assets: no assets in $dir (only $notes) -- nothing to publish" >&2; exit 1; }
