#!/bin/sh
# platform: host-agnostic
chk_gh_admin() {
  _ga_org="${1:-Mavergreen}"
  _ga_ok=0
  if command -v gh >/dev/null 2>&1; then
    _ga_st="$(gh auth status 2>&1)" && {
      case "$_ga_st" in
        *admin:org*) _ga_ok=1 ;;
        *) [ "$(gh api "repos/$_ga_org/shipyard" --jq '.permissions.admin' 2>/dev/null)" = true ] && _ga_ok=1 ;;
      esac
    }
  fi
  [ "$_ga_ok" -eq 1 ] && return 0
  echo "needs an admin token: \`gh auth status\` must show \`admin:org\` or repo admin" >&2
  return 1
}
