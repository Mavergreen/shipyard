#!/bin/sh
# platform: host-agnostic
#   usage: install-macho-readers.sh
#          Resolves LLVM's Mach-O readers (llvm-otool, llvm-lipo, llvm-nm, llvm-strings) through
#          lib/macho-tools.sh -- next to clang-22, the family directories, Xcode's own via xcrun,
#          version-suffixed or bare on PATH -- and names each in $GITHUB_ENV as OTOOL, LIPO, NM and
#          STRINGS (never on PATH: Homebrew's llvm also carries a clang, and the build keeps its own).
#          Only a reader still missing with brew present installs Homebrew's llvm. A reader missing
#          after that prints a ::warning:: naming it and the variable to set, and the script still exits
#          0: it must never fail install@v1. The failure comes where a reader is used (the compat
#          guard, shipyard-check --dist), naming the variable.
# spec: scripts/lib/macho-tools.sh -- Apple's cctools otool and lipo are never a fallback.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib/macho-tools.sh"

missing=""
for v in OTOOL LIPO NM STRINGS; do mach_tool "$v" 2>/dev/null || missing="$missing $v"; done
if [ -n "$missing" ] && command -v brew >/dev/null 2>&1; then
  brew list llvm >/dev/null 2>&1 || brew install llvm || :
  d="$(brew --prefix llvm 2>/dev/null || :)"
  [ -z "$d" ] || d="$d/bin"
  for v in $missing; do
    case "$v" in OTOOL) t=otool ;; LIPO) t=lipo ;; NM) t=nm ;; STRINGS) t=strings ;; esac
    if [ -n "$d" ] && [ -x "$d/llvm-$t" ]; then eval "$v=$d/llvm-$t"; export "$v"; fi
  done
fi
for v in OTOOL LIPO NM STRINGS; do
  eval "val=\${$v:-}"
  if [ -n "$val" ]; then
    echo "install-macho-readers: $v=$val"
    [ -z "${GITHUB_ENV:-}" ] || echo "$v=$val" >> "$GITHUB_ENV"
  else
    echo "::warning::install-macho-readers: no llvm reader for $v was found, so the compat guard and shipyard-check --dist will fail -- install LLVM's tools or set $v to its path"
  fi
done
exit 0
