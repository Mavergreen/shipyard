#!/bin/sh
# platform: host-agnostic
#   usage: audit-repo-settings.sh [org]        (default: Mavergreen)
#          Prints a verdict line and exits non-zero when anything is off, to be usable from a
#          scheduled job with a PAT later.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "These two
#       settings are the only conventions the gate cannot check -- audit them" -- "Allow auto-merge"
#       (OFF by GitHub default) and branch protection on main requiring the PR build check are GitHub
#       repo state, reachable only through the API, so no renovate.json preset can set them; they
#       drifted exactly that way (four repos created 2026-08-02..08-04 had neither, and
#       signal-desktop's Signal 8.26.0 sat green and unmerged for a MONTH with nothing going red).
#       Not a CI gate: reading branch protection requires ADMIN, which a workflow's default
#       GITHUB_TOKEN does not have, so this runs with a human's `gh` credentials instead.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/lib/gh-admin.sh"
org="${1:-Mavergreen}"
[ -n "${SHIPYARD_CHECK_RUNLOG:-}" ] || chk_gh_admin "$org" || exit 2
chk_ran repo-auto-merge
chk_ran repo-required-context

printf '%-28s %-10s %s\n' REPO AUTO-MERGE 'REQUIRED CHECKS ON main'
for repo in $(gh repo list "$org" --limit 100 --json name --jq '.[].name' | sort); do
  am="$(gh api "repos/$org/$repo" --jq '.allow_auto_merge' 2>/dev/null || echo '?')"

  if ! gh api "repos/$org/$repo/contents/.github/workflows/release.yml" --jq '.name' >/dev/null 2>&1; then
    printf '%-28s %-10s %s\n' "$repo" "$am" '(no release.yml — not a product repo)'
    continue
  fi

  # platform: take the EXIT STATUS, not the output. On a 404 (no protection) gh prints its error
  #           JSON to STDOUT and exits non-zero; `|| true` kept that JSON as the value, so a repo
  #           with no protection at all looked like a repo with a required check named
  #           `{"message":"Branch not protected"...}` and the audit reported ok.
  if ctx="$(gh api "repos/$org/$repo/branches/main/protection" \
              --jq '.required_status_checks.contexts | join(",")' 2>/dev/null)"; then
    [ -n "$ctx" ] || ctx='NONE (protected, but no required check)'
  else
    ctx='NONE'
  fi

  printf '%-28s %-10s %s\n' "$repo" "$am" "$ctx"
  [ "$am" = true ] || chk_fail repo-auto-merge "$org/$repo allows auto-merge" \
    "its Allow auto-merge setting is $am, so a green Renovate bump never merges" \
    "gh api -X PATCH repos/$org/$repo -F allow_auto_merge=true"
  case "$ctx" in
    NONE*) chk_fail repo-required-context "$org/$repo requires a status check on main" \
      "main has no required check ($ctx), so a green Renovate bump never merges" \
      "read the build JOB NAME from gh api repos/$org/$repo/commits/main/check-runs --jq '[.check_runs[].name]|unique', then require it: printf '{\"required_status_checks\":{\"strict\":false,\"contexts\":[\"<job>\"]},\"enforce_admins\":false,\"required_pull_request_reviews\":null,\"restrictions\":null}' | gh api -X PUT repos/$org/$repo/branches/main/protection --input -" ;;
  esac
done

echo
if [ "$chk_status" -eq 0 ]; then
  echo "audit-repo-settings: ok — every product repo can automerge a green bump"
fi
exit "$chk_status"
