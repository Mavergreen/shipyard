#!/bin/sh
# platform: host-agnostic
#   usage: payload-cmake-independent-test.sh
#          The installed payload is the same whichever cmake stages it: the package job stages it with
#          the runner's cmake, and a Mac stages it with the cmake product. CMake's own generated
#          templates vary by CMake version, so nothing installed is written from one; the version
#          file is configured from MavergreenShipyardConfigVersion.cmake.in, and it still answers
#          find_package's version checks.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
command -v cmake >/dev/null 2>&1 || { echo "SKIP: no cmake"; exit 77; }
fail() { echo "FAIL: $*"; exit 1; }

code() { sed 's/#.*//' "$root/CMakeLists.txt"; }
for gen in write_basic_package_version_file write_basic_config_version_file configure_package_config_file; do
  code | grep -q "$gen" && fail "CMakeLists.txt calls $gen, whose output is CMake's template and varies with the cmake that stages the payload"
done

_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/payload-cmake.XXXXXX")"; trap 'rm -rf "$w"' EXIT
cmake -S "$root" -B "$w/b" > "$w/configure.log" 2>&1 || { sed 's/^/    | /' "$w/configure.log"; fail "configure failed"; }
want="$(sh "$root/scripts/shipyard-version.sh" | sed -n 's/^FULL=//p')"
cv="$w/b/MavergreenShipyardConfigVersion.cmake"
major="${want%%.*}"
sed -e "s/@PROJECT_VERSION@/$want/g" -e "s/@PROJECT_VERSION_MAJOR@/$major/g" \
  "$root/MavergreenShipyardConfigVersion.cmake.in" | cmp -s - "$cv" \
  || fail "the version file is not MavergreenShipyardConfigVersion.cmake.in configured with $want"

probe() {  # $1 = the version find_package asks for (a range is X...Y or X...<Y); prints COMPATIBLE EXACT
  _r="$1"; _min="${_r%%...*}"; _max=""; _end=INCLUDE
  case "$_r" in *...\<*) _max="${_r#*...<}"; _end=EXCLUDE ;; *...*) _max="${_r#*...}" ;; esac
  {
    echo "set(PACKAGE_FIND_VERSION \"$_min\")"
    echo "string(REGEX MATCH \"^[0-9]+\" PACKAGE_FIND_VERSION_MAJOR \"$_min\")"
    if [ -n "$_max" ]; then
      echo "set(PACKAGE_FIND_VERSION_RANGE \"$_r\")"
      echo "set(PACKAGE_FIND_VERSION_MIN_MAJOR \"\${PACKAGE_FIND_VERSION_MAJOR}\")"
      echo "set(PACKAGE_FIND_VERSION_RANGE_MAX $_end)"
      echo "set(PACKAGE_FIND_VERSION_MAX \"$_max\")"
      echo "string(REGEX MATCH \"^[0-9]+\" PACKAGE_FIND_VERSION_MAX_MAJOR \"$_max\")"
    fi
    echo "include(\"$cv\")"
    echo "message(\"\${PACKAGE_VERSION_COMPATIBLE} \${PACKAGE_VERSION_EXACT}\")"
  } > "$w/probe.cmake"
  cmake -P "$w/probe.cmake" 2>&1
}
next=$((major + 1))
[ "$(probe "$major")" = "TRUE " ] || fail "find_package(MavergreenShipyard $major) must accept $want: $(probe "$major")"
[ "$(probe "$want")" = "TRUE TRUE" ] || fail "find_package(MavergreenShipyard $want) must be an exact match: $(probe "$want")"
[ "$(probe "$next")" = "FALSE " ] || fail "find_package(MavergreenShipyard $next) must refuse $want: $(probe "$next")"
[ "$(probe "$want.1")" = "FALSE " ] || fail "find_package(MavergreenShipyard $want.1) must refuse the older $want: $(probe "$want.1")"
[ "$(probe "$major...<$next")" = "TRUE " ] || fail "the range $major...<$next must accept $want: $(probe "$major...<$next")"
[ "$(probe "$major...$next")" = "FALSE " ] || fail "the range $major...$next reaches another major, so it must refuse $want: $(probe "$major...$next")"
echo "PASS: payload-cmake-independent"
