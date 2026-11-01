# platform: host-agnostic
#   usage: . scripts/lib/mach-nm.sh; NM="$(shipyard_mach_nm)"
#          The Mach-O symbol reader: NM when set; else the llvm-nm beside the llvm-otool or llvm-lipo the
#          caller chose as OTOOL or LIPO; else an installed clang22's (SHIPYARD_MG_PREFIX, default
#          /usr/local/mavergreen); else nm. GNU nm cannot read Mach-O, and the 10.9 CLT nm cannot read
#          arm64 slices.
shipyard_mach_nm() {
  if [ -n "${NM:-}" ]; then printf '%s\n' "$NM"; return 0; fi
  for _mn_r in "${OTOOL:-}" "${LIPO:-}"; do
    case "$_mn_r" in
      */llvm-otool|*/llvm-lipo)
        [ -x "${_mn_r%/*}/llvm-nm" ] && { printf '%s\n' "${_mn_r%/*}/llvm-nm"; return 0; } ;;
    esac
  done
  for _mn_d in clang22 clang22-cross; do
    _mn_n="${SHIPYARD_MG_PREFIX:-/usr/local/mavergreen}/$_mn_d/bin/llvm-nm"
    [ -x "$_mn_n" ] && { printf '%s\n' "$_mn_n"; return 0; }
  done
  printf 'nm\n'
}
