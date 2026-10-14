#!/bin/sh
# platform: host-agnostic
#   usage: install-macho-readers.sh
#          Makes LLVM's Mach-O readers (llvm-otool, llvm-lipo, llvm-nm, llvm-strings) available to the
#          compat guard and artifact-facts on a CI runner that has no family clang. When
#          lib/macho-tools.sh already finds all four, it changes nothing. Otherwise it installs
#          Homebrew's llvm and names the four tools in $GITHUB_ENV as OTOOL, LIPO, NM and STRINGS, and
#          not on PATH: Homebrew's llvm also carries a clang, and the build must keep the one it
#          chose. Exit 1, saying which reader is missing, when there is nothing to install it with.
# spec: scripts/lib/macho-tools.sh -- Apple's otool and lipo are never a fallback, so a macOS runner
#       (Xcode's tools only) needs LLVM's readers put there.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib/macho-tools.sh"

missing=0
for v in OTOOL LIPO NM STRINGS; do mach_tool "$v" 2>/dev/null || missing=1; done
if [ "$missing" -eq 1 ]; then
  command -v brew >/dev/null 2>&1 \
    || { echo "install-macho-readers: LLVM's readers are not installed and there is no brew to install them -- put llvm-otool, llvm-lipo, llvm-nm and llvm-strings on PATH, or set OTOOL, LIPO, NM and STRINGS" >&2; exit 1; }
  brew list llvm >/dev/null 2>&1 || brew install llvm
  d="$(brew --prefix llvm)/bin"
  for pair in OTOOL:otool LIPO:lipo NM:nm STRINGS:strings; do
    [ -x "$d/llvm-${pair#*:}" ] || { echo "install-macho-readers: $d has no llvm-${pair#*:}" >&2; exit 1; }
    eval "${pair%%:*}=$d/llvm-${pair#*:}"
    export "${pair%%:*}"
  done
fi
for v in OTOOL LIPO NM STRINGS; do
  eval "val=\$$v"
  echo "install-macho-readers: $v=$val"
  [ -z "${GITHUB_ENV:-}" ] || echo "$v=$val" >> "$GITHUB_ENV"
done
