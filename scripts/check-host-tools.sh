#!/bin/sh
# platform: host-agnostic
#   usage: check-host-tools.sh [--required]
#          Scans the WHOLE tracked tree, tests/ included: every *.sh, *.bats, *.bash and *.py,
#          every file git tracks as executable, and every file whose first line is "#!". Only
#          scripts/templates/ is skipped -- those are other repos' canonical copies, compared byte
#          for byte by check 17. Each script must declare its host in its header (host-of.sh), and
#          a host-agnostic one may not run a macOS-only tool (host-tools.awk) unless the comment
#          line directly above the call says "# platform: guarded macOS-only call -- <the guard>".
#          A repo where no script declares a host has not adopted the split and passes, saying
#          so; --required makes that a failure. Exit 0 clean, 1 on a violation, 2 on a usage
#          error or when git cannot list the tree.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md check 22
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
required=0
case "$#:${1:-}" in
  0:) ;;
  1:--required) required=1 ;;
  *) echo "usage: check-host-tools.sh [--required]" >&2; exit 2 ;;
esac

_tmp="${TMPDIR:-/tmp}"
list="$(mktemp "${_tmp%/}/host-tools-list.XXXXXX")"
hits="$(mktemp "${_tmp%/}/host-tools-hits.XXXXXX")"
undeclared="$(mktemp "${_tmp%/}/host-tools-undeclared.XXXXXX")"
trap 'rm -f "$list" "$hits" "$undeclared"' EXIT
git ls-files -s > "$list" 2>/dev/null \
  || { echo "check-host-tools: git ls-files failed in $(pwd) -- refusing to report clean having examined nothing" >&2; exit 2; }

status=0
fail() { echo "check-host-tools: $1" >&2; echo "    fix: $2" >&2; status=1; }
TAB="$(printf '\t')"
nscripts=0; nagnostic=0; nmacos=0
while IFS="$TAB" read -r meta p; do
  case "$p" in scripts/templates/*) continue ;; esac
  # platform: a file deleted in the worktree but not yet from the index is still listed
  [ -f "$p" ] || continue
  case "$p" in
    *.sh|*.bats|*.bash|*.py) ;;
    *) case "$meta" in
         100755' '*) ;;
         *) [ "$(head -c 2 "$p")" = '#!' ] || continue ;;
       esac ;;
  esac
  nscripts=$((nscripts + 1))
  rc=0; host="$(sh "$SELF/host-of.sh" "$p")" || rc=$?
  case "$rc" in
    0) ;;
    1) printf '%s\n' "$p" >> "$undeclared"; continue ;;
    3) fail "$p declares its host more than once" "keep exactly one: # platform: host-agnostic, or # platform: macOS-only -- <why>"; continue ;;
    *) fail "$p could not be read (host-of.sh exit $rc)" "check the file's permissions"; continue ;;
  esac
  if [ "$host" = macOS-only ]; then nmacos=$((nmacos + 1)); continue; fi
  nagnostic=$((nagnostic + 1))
  awk -f "$SELF/host-tools.awk" "$p" > "$hits"
  while IFS="$TAB" read -r ln tool text; do
    fail "$p:$ln: declares itself host-agnostic but runs $tool, which Linux does not have: $(printf '%s' "$text" | sed 's/^[[:space:]]*//' | cut -c1-70)" \
         "declare the file '# platform: macOS-only -- $tool', or guard the call and say so on the line above it: # platform: guarded macOS-only call -- <the guard>"
  done < "$hits"
done < "$list"

if [ "$((nagnostic + nmacos))" -eq 0 ]; then
  if [ "$required" -eq 1 ]; then
    fail "no tracked script declares a host, and --required says this repo has adopted the split ($nscripts scripts found across the whole tree)" \
         "declare each one in its header: # platform: host-agnostic, or # platform: macOS-only -- <why>"
    exit 1
  fi
  echo "check-host-tools: no tracked script declares a host -- this repo has not adopted the host split; nothing enforced ($nscripts scripts found)"
  exit 0
fi

while IFS= read -r p; do
  if grep -qE '^# platform: (host-agnostic|macOS-only)' "$p"; then
    fail "$p declares its host below its first line of code, or declares macOS-only with no reason" \
         "move it into the header, before any code: # platform: host-agnostic, or # platform: macOS-only -- <why>"
  else
    fail "$p declares no host -- an undeclared script is an error, never assumed host-agnostic" \
         "add to its header, before any code: # platform: host-agnostic, or # platform: macOS-only -- <why>"
  fi
done < "$undeclared"

[ "$status" -eq 0 ] \
  && echo "check-host-tools: ok -- $nscripts tracked scripts across the whole tree ($nagnostic host-agnostic, $nmacos macOS-only); *.cmake and workflow run: blocks are not scripts and are not scanned"
exit "$status"
