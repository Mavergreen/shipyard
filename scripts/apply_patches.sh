#!/bin/sh
# platform: host-agnostic
#   usage: apply_patches.sh SRC PATCHDIR
#          Applies every PATCHDIR/*.patch to SRC in name order, once. SRC/.mavergreen-patches records
#          the SHA-256 of each patch applied: a second run with the same set does nothing, and one
#          with a different set is refused (SRC must be unpacked afresh). Exit 1 names the patch that
#          does not apply.
set -eu
[ "$#" -eq 2 ] || { echo "usage: apply_patches.sh SRC PATCHDIR" >&2; exit 2; }
src="$(cd "$1" && pwd)" && dir="$(cd "$2" && pwd)" || { echo "apply_patches.sh: cannot read $1 or $2" >&2; exit 1; }

[ -r "$dir" ] || { echo "apply_patches.sh: cannot read $dir" >&2; exit 1; }
want="$(cd "$dir" && for p in *.patch; do [ -f "$p" ] && shasum -a 256 "$p"; done; true)" \
  || { echo "apply_patches.sh: cannot read $dir" >&2; exit 1; }
if [ -f "$src/.mavergreen-patches" ]; then
  [ "$(cat "$src/.mavergreen-patches")" = "$want" ] && { echo "patches already applied to $src"; exit 0; }
  echo "apply_patches.sh: $src was patched with a different set than $dir holds; unpack it afresh" >&2
  exit 1
fi
for p in "$dir"/*.patch; do
  [ -f "$p" ] || continue
  echo "applying ${p##*/}"
  (cd "$src" && patch -p1 -F 0 -N -t -s -V none < "$p") \
    || { echo "apply_patches.sh: ${p##*/} does not apply cleanly to $src" >&2; exit 1; }
done
printf '%s\n' "$want" > "$src/.mavergreen-patches"
