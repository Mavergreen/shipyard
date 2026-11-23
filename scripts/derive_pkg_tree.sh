#!/bin/sh
# platform: host-agnostic -- plain sh, cp -R, rmdir and find; runs on Linux, 10.9 and modern macOS
#   usage: derive_pkg_tree.sh [--requires SHORT[>=FLOOR]]... [--pkg-only SRC=DEST]...
#                             STANDALONE_TREE BUNDLED_LIST OUT_TREE
#          The pkg's product tree, derived from the standalone archive's: a copy of STANDALONE_TREE
#          without the requirements the archive bundles, plus the paths only the pkg carries.
#          BUNDLED_LIST has one "SHORT PATH" line per bundled requirement: the product's short name and
#          its directory relative to the tree. Each SHORT must be one of the --requires, the product's
#          declared requires as stage_product.sh takes them (read by scripts/lib/requires.sh), since the
#          pkg installs SHORT's product instead of carrying it. Each --pkg-only copies SRC to DEST,
#          relative to OUT_TREE, where the tree has nothing (an uninstall hook naming the install
#          location has no place in a relocatable archive). A directory the removals leave empty goes
#          too. Nothing else changes. OUT_TREE must not exist; a failed run leaves none.
#          Exit 1 when a bundled SHORT is not a declared requires, a bundled PATH is not in
#          STANDALONE_TREE, or a DEST already is; 2 on a usage error, a bad --requires, a bad list line
#          (not two fields, not a short name, an absolute path, or one with a . or .. component), a
#          missing SRC or an existing OUT_TREE.
# spec: tests/derive-pkg-tree-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib/requires.sh"
usage='usage: derive_pkg_tree.sh [--requires SHORT[>=FLOOR]]... [--pkg-only SRC=DEST]... STANDALONE_TREE BUNDLED_LIST OUT_TREE'
die() { echo "derive_pkg_tree: $1" >&2; exit "$2"; }
good_rel() {
  case "$1" in ''|.|..|/*|./*|../*|*/.|*/..|*/./*|*/../*) return 1 ;; esac
}
reqs=" "
nadd=0
while [ $# -gt 0 ]; do
  case "$1" in
    --requires)
      [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }
      s="$(mavergreen_require_short "$2")" || die "--requires '$2' names no product" 2
      reqs="$reqs$s "
      shift 2 ;;
    --pkg-only)
      [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }
      src="${2%%=*}" dest="${2#*=}"
      [ "$src" != "$2" ] || die "--pkg-only takes SRC=DEST, not '$2'" 2
      { [ -e "$src" ] || [ -L "$src" ]; } || die "--pkg-only source '$src' does not exist" 2
      good_rel "$dest" || die "--pkg-only destination '$dest' is not a path inside the tree" 2
      nadd=$((nadd + 1))
      eval "add_src_$nadd=\$src add_dest_$nadd=\$dest"
      shift 2 ;;
    --) shift; break ;;
    -*) echo "$usage" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -eq 3 ] || { echo "$usage" >&2; exit 2; }
SA="${1%/}" LIST="$2" OUT="${3%/}"
[ -d "$SA" ] || die "no standalone tree at $SA" 2
[ -f "$LIST" ] || die "no bundled list at $LIST" 2
{ [ -e "$OUT" ] || [ -L "$OUT" ]; } && die "$OUT already exists" 2

while read -r short path extra || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  { [ -n "${path-}" ] && [ -z "${extra-}" ]; } || die "$LIST: '$short${path:+ $path}${extra:+ $extra}' is not 'SHORT PATH'" 2
  case "$short" in -*|*[!a-z0-9-]*) die "$LIST: '$short' is not a short name" 2 ;; esac
  good_rel "$path" || die "$LIST: $short: '$path' is not a path inside the tree" 2
done < "$LIST"
n=0
while read -r short path || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  case "$reqs" in *" $short "*) ;; *) die "$short: bundled by $LIST, but not among the product's requires (${reqs# })" 1 ;; esac
  { [ -e "$SA/$path" ] || [ -L "$SA/$path" ]; } || die "$short: $path is not in $SA" 1
  n=$((n + 1))
done < "$LIST"

work="$OUT.derive.$$"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"
cp -pRP "$SA/." "$work/"
while read -r short path || [ -n "$short" ]; do
  [ -n "$short" ] || continue
  rm -rf "$work/$path"
  d="$(dirname "$path")"
  while [ "$d" != . ] && rmdir "$work/$d" 2>/dev/null; do d="$(dirname "$d")"; done
done < "$LIST"
i=1
while [ "$i" -le "$nadd" ]; do
  eval "src=\$add_src_$i dest=\$add_dest_$i"
  { [ -e "$work/$dest" ] || [ -L "$work/$dest" ]; } && die "--pkg-only destination $dest is already in $SA" 1
  mkdir -p "$work/$(dirname "$dest")"
  cp -pRP "$src" "$work/$dest"
  i=$((i + 1))
done
mv "$work" "$OUT"
trap - EXIT
echo "derive_pkg_tree: dropped $n bundled requirement(s), added $nadd pkg-only path(s)" >&2
