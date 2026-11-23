#!/bin/sh
# platform: host-agnostic
#   usage: check-standalone-archive-test.sh
#          scripts/check-standalone-archive.sh: naming, the one top directory, what the package alone
#          carries, scripts, text files and links naming /usr/local/mavergreen, --plist's declared requires
#          against the product's own prefix and undeclared ones, then Mach-O fixtures built at test
#          time with the pinned clang22 and 10.9 SDK: system, @rpath and @loader_path loads pass, an
#          absolute load, rpath or install name outside the system fails (a declared require's too), a
#          string naming the prefix is a warning, and --run, where this host
#          runs x86_64 natively, starts each bin/ entry from a relocated copy. Without clang22: SKIP, exit 77.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
C="$here/../scripts/check-standalone-archive.sh"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/check-standalone.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: check-standalone-archive: $*"; exit 1; }
n=0
mk() {  # $1 = archive name; builds it from $w/t, whose one entry is the archive's top
  n=$((n + 1)); d="$w/a$n"; mkdir "$d"; A="$d/$1"
  (cd "$w/t" && set -- * && COPYFILE_DISABLE=1 tar -czf "$A" "$@") || fail "tar could not build $1"
}
fresh() {  # $1 = top directory
  rm -rf "$w/t"; mkdir -p "$w/t/$1/bin" "$w/t/$1/share/doc"
  printf '#!/bin/sh\necho ok\n' > "$w/t/$1/bin/tool"; chmod 755 "$w/t/$1/bin/tool"
  printf 'doc\n' > "$w/t/$1/share/doc/README"
}
passes() {  # $1 = label
  rc=0; sh "$C" "$A" > "$w/out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || fail "$1: exit $rc, want 0: $(cat "$w/out")"
}
fails() {  # $1 = label, $2 = phrase
  rc=0; sh "$C" "$A" > "$w/out" 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || fail "$1: exit $rc, want 1: $(cat "$w/out")"
  grep -q -- "$2" "$w/out" || fail "$1: should say '$2': $(cat "$w/out")"
}

rc=0; sh "$C" > /dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || fail "no argument: exit $rc, want 2"
fresh w-1.0; mk w-1.0.tar.gz
rc=0; sh "$C" "$A" > /dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || fail "a name without -macos-<arch>.tar.gz: exit $rc, want 2"
fresh w-1.0; mk w-1.0-macos-ppc.tar.gz
rc=0; sh "$C" "$A" > /dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || fail "an arch the family does not ship: exit $rc, want 2"
rc=0; sh "$C" "$w/none-1.0-macos-x86_64.tar.gz" > /dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || fail "a missing archive: exit $rc, want 2"

