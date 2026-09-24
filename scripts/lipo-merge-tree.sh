#!/bin/sh
# platform: macOS-only -- lipo merges the two trees
#   usage: lipo-merge-tree.sh --a DIR --b DIR --out DIR [--allow-differ RELPATH]... [--require-archs "ARCH ..."]
#          Merges two single-arch builds of the same thing into one universal tree -- shipyard's CMake
#          (x86_64/10.9 + arm64/11.0) and its updater app. Identical files are copied; files Mach-O in
#          both that differ are lipo -create'd; a non-Mach-O difference is refused unless declared
#          with --allow-differ, in which case A's copy wins; a file in only one tree is refused.
#          Anything else differing means these are not two slices of one build. --require-archs takes
#          a space-separated architecture list every regular Mach-O file in the output must carry; a
#          file lacking one is refused and OUT is removed.
# platform: a slice's minimum OS is per-arch -- arm64 has no 10.9 -- so the two slices are two
#           builds, and this is where they become one.
set -eu
A=""; B=""; OUT=""; ALLOW=""; ARCHS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --a) A="${2%/}"; shift 2;;
    --b) B="${2%/}"; shift 2;;
    --out) OUT="${2%/}"; shift 2;;
    --allow-differ) ALLOW="$ALLOW
$2"; shift 2;;
    --require-archs) ARCHS="$2"; shift 2;;
    *) echo "lipo-merge-tree: unknown option $1" >&2; exit 2;;
  esac
done
[ -d "$A" ] && [ -d "$B" ] && [ -n "$OUT" ] || { echo "lipo-merge-tree: need --a DIR --b DIR --out DIR" >&2; exit 2; }
[ ! -e "$OUT" ] || { echo "lipo-merge-tree: $OUT already exists" >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/lipo-merge-tree.XXXXXX")"
trap 'rm -rf "$work" "$OUT"' EXIT

is_macho() { lipo -info "$1" >/dev/null 2>&1; }
allowed() { printf '%s\n' "$ALLOW" | grep -Fqx -- "$1"; }
# platform: lipo -info includes the PATH ("Non-fat file: path/to/bin/tool is architecture: x86_64",
#           "Architectures in the fat file: path/to/bin/tool are: i386 x86_64"), so match exact
#           space-delimited tokens from the arch list after the last ": " and never the file path.
has_arch() {
  archs="$(lipo -info "$1" 2>/dev/null | sed 's/.*: //')"
  case " $archs " in *" $2 "*) return 0;; esac; return 1
}

( cd "$A" && find . \( -type f -o -type l \) | sort ) > "$work/lmt-a"
( cd "$B" && find . \( -type f -o -type l \) | sort ) > "$work/lmt-b"
if ! cmp -s "$work/lmt-a" "$work/lmt-b"; then
  echo "lipo-merge-tree: the trees do not hold the same files:" >&2
  diff "$work/lmt-a" "$work/lmt-b" >&2 || true
  exit 1
fi

COPYFILE_DISABLE=1 cp -R "$A" "$OUT"
bad=0
while IFS= read -r rel; do
  rel="${rel#./}"; fa="$A/$rel"; fb="$B/$rel"; fo="$OUT/$rel"
  if [ -L "$fa" ]; then
    [ "$(readlink "$fa")" = "$(readlink "$fb")" ] \
      || { echo "lipo-merge-tree: symlink $rel differs between trees" >&2; bad=1; }
    continue
  fi
  cmp -s "$fa" "$fb" && continue
  if is_macho "$fa" && is_macho "$fb"; then
    rm -f "$fo"; lipo -create "$fa" "$fb" -output "$fo"
  elif allowed "$rel"; then
    echo "lipo-merge-tree: $rel differs (declared); keeping the --a copy" >&2
  else
    echo "lipo-merge-tree: $rel differs and is not Mach-O; refusing (declare it with --allow-differ if that is expected)" >&2
    bad=1
  fi
done < "$work/lmt-a"
[ "$bad" -eq 0 ] || exit 1

if [ -n "$ARCHS" ]; then
  while IFS= read -r rel; do
    rel="${rel#./}"; fo="$OUT/$rel"
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
