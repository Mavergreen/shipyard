# platform: host-agnostic
#   usage: . scripts/lib/mach-nm.sh; NM="$(shipyard_mach_nm)"; LIPO="$(shipyard_mach_tool lipo)"
#          The Mach-O tool for one of nm, lipo, otool, ar, strip or install-name-tool: its variable (NM,
#          LIPO, OTOOL, AR, STRIP, INSTALL_NAME_TOOL) when set; else the llvm- tool beside an llvm- tool
#          the caller chose as OTOOL, LIPO, NM or AR. Then on macOS, Apple's own name (for nm, an
#          installed clang22's llvm-nm first: the 10.9 CLT nm cannot read arm64 slices). Off macOS, an
#          installed clang22's (SHIPYARD_MG_PREFIX, default /usr/local/mavergreen), else the bare llvm-
#          name, never the host's: GNU ar and nm cannot read Mach-O, and GNU ar mangles Darwin archives
#          whose members share a name. shipyard_mach_nm is shipyard_mach_tool nm. SHIPYARD_MACH_HOST
#          replaces uname -s (test-only).
shipyard_mach_nm() { shipyard_mach_tool nm; }
shipyard_mach_tool() {
  case "$1" in
    nm) _mt_v=${NM:-} _mt_a=nm ;;
    lipo) _mt_v=${LIPO:-} _mt_a=lipo ;;
    otool) _mt_v=${OTOOL:-} _mt_a=otool ;;
    ar) _mt_v=${AR:-} _mt_a=ar ;;
    strip) _mt_v=${STRIP:-} _mt_a=strip ;;
    install-name-tool) _mt_v=${INSTALL_NAME_TOOL:-} _mt_a=install_name_tool ;;
    *) echo "shipyard_mach_tool: no Mach-O tool named '$1'" >&2; return 2 ;;
  esac
  if [ -n "$_mt_v" ]; then printf '%s\n' "$_mt_v"; return 0; fi
  for _mt_r in "${OTOOL:-}" "${LIPO:-}" "${NM:-}" "${AR:-}"; do
    case "$_mt_r" in
      */llvm-*) [ -x "${_mt_r%/*}/llvm-$1" ] && { printf '%s\n' "${_mt_r%/*}/llvm-$1"; return 0; } ;;
    esac
  done
  _mt_h=${SHIPYARD_MACH_HOST:-$(uname -s)}
  if [ "$_mt_h" != Darwin ] || [ "$1" = nm ]; then
    for _mt_d in clang22 clang22-cross; do
      _mt_t="${SHIPYARD_MG_PREFIX:-/usr/local/mavergreen}/$_mt_d/bin/llvm-$1"
      [ -x "$_mt_t" ] && { printf '%s\n' "$_mt_t"; return 0; }
    done
  fi
  if [ "$_mt_h" = Darwin ]; then printf '%s\n' "$_mt_a"; else printf 'llvm-%s\n' "$1"; fi
}