fresh w-1.0; mk w-1.0-macos-universal.tar.gz; passes "a product tree under <short>-<version>/"
fresh go126-cross-1.26.5-mavericks.5; mk go126-cross-1.26.5-mavericks.5-macos-x86_64.tar.gz
passes "a short name and a version that both carry hyphens"
grep -q 'go126-cross' "$w/out" || fail "the report names the product: $(cat "$w/out")"
fresh w-1.1; mk w-1.0-macos-arm64.tar.gz; fails "a top directory for another version" "w-1.1"
fresh w-1.0; mkdir "$w/t/extra"; printf 'x\n' > "$w/t/extra/f"; mk w-1.0-macos-x86_64.tar.gz
fails "a second top-level entry" "outside w-1.0/"
fresh w-1.0; printf '<plist/>\n' > "$w/t/w-1.0/mavergreen.plist"; mk w-1.0-macos-x86_64.tar.gz
fails "the package's manifest" "mavergreen.plist"
fresh w-1.0; mkdir -p "$w/t/w-1.0/Library/Application Support/Mavergreen/w-updater.app/Contents"
printf 'x\n' > "$w/t/w-1.0/Library/Application Support/Mavergreen/w-updater.app/Contents/Info.plist"; mk w-1.0-macos-x86_64.tar.gz
fails "an updater" "updater"
fresh w-1.0; mkdir -p "$w/t/w-1.0/Library/LaunchAgents"; printf 'x\n' > "$w/t/w-1.0/Library/LaunchAgents/dev.mavergreen.w-updatecheck.plist"
mk w-1.0-macos-x86_64.tar.gz; fails "a LaunchAgent" "LaunchAgents"
fresh w-1.0; printf '#!/bin/sh\n' > "$w/t/w-1.0/postinstall"; mk w-1.0-macos-x86_64.tar.gz
fails "a pkg install script" "install script"
fresh w-1.0; printf 'x\n' > "$w/t/w-1.0/share/._README"; mk w-1.0-macos-x86_64.tar.gz
fails "an AppleDouble entry" "AppleDouble"
fresh w-1.0; printf '#!/usr/local/mavergreen/w/bin/interp\n' > "$w/t/w-1.0/bin/tool"; mk w-1.0-macos-x86_64.tar.gz
fails "a shebang into /usr/local/mavergreen" "bin/tool"
fresh w-1.0; printf '#!/bin/sh\nexec /usr/local/mavergreen/w/libexec/real "$@"\n' > "$w/t/w-1.0/bin/tool"; mk w-1.0-macos-x86_64.tar.gz
fails "a script naming /usr/local/mavergreen" "/usr/local/mavergreen"
fresh w-1.0; ln -s /usr/local/mavergreen/w/bin/tool "$w/t/w-1.0/bin/link"; mk w-1.0-macos-x86_64.tar.gz
fails "a symlink into /usr/local/mavergreen" "bin/link"
fresh w-1.0; ln -s tool "$w/t/w-1.0/bin/link"; ln -s /usr/bin/true "$w/t/w-1.0/bin/sys"; mk w-1.0-macos-x86_64.tar.gz
passes "a relative symlink, and one to the system"
fresh w-1.0; printf 'prefix=/usr/local/mavergreen/w\n' > "$w/t/w-1.0/share/doc/w.pc"; mk w-1.0-macos-x86_64.tar.gz
fails "a text file naming /usr/local/mavergreen" "share/doc/w.pc names /usr/local/mavergreen"
fresh w-1.0; printf 'a\0/usr/local/mavergreen/w/lib\0b' > "$w/t/w-1.0/share/doc/blob.bin"; mk w-1.0-macos-x86_64.tar.gz
passes "a binary file holding the string"
grep -q 'warning: share/doc/blob.bin holds the string /usr/local/mavergreen/w/lib' "$w/out" || fail "a binary file's string is a warning: $(cat "$w/out")"
echo "ok: naming, the top directory, the package's pieces, scripts and links"

