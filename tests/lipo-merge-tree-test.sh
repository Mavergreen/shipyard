#!/bin/sh
# platform: host-agnostic
#   usage: lipo-merge-tree-test.sh
#          Two builds of one thing differing ONLY by architecture must merge into one universal tree;
#          anything else differing must be refused unless the caller declared that path.
# platform: the merge logic is arch-agnostic, so the second arch is an i386 object, the one every
#           host's clang22 builds (10.9's native clang22 targets x86_64 only and links no i386).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/lipo-merge-tree.sh"
CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/..")"
LIPO="$CL/bin/llvm-lipo"; export LIPO
S9="$(sh "$here/../scripts/fetch_sdk.sh")"
w="$(mktemp -d "${TMPDIR:-/tmp}/lipo-merge-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
build() {  # $1 = target triple  $2 = sysroot  then clang arguments
  _t="$1"; _r="$2"; shift 2
  "$CL/bin/clang" --no-default-config -Wno-unused-command-line-argument -fuse-ld=lld --ld-path="$CL/bin/ld64.lld" -target "$_t" -isysroot "$_r" "$@"
}
printf 'int main(void){return 0;}\n' > "$w/m.c"
build x86_64-apple-macos10.9 "$S9" -o "$w/m-x86_64" "$w/m.c" 2>/dev/null || { echo "SKIP: cannot build x86_64 here"; exit 77; }
ALT=i386
build i386-apple-macos10.9 "$S9" -c -o "$w/m-alt" "$w/m.c" || { echo "FAIL: the pinned clang22 cannot build an i386 object"; exit 1; }
build x86_64h-apple-macos10.9 "$S9" -c -o "$w/m-x86_64h" "$w/m.c" 2>/dev/null || true  # x86_64h is optional for this test; as an object, since lld links it as plain x86_64

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
"$LIPO" -info "$w/o2/bin/tool" | grep -q "$ALT" && "$LIPO" -info "$w/o2/bin/tool" | grep -q 'x86_64' \
  || { echo "FAIL: bin/tool is not universal: $("$LIPO" -info "$w/o2/bin/tool")"; exit 1; }
[ "$(cat "$w/o2/App.app/Contents/Info.plist")" = a ] || { echo "FAIL: a declared difference must take A's copy"; exit 1; }
[ "$(cat "$w/o2/share/x/data.txt")" = same ] || { echo "FAIL: identical files must be copied"; exit 1; }
[ -L "$w/o2/bin/tool-link" ] || { echo "FAIL: symlinks must stay symlinks"; exit 1; }

mk "$w/c" "$w/m-x86_64"; mk "$w/d" "$w/m-x86_64"
if sh "$S" --a "$w/c" --b "$w/d" --out "$w/o3" --require-archs "$ALT x86_64" >/dev/null 2>&1; then
  echo "FAIL: identical thin x86_64 with --require-archs \"$ALT x86_64\" must be refused"; exit 1
fi
[ ! -d "$w/o3" ] || { echo "FAIL: failed merge must not leave OUT dir"; exit 1; }

sh "$S" --a "$w/a" --b "$w/b" --out "$w/o4" --allow-differ App.app/Contents/Info.plist --require-archs "$ALT x86_64" >/dev/null
"$LIPO" -info "$w/o4/bin/tool" | grep -q "$ALT" && "$LIPO" -info "$w/o4/bin/tool" | grep -q 'x86_64' \
  || { echo "FAIL: o4/bin/tool is not universal: $("$LIPO" -info "$w/o4/bin/tool")"; exit 1; }

"$LIPO" -create "$w/m-alt" "$w/m-x86_64" -output "$w/m-fat"
mk "$w/e" "$w/m-fat"; mk "$w/f" "$w/m-fat"
sh "$S" --a "$w/e" --b "$w/f" --out "$w/o5" --require-archs "$ALT x86_64" >/dev/null \
  || { echo "FAIL: identical fat frameworks must merge"; exit 1; }
"$LIPO" -info "$w/o5/bin/tool" | grep -q "$ALT" && "$LIPO" -info "$w/o5/bin/tool" | grep -q 'x86_64' \
  || { echo "FAIL: o5/bin/tool is not universal: $("$LIPO" -info "$w/o5/bin/tool")"; exit 1; }

printf 'int main(void){return 1;}\n' > "$w/m2.c"
build x86_64-apple-macos10.9 "$S9" -o "$w/m2-x86_64" "$w/m2.c"
mk "$w/g" "$w/m-x86_64"; mk "$w/h" "$w/m2-x86_64"
if sh "$S" --a "$w/g" --b "$w/h" --out "$w/o6" >/dev/null 2>&1; then
  echo "FAIL: different x86_64 files must fail lipo"; exit 1
fi
[ ! -d "$w/o6" ] || { echo "FAIL: failed lipo must not leave OUT dir"; exit 1; }

