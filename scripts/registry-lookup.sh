#!/bin/sh
# platform: host-agnostic
#   usage: . registry-lookup.sh   (sourced, with SELF set to shipyard's scripts directory)
#          registry_lookup FACT KEY         runs product-name.sh FACT KEY: 0 with the answer in REG_V;
#                                           1 when KEY is not registered; 2 when the registry cannot
#                                           answer, with product-name.sh's own reason in REG_WHY
#          registry_need CALLER FACT KEY    the same, but a failure prints why, prefixed CALLER:, and
#                                           exits the sourcing script: 1 when KEY is not registered,
#                                           2 when the registry cannot answer
# spec: tests/product-names-test.sh -- product-name.sh exits 1 only when KEY names no product it will
#       answer for; any other failure, or an empty answer, means the registry cannot answer.

registry_lookup() {
  REG_V=""; REG_WHY=""
  _rl_rc=0
  _rl_out="$(sh "$SELF/product-name.sh" "$1" "$2" 2>/dev/null)" || _rl_rc=$?
  if [ "$_rl_rc" -eq 0 ] && [ -n "$_rl_out" ]; then
    REG_V="$_rl_out"; return 0
  fi
  [ "$_rl_rc" -ne 1 ] || return 1
  _rl_why="$(sh "$SELF/product-name.sh" "$1" "$2" 2>&1 >/dev/null)" || :
  REG_WHY="${_rl_why:-product-name.sh $1 $2 exited $_rl_rc with no answer}"
  return 2
}

registry_need() {
  _rn_rc=0; registry_lookup "$2" "$3" || _rn_rc=$?
  case "$_rn_rc" in
    0) return 0 ;;
    1) echo "$1: $3 is not in shipyard's scripts/product-names -- register it there first" >&2; exit 1 ;;
    *) printf "%s: cannot look up %s in shipyard's registry\n%s\n" "$1" "$3" "$REG_WHY" >&2; exit 2 ;;
  esac
}