plist() {  # $1 = file, then each require
  _f="$1"; shift
  { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>product</key>\n  <string>go126</string>\n'
    if [ $# -gt 0 ]; then
      printf '  <key>requires</key>\n  <array>\n'
      for _r in "$@"; do printf '    <string>%s</string>\n' "$(printf '%s' "$_r" | sed 's/>/\&gt;/g')"; done
      printf '  </array>\n'
    fi
    printf '</dict>\n</plist>\n'; } > "$_f"
}
P="$w/mavergreen.plist"
plist "$P" clang22 'sdk109>=1.0'
with() {  # $1 = expected exit, $2 = label, $3 = phrase (or -)
  rc=0; sh "$C" --plist "$P" "$A" > "$w/out" 2>&1 || rc=$?
  [ "$rc" -eq "$1" ] || fail "$2: --plist: exit $rc, want $1: $(cat "$w/out")"
  [ "$3" = - ] || grep -q -- "$3" "$w/out" || fail "$2: --plist: should say '$3': $(cat "$w/out")"
}
go() {  # $1 = the extra path the wrapper names (or -)
  fresh go126-1.26.5; G="$w/t/go126-1.26.5"
  { printf '#!/bin/sh\nCC=/usr/local/mavergreen/clang22/bin/clang\n'
    printf 'SDKROOT=/usr/local/mavergreen/sdk109/SDKs/MacOSX10.9.sdk\n'
    [ "$1" = - ] || printf 'X=%s\n' "$1"
    printf 'exec "$(dirname "$0")/../libexec/go" "$@"\n'; } > "$G/bin/tool"
}
go -; mk go126-1.26.5-macos-x86_64.tar.gz
with 0 "a wrapper naming its declared requires" "requires clang22 sdk109"
fails "a wrapper naming requires, without --plist" "bin/tool is a script naming /usr/local/mavergreen"
go /usr/local/mavergreen/go126/lib/x; mk go126-1.26.5-macos-x86_64.tar.gz
with 1 "a wrapper naming its own prefix" "bin/tool names /usr/local/mavergreen/go126.*self-reference (relocation bug)"
go /usr/local/mavergreen/zig/bin/zig; mk go126-1.26.5-macos-x86_64.tar.gz
with 1 "a wrapper naming an undeclared product" "bin/tool names /usr/local/mavergreen/zig.*undeclared dependency"
grep -q 'clang22' "$w/out" && fail "a declared require is no finding: $(cat "$w/out")"
go /usr/local/mavergreen/clang22x/bin/cc; mk go126-1.26.5-macos-x86_64.tar.gz
with 1 "a path component that only begins with a require" "/usr/local/mavergreen/clang22x.*undeclared dependency"
go -; printf 'CC=/usr/local/mavergreen/clang22/bin/clang\nGOROOT_FINAL=/opt/go\n' > "$G/go.env"; mk go126-1.26.5-macos-x86_64.tar.gz
with 0 "a text go.env naming a require" -
fails "a text go.env naming a require, without --plist" "go.env names /usr/local/mavergreen"
go -; printf 'GOROOT=/usr/local/mavergreen/go126\n' > "$G/go.env"; mk go126-1.26.5-macos-x86_64.tar.gz
with 1 "a text go.env naming its own prefix" "go.env names /usr/local/mavergreen/go126.*self-reference"
go -; printf 'GOROOT=/usr/local/mavergreen/go126\n' > "$G/go.env"; mk go126-1.26.5-macos-x86_64.tar.gz
plist "$P"; with 1 "a manifest with no requires" "bin/tool names /usr/local/mavergreen/clang22.*undeclared dependency"
printf 'not a plist\n' > "$P"; with 2 "a manifest stevedore cannot read" -
rc=0; sh "$C" --plist "$w/none.plist" "$A" > /dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || fail "a missing manifest: exit $rc, want 2"
rc=0; sh "$C" --plist > /dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || fail "--plist with no path: exit $rc, want 2"
plist "$P" clang22 'sdk109>=1.0'
echo "ok: --plist: scripts and text files may name declared requires, never the product itself"

CL="$(sh "$here/../scripts/fetch_clang22.sh" "$here/../components/clang22" 2>/dev/null)" || { echo "SKIP: no clang22"; exit 77; }
SDK="$(sh "$here/../scripts/fetch_sdk.sh" 2>/dev/null)" || fail "no pinned 10.9 SDK"
OTOOL="$CL/bin/llvm-otool"; LIPO="$CL/bin/llvm-lipo"; NM="$CL/bin/llvm-nm"; export OTOOL LIPO NM
cc() { "$CL/bin/clang" --no-default-config -target x86_64-apple-macos10.9 -isysroot "$SDK" "$@"; }
printf 'int lib(void) { return 0; }\n' > "$w/lib.c"
printf 'int lib(void);\nint main(void) { return lib(); }\n' > "$w/main.c"
macho() {  # $1 = install name of lib/libx.dylib, $2 = the tool's rpath (or -), then extra link args for the tool
  _id="$1"; _rp="$2"; shift 2
  fresh w-1.0; mkdir -p "$w/t/w-1.0/lib"
  cc -dynamiclib -install_name "$_id" "$w/lib.c" -o "$w/t/w-1.0/lib/libx.dylib" || fail "cc could not build libx.dylib"
  if [ "$_rp" = - ]; then set -- "$@"; else set -- -Wl,-rpath,"$_rp" "$@"; fi
  cc "$w/main.c" "$w/t/w-1.0/lib/libx.dylib" -o "$w/t/w-1.0/bin/tool" "$@" || fail "cc could not build the tool"
}
macho @rpath/libx.dylib @loader_path/../lib; mk w-1.0-macos-x86_64.tar.gz
passes "an @rpath install name and an @loader_path rpath"
grep -q 'Mach-O' "$w/out" || fail "the report counts the Mach-O files it read: $(cat "$w/out")"
macho @loader_path/../lib/libx.dylib -; mk w-1.0-macos-x86_64.tar.gz
passes "an @loader_path install name"
macho /usr/local/mavergreen/w/lib/libx.dylib -; mk w-1.0-macos-x86_64.tar.gz
fails "a tool loading from /usr/local/mavergreen" "bin/tool .*loads /usr/local/mavergreen/w/lib/libx.dylib"
grep -q 'lib/libx.dylib .*install name /usr/local/mavergreen/w/lib/libx.dylib' "$w/out" || fail "the install name is its own finding: $(cat "$w/out")"
macho @rpath/libx.dylib /usr/local/mavergreen/w/lib; mk w-1.0-macos-x86_64.tar.gz
fails "an absolute rpath into /usr/local/mavergreen" "rpath /usr/local/mavergreen/w/lib"
macho /opt/w/lib/libx.dylib -; mk w-1.0-macos-x86_64.tar.gz
fails "an absolute non-system load" "loads /opt/w/lib/libx.dylib"
macho /usr/local/mavergreen/clang22/lib/libx.dylib -; mk w-1.0-macos-x86_64.tar.gz
plist "$P" clang22
with 1 "a Mach-O loading from a declared require" "bin/tool .*loads /usr/local/mavergreen/clang22/lib/libx.dylib"
macho @rpath/libx.dylib @loader_path/../lib
printf 'const char *p = "/usr/local/mavergreen/w/share";\nint main(void) { return p[0] == 0; }\n' > "$w/str.c"
cc "$w/str.c" -o "$w/t/w-1.0/bin/str" || fail "cc could not build the tool holding a string"
mk w-1.0-macos-x86_64.tar.gz
passes "a Mach-O holding the string"
grep -q 'warning: bin/str holds the string /usr/local/mavergreen/w/share' "$w/out" || fail "a Mach-O's string is a warning: $(cat "$w/out")"
echo "ok: Mach-O loads, rpaths and install names"

can_run=no
[ "$(uname -s):$(uname -m)" != Darwin:x86_64 ] || can_run=yes
macho @rpath/libx.dylib @loader_path/../lib; mk w-1.0-macos-x86_64.tar.gz
rc=0; sh "$C" --run "$A" > "$w/out" 2>&1 || rc=$?
if [ "$can_run" = yes ]; then
  [ "$rc" -eq 0 ] || fail "--run: a relocatable tool starts: exit $rc: $(cat "$w/out")"
  grep -q 'bin/tool' "$w/out" || fail "--run names each bin/ entry it started: $(cat "$w/out")"
  macho /usr/local/mavergreen/w/lib/libx.dylib -; mk w-1.0-macos-x86_64.tar.gz
  rc=0; sh "$C" --run "$A" > "$w/out" 2>&1 || rc=$?
  [ "$rc" -eq 1 ] || fail "--run: a tool that cannot find its library: exit $rc, want 1: $(cat "$w/out")"
  grep -q 'bin/tool .*did not start' "$w/out" || fail "--run says which tool did not start: $(cat "$w/out")"
  echo "ok: --run starts each bin/ entry from a relocated copy"
else
  [ "$rc" -eq 0 ] || fail "--run on a host that cannot run x86_64: exit $rc: $(cat "$w/out")"
  grep -q 'not run' "$w/out" || fail "--run on a host that cannot run it says so: $(cat "$w/out")"
  echo "ok: --run notes it could not run here"
fi

echo "PASS: check-standalone-archive"