if [ -f "$w/m-x86_64h" ]; then
  "$LIPO" -create "$w/m-alt" "$w/m-x86_64h" -output "$w/m-alt-x86_64h"
  mk "$w/k" "$w/m-alt-x86_64h"; mk "$w/l" "$w/m-alt-x86_64h"
  if sh "$S" --a "$w/k" --b "$w/l" --out "$w/o8" --require-archs "$ALT x86_64" >/dev/null 2>&1; then
    echo "FAIL: $ALT+x86_64h must not satisfy --require-archs \"$ALT x86_64\""; exit 1
  fi
  [ ! -d "$w/o8" ] || { echo "FAIL: failed arch validation must not leave OUT dir"; exit 1; }
fi

mkdir -p "$w/x86_64h-dir"
"$LIPO" -create "$w/m-alt" "$w/m-x86_64" -output "$w/x86_64h-dir/fat-binary"
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

repo="$w/repo"; mkdir -p "$repo/.mavergreen/products/w"
union() { printf '%s\n' "$@" > "$repo/.mavergreen/products/w/union"; }
um() {
  mkdir -p "$1/bin" "$1/lib"
  echo same > "$1/bin/tool"
}
uerr="$w/uerr"

um "$w/ua"; um "$w/ub"
echo llvm > "$w/ub/lib/libLLVMAArch64Foo.a"; chmod 640 "$w/ub/lib/libLLVMAArch64Foo.a"
union 'lib/libLLVMAArch64*'
MAVERGREEN_REPO_ROOT="$repo" sh "$S" --a "$w/ua" --b "$w/ub" --out "$w/uo1" --short w >/dev/null 2>&1 \
  || { echo "FAIL: a B-only file matching a union glob must merge"; exit 1; }
cmp -s "$w/ub/lib/libLLVMAArch64Foo.a" "$w/uo1/lib/libLLVMAArch64Foo.a" || { echo "FAIL: the union file is not byte-identical"; exit 1; }
[ "$(ls -l "$w/uo1/lib/libLLVMAArch64Foo.a" | cut -c1-10)" = "$(ls -l "$w/ub/lib/libLLVMAArch64Foo.a" | cut -c1-10)" ] \
  || { echo "FAIL: the union file lost its mode"; exit 1; }

um "$w/uc"; um "$w/ud"; mkdir -p "$w/ud/share"; echo x > "$w/ud/share/extra.txt"
union 'lib/libLLVMAArch64*'
if MAVERGREEN_REPO_ROOT="$repo" sh "$S" --a "$w/uc" --b "$w/ud" --out "$w/uo2" --short w >/dev/null 2>"$uerr"; then
  echo "FAIL: an undeclared one-sided file must be refused"; exit 1
fi
grep -q '^arch-union:' "$uerr" && grep -q 'share/extra.txt' "$uerr" || { echo "FAIL: arch-union must name share/extra.txt: $(cat "$uerr")"; exit 1; }
[ ! -e "$w/uo2" ] || { echo "FAIL: a refused union merge must not leave OUT"; exit 1; }

um "$w/ue"; um "$w/uf"
union 'include/arm_*'
if MAVERGREEN_REPO_ROOT="$repo" sh "$S" --a "$w/ue" --b "$w/uf" --out "$w/uo3" --short w >/dev/null 2>"$uerr"; then
  echo "FAIL: a union glob that matches nothing must be refused"; exit 1
fi
grep -q 'include/arm_\*' "$uerr" || { echo "FAIL: arch-union must name the glob: $(cat "$uerr")"; exit 1; }
[ ! -e "$w/uo3" ] || { echo "FAIL: a refused union merge must not leave OUT"; exit 1; }

um "$w/ug"; um "$w/uh"; ln -s libLLVMAArch64Foo.a "$w/uh/lib/libLLVMAArch64Link.a"
union 'lib/libLLVMAArch64*'
MAVERGREEN_REPO_ROOT="$repo" sh "$S" --a "$w/ug" --b "$w/uh" --out "$w/uo4" --short w >/dev/null 2>&1 \
  || { echo "FAIL: a B-only symlink matching a union glob must merge"; exit 1; }
[ -L "$w/uo4/lib/libLLVMAArch64Link.a" ] || { echo "FAIL: the union symlink must stay a link"; exit 1; }

um "$w/ui"; um "$w/uj"; mkdir "$w/uj/lib/emptydir"
union 'lib/other*'
if MAVERGREEN_REPO_ROOT="$repo" sh "$S" --a "$w/ui" --b "$w/uj" --out "$w/uo5" --short w >/dev/null 2>"$uerr"; then
  echo "FAIL: an undeclared one-sided empty directory must be refused"; exit 1
fi
grep -q 'lib/emptydir' "$uerr" || { echo "FAIL: arch-union must name lib/emptydir: $(cat "$uerr")"; exit 1; }

