#!/bin/sh
# platform: host-agnostic
#   usage: lipo-merge-tree.sh --a DIR --b DIR --out DIR [--short S] [--allow-differ RELPATH]... [--require-archs "ARCH ..."]
#          Merges two single-arch builds of the same thing into one universal tree -- shipyard's CMake
#          (x86_64/10.9 + arm64/11.0) and its updater app. Identical files are copied; files Mach-O in
#          both that differ are lipo -create'd; a non-Mach-O difference is refused unless declared
#          with --allow-differ, in which case A's copy wins. Anything else differing means these are
#          not two slices of one build. A file, symlink or empty directory in only one tree is refused
#          (arch-union), unless --short S names a product whose .mavergreen/products/S/union declares
#          it: each line is a glob over the relative path, the entry is copied into OUT from its own
#          side, and a glob matching no one-sided entry is refused. --require-archs takes a
#          space-separated architecture list every regular Mach-O file in the output must carry; a
#          file lacking one is refused and OUT is removed. The Mach-O reader is LIPO, else LLVM's
#          llvm-lipo as mach_tool finds it; with neither it exits 4.
# platform: a slice's minimum OS is per-arch -- arm64 has no 10.9 -- so the two slices are two
#           builds, and this is where they become one.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
. "$SELF/lib/macho-tools.sh"
LC_ALL=C; export LC_ALL
A=""; B=""; OUT=""; ALLOW=""; ARCHS=""; SHORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --a) A="${2%/}"; shift 2;;
    --b) B="${2%/}"; shift 2;;
    --out) OUT="${2%/}"; shift 2;;
    --short) SHORT="$2"; shift 2;;
    --allow-differ) ALLOW="$ALLOW
$2"; shift 2;;
    --require-archs) ARCHS="$2"; shift 2;;
    *) echo "lipo-merge-tree: unknown option $1" >&2; exit 2;;
  esac
done
[ -d "$A" ] && [ -d "$B" ] && [ -n "$OUT" ] || { echo "lipo-merge-tree: need --a DIR --b DIR --out DIR" >&2; exit 2; }
[ ! -e "$OUT" ] || { echo "lipo-merge-tree: $OUT already exists" >&2; exit 2; }
mach_tool LIPO || exit 4
work="$(mktemp -d "${TMPDIR:-/tmp}/lipo-merge-tree.XXXXXX")"
trap 'rm -rf "$work" "$OUT"' EXIT

is_macho() { "$LIPO" -info "$1" >/dev/null 2>&1; }
allowed() { printf '%s\n' "$ALLOW" | grep -Fqx -- "$1"; }
# platform: lipo -info includes the PATH ("Non-fat file: path/to/bin/tool is architecture: x86_64",
#           "Architectures in the fat file: path/to/bin/tool are: i386 x86_64"), so match exact
#           space-delimited tokens from the arch list after the last ": " and never the file path.
has_arch() {
  archs="$("$LIPO" -info "$1" 2>/dev/null | sed -e 's/.*: //' -e 's/[[:space:]]*$//')"
  case " $archs " in *" $2 "*) return 0;; esac; return 1
}
tree_list() { ( cd "$1" && find . \( -type f -o -type l -o -type d -empty \) | sed -e '/^\.$/d' -e 's|^\./||' | sort ); }
matches_any() { while IFS= read -r _g; do [ -n "$_g" ] || continue; case "$1" in $_g) return 0;; esac; done < "$2"; return 1; }
union_fail() {
  chk_fail arch-union "$1" "$2" \
    "add the path to .mavergreen/products/${SHORT:-<short>}/union if it ships from one arch only, or make both builds produce it; delete a glob that matches nothing"
}

tree_list "$A" > "$work/lmt-a"
tree_list "$B" > "$work/lmt-b"
comm -12 "$work/lmt-a" "$work/lmt-b" > "$work/lmt-both"
comm -23 "$work/lmt-a" "$work/lmt-b" | while IFS= read -r rel; do [ -d "$B/$rel" ] && [ ! -L "$B/$rel" ] || echo "$rel"; done > "$work/lmt-only-a"
comm -13 "$work/lmt-a" "$work/lmt-b" | while IFS= read -r rel; do [ -d "$A/$rel" ] && [ ! -L "$A/$rel" ] || echo "$rel"; done > "$work/lmt-only-b"
cat "$work/lmt-only-a" "$work/lmt-only-b" > "$work/lmt-one"

: > "$work/lmt-globs"
[ -z "$SHORT" ] || mg_lines "products/$SHORT/union" > "$work/lmt-globs" 2>/dev/null || true
bad=0
while IFS= read -r rel; do
  matches_any "$rel" "$work/lmt-globs" && continue
  union_fail "$rel is in only one of the trees and no union glob declares it" "$rel is built on one arch only"
  bad=1
done < "$work/lmt-one"
while IFS= read -r g; do
  [ -n "$g" ] || continue
  printf '%s\n' "$g" > "$work/lmt-g1"
  hit=0
  while IFS= read -r rel; do
    if matches_any "$rel" "$work/lmt-g1"; then hit=1; break; fi
  done < "$work/lmt-one"
  [ "$hit" -eq 1 ] && continue
  union_fail "the union glob $g matches no file in only one of the trees" "a union glob must name a file one build lacks"
  bad=1
done < "$work/lmt-globs"
[ "$bad" -eq 0 ] || exit 1

COPYFILE_DISABLE=1 cp -R "$A" "$OUT"
while IFS= read -r rel; do
  fb="$B/$rel"; fo="$OUT/$rel"
  mkdir -p "$(dirname "$fo")"
  if [ -L "$fb" ]; then ln -s "$(readlink "$fb")" "$fo"
  elif [ -d "$fb" ]; then COPYFILE_DISABLE=1 cp -pR "$fb" "$fo"
  else COPYFILE_DISABLE=1 cp -p "$fb" "$fo"; fi
done < "$work/lmt-only-b"

while IFS= read -r rel; do
  fa="$A/$rel"; fb="$B/$rel"; fo="$OUT/$rel"
  if [ -L "$fa" ]; then
    [ "$(readlink "$fa")" = "$(readlink "$fb")" ] \
      || { echo "lipo-merge-tree: symlink $rel differs between trees" >&2; bad=1; }
    continue
  fi
  [ -d "$fa" ] && [ -d "$fb" ] && continue
  cmp -s "$fa" "$fb" && continue
  if is_macho "$fa" && is_macho "$fb"; then
    rm -f "$fo"; "$LIPO" -create "$fa" "$fb" -output "$fo"
  elif allowed "$rel"; then
    echo "lipo-merge-tree: $rel differs (declared); keeping the --a copy" >&2
  else
    echo "lipo-merge-tree: $rel differs and is not Mach-O; refusing (declare it with --allow-differ if that is expected)" >&2
    bad=1
  fi
done < "$work/lmt-both"
[ "$bad" -eq 0 ] || exit 1

if [ -n "$ARCHS" ]; then
  while IFS= read -r rel; do
    fo="$OUT/$rel"
    [ -L "$fo" ] && continue  # skip symlinks
    [ -f "$fo" ] || continue  # skip directories
    is_macho "$fo" || continue  # skip non-Mach-O files
    for arch in $ARCHS; do
      if ! has_arch "$fo" "$arch"; then
        echo "lipo-merge-tree: $rel is missing arch $arch" >&2
        exit 1
      fi
    done
  done < "$work/lmt-a"
fi

trap 'rm -rf "$work"' EXIT
echo "lipo-merge-tree: $A + $B -> $OUT" >&2
