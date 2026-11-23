#!/bin/sh
# platform: host-agnostic
#   usage: check-standalone-archive-test.sh
#          scripts/check-standalone-archive.sh: naming, the one top directory, what the package alone
#          carries, scripts and links naming /usr/local/mavergreen, then Mach-O fixtures built at test
#          time with the pinned clang22 and 10.9 SDK: system, @rpath and @loader_path loads pass, an
#          absolute load, rpath or install name outside the system fails, and --run, where this host
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
passes "a data file naming the prefix is not a script"
echo "ok: naming, the top directory, the package's pieces, scripts and links"

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
