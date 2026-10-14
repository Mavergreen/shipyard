#!/bin/sh
# platform: host-agnostic
#   usage: . macho-tools.sh     (sourced; defines mach_tool)
#          mach_tool OTOOL|LIPO|NM|STRINGS   leaves the variable set and exported, to the reader the
#                                            caller named or else LLVM's, and returns 0. When none is found
#                                            it says which variable to set and returns 1.
#          SHIPYARD_MACHO_DIRS, when set, replaces the two family directories searched after
#          clang-22's own (a test seam: the tests set it empty to mean "nowhere").
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the Mach-O
#       readers are LLVM's on every host, so one binary reads the same on 10.9, modern macOS and
#       Linux. They are looked for next to clang-22 on PATH, then in the family prefix, then as a
#       version-suffixed name on PATH (what a Linux distribution ships), then bare on PATH. Apple's
#       otool and lipo are never a fallback: the 10.9 CLT's otool cannot read LC_BUILD_VERSION.

mach_tool() {
  case "$1" in
    OTOOL) _mt=otool ;;
    LIPO) _mt=lipo ;;
    NM) _mt=nm ;;
    STRINGS) _mt=strings ;;
    *) echo "macho-tools: no such reader: $1" >&2; return 2 ;;
  esac
  eval "_mt_cur=\${$1:-}"
  [ -z "$_mt_cur" ] || return 0
  _mt_found=""
  _mt_clang="$(command -v clang-22 2>/dev/null || true)"
  for _mt_dir in "${_mt_clang%/*}" ${SHIPYARD_MACHO_DIRS-/opt/mavergreen/clang22/bin /usr/local/mavergreen/clang22/bin}; do
    [ -n "$_mt_dir" ] || continue
    if [ -x "$_mt_dir/llvm-$_mt" ]; then _mt_found="$_mt_dir/llvm-$_mt"; break; fi
  done
  if [ -z "$_mt_found" ]; then
    _mt_n=40
    while [ "$_mt_n" -ge 10 ]; do
      _mt_found="$(command -v "llvm-$_mt-$_mt_n" 2>/dev/null || true)"
      [ -z "$_mt_found" ] || break
      _mt_n=$((_mt_n - 1))
    done
  fi
  [ -n "$_mt_found" ] || _mt_found="$(command -v "llvm-$_mt" 2>/dev/null || true)"
  if [ -z "$_mt_found" ]; then
    echo "macho-tools: no llvm-$_mt found next to clang-22, in /opt/mavergreen/clang22/bin, in /usr/local/mavergreen/clang22/bin or on PATH -- set $1 to its path" >&2
    return 1
  fi
  eval "$1=\$_mt_found"
  export "$1"
  unset _mt_found
}
