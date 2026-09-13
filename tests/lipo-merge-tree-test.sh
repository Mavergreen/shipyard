#!/bin/sh
#   usage: lipo-merge-tree-test.sh
#          Two builds of one thing differing ONLY by architecture must merge into one universal tree;
#          anything else differing must be refused unless the caller declared that path.
# platform: the merge logic is arch-agnostic, so this needs any two architectures the box can
#           compile -- but requiring i386, which only a 10.9 box can build, made this exit 77 on
#           macos-26, leaving the script that assembles BOTH shipped artifacts untested on the only
#           machine that ever runs it for real. So: x86_64 plus whichever second arch this box has --
#           i386 on 10.9, arm64 on Apple Silicon.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/lipo-merge-tree.sh"
command -v clang >/dev/null 2>&1 || { echo "SKIP: no clang"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/lipo-merge-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
printf 'int main(void){return 0;}\n' > "$w/m.c"
clang -arch x86_64 -o "$w/m-x86_64" "$w/m.c" 2>/dev/null || { echo "SKIP: cannot build x86_64 here"; exit 77; }
ALT=""
for a in i386 arm64; do
  if clang -arch "$a" -o "$w/m-alt" "$w/m.c" 2>/dev/null; then ALT="$a"; break; fi
done
[ -n "$ALT" ] || { echo "SKIP: this box can build neither i386 nor arm64 alongside x86_64"; exit 77; }
echo "lipo-merge-tree: merging x86_64 + $ALT"
clang -arch x86_64h -o "$w/m-x86_64h" "$w/m.c" 2>/dev/null || true  # x86_64h is optional for this test

mk() {  # $1 = tree  $2 = the Mach-O to put at bin/tool
  mkdir -p "$1/bin" "$1/share/x" "$1/App.app/Contents"
  cp "$2" "$1/bin/tool"
  echo same > "$1/share/x/data.txt"
  ln -s tool "$1/bin/tool-link"
}
mk "$w/a" "$w/m-x86_64"; mk "$w/b" "$w/m-alt"
echo a > "$w/a/App.app/Contents/Info.plist"; echo b > "$w/b/App.app/Contents/Info.plist"

if sh "$S" --a "$w/a" --b "$w/b" --out "$w/o1" >/dev/null 2>&1; then
  echo "FAIL: an undeclared difference in a non-Mach-O file must be refused"; exit 1
fi
sh "$S" --a "$w/a" --b "$w/b" --out "$w/o2" --allow-differ App.app/Contents/Info.plist >/dev/null
lipo -info "$w/o2/bin/tool" | grep -q "$ALT" && lipo -info "$w/o2/bin/tool" | grep -q 'x86_64' \
  || { echo "FAIL: bin/tool is not universal: $(lipo -info "$w/o2/bin/tool")"; exit 1; }
[ "$(cat "$w/o2/App.app/Contents/Info.plist")" = a ] || { echo "FAIL: a declared difference must take A's copy"; exit 1; }
[ "$(cat "$w/o2/share/x/data.txt")" = same ] || { echo "FAIL: identical files must be copied"; exit 1; }
[ -L "$w/o2/bin/tool-link" ] || { echo "FAIL: symlinks must stay symlinks"; exit 1; }

mk "$w/c" "$w/m-x86_64"; mk "$w/d" "$w/m-x86_64"
if sh "$S" --a "$w/c" --b "$w/d" --out "$w/o3" --require-archs "$ALT x86_64" >/dev/null 2>&1; then
  echo "FAIL: identical thin x86_64 with --require-archs \"$ALT x86_64\" must be refused"; exit 1
fi
[ ! -d "$w/o3" ] || { echo "FAIL: failed merge must not leave OUT dir"; exit 1; }

sh "$S" --a "$w/a" --b "$w/b" --out "$w/o4" --allow-differ App.app/Contents/Info.plist --require-archs "$ALT x86_64" >/dev/null
lipo -info "$w/o4/bin/tool" | grep -q "$ALT" && lipo -info "$w/o4/bin/tool" | grep -q 'x86_64' \
  || { echo "FAIL: o4/bin/tool is not universal: $(lipo -info "$w/o4/bin/tool")"; exit 1; }

lipo -create "$w/m-alt" "$w/m-x86_64" -output "$w/m-fat"
mk "$w/e" "$w/m-fat"; mk "$w/f" "$w/m-fat"
sh "$S" --a "$w/e" --b "$w/f" --out "$w/o5" --require-archs "$ALT x86_64" >/dev/null \
  || { echo "FAIL: identical fat frameworks must merge"; exit 1; }
lipo -info "$w/o5/bin/tool" | grep -q "$ALT" && lipo -info "$w/o5/bin/tool" | grep -q 'x86_64' \
  || { echo "FAIL: o5/bin/tool is not universal: $(lipo -info "$w/o5/bin/tool")"; exit 1; }

printf 'int main(void){return 1;}\n' > "$w/m2.c"
clang -arch x86_64 -o "$w/m2-x86_64" "$w/m2.c"
mk "$w/g" "$w/m-x86_64"; mk "$w/h" "$w/m2-x86_64"
if sh "$S" --a "$w/g" --b "$w/h" --out "$w/o6" >/dev/null 2>&1; then
  echo "FAIL: different x86_64 files must fail lipo"; exit 1
fi
[ ! -d "$w/o6" ] || { echo "FAIL: failed lipo must not leave OUT dir"; exit 1; }

if [ -f "$w/m-x86_64h" ]; then
  lipo -create "$w/m-alt" "$w/m-x86_64h" -output "$w/m-alt-x86_64h"
  mk "$w/k" "$w/m-alt-x86_64h"; mk "$w/l" "$w/m-alt-x86_64h"
  if sh "$S" --a "$w/k" --b "$w/l" --out "$w/o8" --require-archs "$ALT x86_64" >/dev/null 2>&1; then
    echo "FAIL: $ALT+x86_64h must not satisfy --require-archs \"$ALT x86_64\""; exit 1
  fi
  [ ! -d "$w/o8" ] || { echo "FAIL: failed arch validation must not leave OUT dir"; exit 1; }
fi

mkdir -p "$w/x86_64h-dir"
lipo -create "$w/m-alt" "$w/m-x86_64" -output "$w/x86_64h-dir/fat-binary"
mkdir -p "$w/m-path-a/x86_64h-dir" "$w/m-path-b/x86_64h-dir"
cp "$w/x86_64h-dir/fat-binary" "$w/m-path-a/x86_64h-dir/bin"
cp "$w/x86_64h-dir/fat-binary" "$w/m-path-b/x86_64h-dir/bin"
if sh "$S" --a "$w/m-path-a" --b "$w/m-path-b" --out "$w/o9" --require-archs "$ALT x86_64h" >/dev/null 2>&1; then
  echo "FAIL: x86_64h in path must not satisfy --require-archs for x86_64h architecture"; exit 1
fi
[ ! -d "$w/o9" ] || { echo "FAIL: failed arch validation must not leave OUT dir"; exit 1; }

mk "$w/i" "$w/m-x86_64"; mk "$w/j" "$w/m-alt"; echo extra > "$w/i/share/x/only-in-a"
if sh "$S" --a "$w/i" --b "$w/j" --out "$w/o7" >/dev/null 2>&1; then
  echo "FAIL: a file missing from one tree must be refused"; exit 1
fi

echo "PASS: lipo-merge-tree"
