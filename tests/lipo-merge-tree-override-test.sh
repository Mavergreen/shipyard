#!/bin/sh
# platform: host-agnostic
#   usage: lipo-merge-tree-override-test.sh
#          Every lipo call lipo-merge-tree.sh makes must go through LIPO, so a cross toolchain can
#          supply the Mach-O reader. A stub LIPO answers -info and -create from plain fixture files,
#          so this needs no clang and no real Mach-O, and runs on Linux.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/lipo-merge-tree.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/lipo-merge-override.XXXXXX")"; trap 'rm -rf "$w"' EXIT
export LMT_LOG="$w/lipo.log"
cat > "$w/lipo-stub" <<'STUB'
#!/bin/sh
echo "$*" >> "$LMT_LOG"
archs_of() { head -1 "$1" | sed 's/^MACHO://'; }
case "$1" in
  -info)
    if head -1 "$2" 2>/dev/null | grep -q '^MACHO:'; then
      echo "Architectures in the fat file: $2 are: $(archs_of "$2")"
      exit 0
    fi
    echo "$2 is not a fat file" >&2; exit 1 ;;
  -create)
    printf 'MACHO:%s %s\n' "$(archs_of "$2")" "$(archs_of "$3")" > "$5"
    exit 0 ;;
  *) echo "lipo-stub: unexpected $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$w/lipo-stub"

mk() {  # $1 = tree  $2 = the archs of the fixture Mach-O at bin/tool
  mkdir -p "$1/bin" "$1/share/x" "$1/App.app/Contents"
  printf 'MACHO:%s\n' "$2" > "$1/bin/tool"
  echo same > "$1/share/x/data.txt"
  ln -s tool "$1/bin/tool-link"
}
mk "$w/a" x86_64; mk "$w/b" arm64
echo a > "$w/a/App.app/Contents/Info.plist"; echo b > "$w/b/App.app/Contents/Info.plist"

if LIPO="$w/lipo-stub" sh "$S" --a "$w/a" --b "$w/b" --out "$w/o1" >/dev/null 2>&1; then
  echo "FAIL: an undeclared difference in a non-Mach-O file must be refused"; exit 1
fi

LIPO="$w/lipo-stub" sh "$S" --a "$w/a" --b "$w/b" --out "$w/o2" \
  --allow-differ App.app/Contents/Info.plist --require-archs "arm64 x86_64" >/dev/null \
  || { echo "FAIL: merge through the LIPO override must succeed"; exit 1; }
[ "$(cat "$w/o2/bin/tool")" = "MACHO:x86_64 arm64" ] \
  || { echo "FAIL: bin/tool was not merged through the stub: $(cat "$w/o2/bin/tool")"; exit 1; }
grep -q -- '^-info ' "$LMT_LOG" || { echo "FAIL: -info did not go through LIPO"; exit 1; }
grep -q -- '^-create ' "$LMT_LOG" || { echo "FAIL: -create did not go through LIPO"; exit 1; }

if LIPO="$w/lipo-stub" sh "$S" --a "$w/a" --b "$w/b" --out "$w/o3" \
  --allow-differ App.app/Contents/Info.plist --require-archs "ppc x86_64" >/dev/null 2>&1; then
  echo "FAIL: --require-archs must refuse a missing arch read through LIPO"; exit 1
fi
[ ! -d "$w/o3" ] || { echo "FAIL: failed arch validation must not leave OUT dir"; exit 1; }

echo "PASS: lipo-merge-tree LIPO override"