um "$w/uk"; um "$w/ul"; mkdir "$w/uk/lib/emptydir" "$w/ul/lib/emptydir"
sh "$S" --a "$w/uk" --b "$w/ul" --out "$w/uo6" >/dev/null 2>&1 || { echo "FAIL: an empty directory on both sides must merge"; exit 1; }
[ -d "$w/uo6/lib/emptydir" ] || { echo "FAIL: the shared empty directory is missing from OUT"; exit 1; }

um "$w/um1"; um "$w/um2"; echo x > "$w/um1/lib/only-a"
if sh "$S" --a "$w/um1" --b "$w/um2" --out "$w/uo7" >/dev/null 2>"$uerr"; then
  echo "FAIL: an A-only file with no --short must be refused"; exit 1
fi
grep -q 'lib/only-a' "$uerr" || { echo "FAIL: the refusal must name lib/only-a: $(cat "$uerr")"; exit 1; }

mkdir -p "$w/nr"
printf '#!/bin/sh\nexit 1\n' > "$w/nr/xcrun"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$w/ran" > "$w/nr/lipo"
chmod +x "$w/nr/xcrun" "$w/nr/lipo"
env -u LIPO SHIPYARD_MACHO_DIRS= PATH="$w/nr:/usr/bin:/bin" sh "$S" --a "$w/uk" --b "$w/ul" --out "$w/uo8" >/dev/null 2>"$uerr" \
  || { echo "FAIL: trees with no Mach-O must merge with no reader: $(cat "$uerr")"; exit 1; }
mkdir -p "$w/ux/bin" "$w/uy/bin"
printf '\317\372\355\376one' > "$w/ux/bin/m"; printf '\317\372\355\376two' > "$w/uy/bin/m"
set +e
env -u LIPO SHIPYARD_MACHO_DIRS= PATH="$w/nr:/usr/bin:/bin" sh "$S" --a "$w/ux" --b "$w/uy" --out "$w/uo10" >/dev/null 2>"$uerr"
rc=$?
set -e
[ "$rc" -eq 4 ] && grep -q 'LIPO' "$uerr" || { echo "FAIL: Mach-O with no reader must exit 4 naming LIPO (rc=$rc): $(cat "$uerr")"; exit 1; }
[ ! -e "$w/ran" ] || { echo "FAIL: a bare lipo on PATH was run"; exit 1; }

printf '#!/bin/sh\necho "Non-fat file: $2 is architecture: x86_64 "\n' > "$w/spacelipo"; chmod +x "$w/spacelipo"
um "$w/un"; um "$w/uo"
LIPO="$w/spacelipo" sh "$S" --a "$w/un" --b "$w/uo" --out "$w/uo9" --require-archs x86_64 >/dev/null 2>&1 \
  || { echo "FAIL: has_arch must match x86_64 in -info output that ends in a space"; exit 1; }

mk "$w/ra" "$w/m-x86_64"; mk "$w/rb" "$w/m-alt"
cp "$w/m-x86_64" "$w/ra/bin/a-only"; cp "$w/m-alt" "$w/rb/bin/b-only"
union 'bin/a-only' 'bin/b-only'
MAVERGREEN_REPO_ROOT="$repo" sh "$S" --a "$w/ra" --b "$w/rb" --out "$w/uo11" --short w --require-archs "$ALT x86_64" >/dev/null 2>"$uerr" \
  || { echo "FAIL: --require-archs must judge merged entries only, not union ones: $(cat "$uerr")"; exit 1; }

um "$w/uq"; um "$w/ur"; echo x > "$w/uq/lib/node"; mkdir -p "$w/ur/lib/node"; echo y > "$w/ur/lib/node/f"
union 'lib/node/*' 'lib/node'
if MAVERGREEN_REPO_ROOT="$repo" sh "$S" --a "$w/uq" --b "$w/ur" --out "$w/uo12" --short w >/dev/null 2>"$uerr"; then
  echo "FAIL: a file against a populated directory must be refused"; exit 1
fi
grep -q 'lib/node ' "$uerr" || { echo "FAIL: the refusal must name lib/node: $(cat "$uerr")"; exit 1; }

um "$w/us"; um "$w/ut"; mkdir "$w/us/lib/d"; mkdir "$w/ut/lib/d"; echo y > "$w/ut/lib/d/f"
union 'lib/d/*'
MAVERGREEN_REPO_ROOT="$repo" sh "$S" --a "$w/us" --b "$w/ut" --out "$w/uo13" --short w >/dev/null 2>&1 \
  || { echo "FAIL: an empty directory against a populated one must merge"; exit 1; }
[ "$(cat "$w/uo13/lib/d/f")" = y ] || { echo "FAIL: the populated side's file is missing from OUT"; exit 1; }

echo "PASS: lipo-merge-tree"
