#!/bin/sh
# platform: host-agnostic
#   usage: . macho-tools.sh     (sourced; defines mach_tool, mach_pinned_dirs and mach_pinned)
#          mach_tool OTOOL|LIPO|NM|STRINGS|DSYMUTIL|STRIP|OBJDUMP
#                                            leaves the variable set and exported, to the tool the
#                                            caller named or else LLVM's, and returns 0. When none is found
#                                            it says which variable to set and returns 1.
#          SHIPYARD_MACHO_DIRS, when set, replaces the family directories searched after
#          clang-22's own (a test seam: the tests set it empty to mean "nowhere"). The default is
#          clang22/bin under ${MAVERGREEN_ROOT}/opt/mavergreen, then clang22/bin and clang22-cross/bin under
#          ${MAVERGREEN_ROOT}/usr/local/mavergreen. MAVERGREEN_ROOT is the volume, default /; the caller
#          sources mavergreen-meta.sh and lib/name-rules.sh first, for mavergreen_prefix.
#          NM, DSYMUTIL, STRIP and OBJDUMP also try, before all of those, the tool beside the llvm-otool,
#          llvm-lipo or llvm-nm the caller chose; NM after all of them a bare nm. DSYMUTIL takes LLVM's
#          unprefixed dsymutil wherever it takes llvm-dsymutil, as dsymutil-N where llvm-dsymutil-N, and
#          on PATH only beside an llvm-objdump.
#          mach_pinned_dirs prints those family directories, one per line; mach_pinned NAME prints the
#          first llvm-NAME in them, or returns 1. Neither looks on PATH.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the Mach-O
#       readers are LLVM's on every host, so one binary reads the same on 10.9, modern macOS and
#       Linux. They are looked for next to clang-22 on PATH, then in the family prefix, then from xcrun on macOS, then as a
#       version-suffixed name on PATH (what a Linux distribution ships), then bare on PATH. Apple's
#       otool and lipo are never a fallback: the 10.9 CLT's otool cannot read LC_BUILD_VERSION.

mach_pinned_dirs() {
  type mavergreen_prefix >/dev/null 2>&1 || { echo "macho-tools: mavergreen_prefix is undefined (source mavergreen-meta.sh and lib/name-rules.sh first)" >&2; return 2; }
  _mp_vol="${MAVERGREEN_ROOT:-}"; _mp_vol="${_mp_vol%/}"
  for _mp_d in ${SHIPYARD_MACHO_DIRS-$_mp_vol$(mavergreen_prefix clang22)/bin $_mp_vol/usr/local/mavergreen/clang22/bin $_mp_vol/usr/local/mavergreen/clang22-cross/bin}; do
    printf '%s\n' "$_mp_d"
  done
}
mach_pinned() {
  _mp_ds="$(mach_pinned_dirs)" || return 2
  for _mp_t in $_mp_ds; do
    [ -x "$_mp_t/llvm-$1" ] && { printf '%s\n' "$_mp_t/llvm-$1"; return 0; }
  done
  return 1
}

mach_tool() {
  case "$1" in
    OTOOL) _mt=otool ;;
    LIPO) _mt=lipo ;;
    NM) _mt=nm ;;
    STRINGS) _mt=strings ;;
    DSYMUTIL) _mt=dsymutil ;;
    STRIP) _mt=strip ;;
    OBJDUMP) _mt=objdump ;;
    *) echo "macho-tools: no such reader: $1" >&2; return 2 ;;
  esac
  eval "_mt_cur=\${$1:-}"
  [ -z "$_mt_cur" ] || return 0
  _mt_found=""
  _mt_plain=""; [ "$_mt" != dsymutil ] || _mt_plain=dsymutil
  case "$_mt" in
    nm|dsymutil|strip|objdump)
      for _mt_r in "${OTOOL:-}" "${LIPO:-}" "${NM:-}"; do
        case "$_mt_r" in
          */llvm-otool|*/llvm-lipo|*/llvm-nm)
            for _mt_n in "llvm-$_mt" $_mt_plain; do
              if [ -x "${_mt_r%/*}/$_mt_n" ]; then _mt_found="${_mt_r%/*}/$_mt_n"; break 2; fi
            done ;;
        esac
      done ;;
  esac
  _mt_clang="$(command -v clang-22 2>/dev/null || true)"
  _mt_dirs="$(mach_pinned_dirs)" || return 2
  for _mt_dir in "${_mt_clang%/*}" $_mt_dirs; do
    [ -z "$_mt_found" ] || break
    [ -n "$_mt_dir" ] || continue
    for _mt_n in "llvm-$_mt" $_mt_plain; do
      if [ -x "$_mt_dir/$_mt_n" ]; then _mt_found="$_mt_dir/$_mt_n"; break 2; fi
    done
  done
  # platform: Xcode ships LLVM's own llvm-otool, llvm-lipo, llvm-nm and llvm-strings (not cctools), and
  #           xcrun finds them without them being on PATH.
  if [ -z "$_mt_found" ] && command -v xcrun >/dev/null 2>&1; then
    # platform: guarded macOS-only call -- xcrun exists only on a Mac, and the enclosing `if` tests for it
    _mt_found="$(xcrun -f "llvm-$_mt" 2>/dev/null || true)"
    [ -x "$_mt_found" ] || _mt_found=""
  fi
  if [ -z "$_mt_found" ]; then
    _mt_n=40
    while [ "$_mt_n" -ge 10 ]; do
      for _mt_x in "llvm-$_mt" $_mt_plain; do
        _mt_found="$(command -v "$_mt_x-$_mt_n" 2>/dev/null || true)"
        [ -z "$_mt_found" ] || break 2
      done
      _mt_n=$((_mt_n - 1))
    done
  fi
  [ -n "$_mt_found" ] || _mt_found="$(command -v "llvm-$_mt" 2>/dev/null || true)"
  if [ -z "$_mt_found" ] && [ -n "$_mt_plain" ]; then
    _mt_found="$(command -v dsymutil 2>/dev/null || true)"
    case "$_mt_found" in /*) [ -x "${_mt_found%/*}/llvm-objdump" ] || _mt_found="" ;; *) _mt_found="" ;; esac
  fi
  if [ -z "$_mt_found" ] && [ "$_mt" = nm ]; then _mt_found="$(command -v nm 2>/dev/null || true)"; fi
  if [ -z "$_mt_found" ]; then
    echo "macho-tools: no llvm-$_mt found next to clang-22, in /opt/mavergreen/clang22/bin, in /usr/local/mavergreen/clang22/bin, from xcrun or on PATH -- set $1 to its path" >&2
    return 1
  fi
  eval "$1=\$_mt_found"
  export "$1"
  unset _mt_found
}
