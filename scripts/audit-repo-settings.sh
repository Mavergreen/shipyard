#!/bin/sh
#   usage: audit-repo-settings.sh [org]        (default: Mavergreen)
#          Prints a verdict line and exits non-zero when anything is off, to be usable from a
#          scheduled job with a PAT later.
# spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md "These two
#       settings are the only conventions the gate cannot check -- audit them" -- "Allow auto-merge"
#       (OFF by GitHub default) and branch protection on main requiring the PR build check are GitHub
#       repo state, reachable only through the API, so no renovate.json preset can set them; they
#       drifted exactly that way (four repos created 2026-08-02..08-04 had neither, and
#       signal-desktop's Signal 8.26.0 sat green and unmerged for a MONTH with nothing going red).
#       Not a CI gate: reading branch protection requires ADMIN, which a workflow's default
#       GITHUB_TOKEN does not have, so this runs with a human's `gh` credentials instead.
set -eu
org="${1:-Mavergreen}"
command -v gh >/dev/null 2>&1 || { echo "audit-repo-settings: needs the gh CLI" >&2; exit 1; }

bad=0
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
  [ "$am" = true ] || { bad=$((bad + 1)); }
  case "$ctx" in NONE*) bad=$((bad + 1)) ;; esac
done

echo
if [ "$bad" -eq 0 ]; then
  echo "audit-repo-settings: ok — every product repo can automerge a green bump"
  exit 0
fi
echo "audit-repo-settings: $bad setting(s) would stop a green Renovate bump from merging" >&2
echo "    fix: gh api -X PATCH repos/$org/<repo> -F allow_auto_merge=true" >&2
echo "    fix: printf '{\"required_status_checks\":{\"strict\":false,\"contexts\":[\"<job>\"]},\"enforce_admins\":false,\"required_pull_request_reviews\":null,\"restrictions\":null}' | gh api -X PUT repos/$org/<repo>/branches/main/protection --input -" >&2
echo "    the context is the build JOB NAME; read it from a real run first:" >&2
echo "    gh api repos/$org/<repo>/commits/main/check-runs --jq '[.check_runs[].name]|unique'" >&2
exit 1
