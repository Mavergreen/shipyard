#!/bin/sh
# platform: host-agnostic
#   usage: build-universal-test.sh
#          build_universal.sh builds a fixture C project's x86_64 (10.9) and arm64 (11.0) slices and
#          merges them: a fat executable, one copy of an identical data file, usage errors that exit 2,
#          an existing --out refused, and a data file that differs between arches refused by name with
#          no --out left. Linux only; fetches clang22 and both SDKs over the network.
set -eu
[ "$(uname -s)" = Linux ] || { echo 'SKIP: build_universal needs a Linux host'; exit 77; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/scripts/build_universal.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/build-universal.XXXXXX")"; trap 'rm -rf "$T"' EXIT
CL="$(sh "$ROOT/scripts/fetch_clang22.sh" "$ROOT/components/clang22")"
LIPO="$CL/bin/llvm-lipo"; OTOOL="$CL/bin/llvm-otool"; export LIPO OTOOL
fails=0
say() { echo "FAIL: $1"; fails=$((fails+1)); }

cmake -S "$ROOT" -B "$T/shipyard-build" > "$T/install.log" 2>&1 \
  && cmake --install "$T/shipyard-build" --prefix "$T/prefix" >> "$T/install.log" 2>&1 \
  || { echo "FAIL: shipyard does not install"; sed 's/^/    | /' "$T/install.log"; exit 1; }
presets="$T/prefix/share/cmake/MavericksShipyard/mavericks-presets.json"

fixture() {  # $1 = source dir  $2 = "same" or "differ"
  mkdir -p "$1"
  printf 'int main(void) { return 0; }\n' > "$1/hello.c"
  printf 'plain data\n' > "$1/data.txt"
  printf 'arch=@CMAKE_OSX_ARCHITECTURES@\n' > "$1/arch.txt.in"
  {
    printf 'cmake_minimum_required(VERSION 3.25)\nproject(fix C)\nadd_executable(hello hello.c)\n'
    printf 'install(TARGETS hello DESTINATION bin)\ninstall(FILES data.txt DESTINATION share/fix)\n'
    if [ "$2" = differ ]; then
      printf 'configure_file(arch.txt.in arch.txt @ONLY)\ninstall(FILES ${CMAKE_BINARY_DIR}/arch.txt DESTINATION share/fix)\n'
    fi
  } > "$1/CMakeLists.txt"
  cat > "$1/CMakePresets.json" <<JSON
{ "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 25, "patch": 0 },
  "include": ["$presets"],
  "configurePresets": [
    { "name": "native", "inherits": "mavericks-native" },
    { "name": "cross", "inherits": "mavericks-cross" },
    { "name": "arm64", "inherits": "macos-arm64" } ] }
JSON
}
CMAKE=cmake; export CMAKE
fixture "$T/fix-same" same
fixture "$T/fix-differ" differ

sh "$S" --source "$T/fix-same" --out "$T/out" > "$T/out.log" 2>&1 \
  || { echo "FAIL: build_universal did not build the fixture"; sed 's/^/    | /' "$T/out.log"; exit 1; }
archs="$("$LIPO" -info "$T/out/bin/hello" | sed "s/.*: //" | tr -s " " | sed "s/ $//")"
for a in x86_64 arm64; do
  case " $archs " in *" $a "*) ;; *) say "bin/hello lacks $a: $archs" ;; esac
done
slices="$(sh "$ROOT/scripts/macho-slices.sh" "$T/out/bin/hello")"
[ "$(printf '%s\n' "$slices" | command grep -c .)" -eq 2 ] || say "expected two slices, got: $slices"
printf '%s\n' "$slices" | command grep -qx 'x86_64 EXECUTE 10.9 10.9' || say "x86_64 slice is not minos 10.9 / sdk 10.9: $slices"
printf '%s\n' "$slices" | command grep -qx 'arm64 EXECUTE 11.0 11.3' || say "arm64 slice is not minos 11.0 / sdk 11.3: $slices"
[ "$(cat "$T/out/share/fix/data.txt")" = 'plain data' ] || say "the data file was not copied intact"
[ "$(find "$T/out" -name data.txt | wc -l)" -eq 1 ] || say "the data file is not present exactly once"

for bad in "" "--source" "--source $T/fix-same" "--out $T/o2" "--source $T/fix-same --out $T/o3 --bogus x" "--source $T/fix-same --out"; do
  rc=0; sh "$S" $bad > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || say "usage error '$bad' must exit 2, got $rc"
done
rc=0; sh "$S" --source "$T/fix-same" --out "$T/out" > /dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || say "an existing --out must be refused with 2, got $rc"
[ -f "$T/out/bin/hello" ] || say "refusing an existing --out damaged it"

rc=0; sh "$S" --source "$T/fix-differ" --out "$T/out-differ" > "$T/differ.log" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || say "a data file differing between arches must exit 1, got $rc"
command grep -q 'share/fix/arch.txt' "$T/differ.log" || say "the refusal does not name share/fix/arch.txt"
[ ! -e "$T/out-differ" ] || say "a refused merge left --out behind"

[ "$fails" -eq 0 ] || exit 1
echo "PASS: build_universal builds, merges and refuses as specified"
