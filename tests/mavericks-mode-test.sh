#!/bin/sh
# platform: host-agnostic
#   usage: mavericks-mode-test.sh
#          scripts/mavericks_mode.sh and MavericksMode.cmake call an OS X 10.9.x host "mavericks" and
#          every other host "modern", with sw_vers and uname stubbed on PATH. Exit 0 clean, 1 on
#          failure, 77 with no cmake.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/.." && pwd)"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/mavericks-mode.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fails=0
say() { echo "FAIL: $1"; fails=$((fails+1)); }

stub() {  # $1 = directory  $2 = uname -s  $3 = sw_vers -productVersion
  mkdir -p "$1"
  printf '#!/bin/sh\necho %s\n' "$2" > "$1/uname"
  printf '#!/bin/sh\necho %s\n' "$3" > "$1/sw_vers"
  chmod +x "$1/uname" "$1/sw_vers"
}
stub "$w/mav" Darwin 10.9.5
stub "$w/tahoe" Darwin 26.1
stub "$w/linux" Linux 10.9.5
rm "$w/linux/sw_vers"

for c in "mav mavericks" "tahoe modern" "linux modern"; do
  h="${c% *}"; want="${c#* }"
  got="$(PATH="$w/$h:$PATH" sh "$root/scripts/mavericks_mode.sh")"
  [ "$got" = "$want" ] || say "mavericks_mode.sh on the $h stub printed '$got', not '$want'"
done

cm="$(command -v cmake 2>/dev/null || true)"
[ -n "$cm" ] || { echo "SKIP: no cmake"; exit 77; }
printf 'set(APPLE 1)\nlist(APPEND CMAKE_MODULE_PATH "%s")\ninclude(MavericksMode)\nmavericks_build_mode(fn)\nmessage("MODE=${MAVERICKS_MODE} FN=${fn}")\n' \
  "$root" > "$w/mode.cmake"
for c in "mav mavericks" "tahoe modern"; do
  h="${c% *}"; want="${c#* }"
  out="$(PATH="$w/$h:$PATH" "$cm" -P "$w/mode.cmake" 2>&1)" || say "MavericksMode.cmake failed on the $h stub: $out"
  case "$out" in
    *"MODE=$want FN=$want"*) ;;
    *) say "MavericksMode.cmake on the $h stub did not set MAVERICKS_MODE and mavericks_build_mode to '$want': $out" ;;
  esac
done

[ "$fails" -eq 0 ] || exit 1
echo "PASS: mavericks-mode"
