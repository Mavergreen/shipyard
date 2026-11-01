#!/bin/sh
# platform: host-agnostic
#   usage: audit-repo-settings.sh [org]        (default: Mavergreen)
#          Prints a verdict line and exits non-zero when anything is off (a private repo, which on the
#          org's free plan gets no org secrets; auto-merge off; main without a required check, or
#          without its release.yml's Mavergreen/mavericks-vm job among them), to be usable from a
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
. "$SELF/lib/py.sh"
org="${1:-Mavergreen}"
[ -n "${SHIPYARD_CHECK_RUNLOG:-}" ] || chk_gh_admin "$org" || exit 2
chk_ran repo-public
chk_ran repo-auto-merge
chk_ran repo-required-context
chk_ran repo-requires-on-target
w="$(mktemp -d "${TMPDIR:-/tmp}/audit-repo-settings.XXXXXX")"   # template: 10.9 BSD mktemp requires one
trap 'rm -rf "$w"' EXIT
cat > "$w/vm.py" <<'PY'
import subprocess, sys, yaml
def jobs_of(wf):
    j = wf.get("jobs") if isinstance(wf, dict) else None
    return [(k, b) for k, b in j.items() if isinstance(b, dict)] if isinstance(j, dict) else []
def runs_vm(b):
    return any(isinstance(st, dict) and isinstance(st.get("uses"), str)
               and st["uses"].lower().startswith("mavergreen/mavericks-vm@")
               for st in (b.get("steps") or []))
for j, b in jobs_of(yaml.safe_load(open(sys.argv[2])) or {}):
    if runs_vm(b):
        print(b.get("name") or j)
    elif isinstance(b.get("uses"), str) and b["uses"].startswith("./.github/workflows/"):
        called = subprocess.run(["gh", "api", "-H", "Accept: application/vnd.github.raw",
                                 "repos/%s/contents/%s" % (sys.argv[1], b["uses"][2:])],
                                stdout=subprocess.PIPE, universal_newlines=True, check=True).stdout
        for cj, cb in jobs_of(yaml.safe_load(called) or {}):
            if runs_vm(cb):
                print("%s / %s" % (b.get("name") or j, cb.get("name") or cj))
PY

printf '%-28s %-10s %-10s %s\n' REPO VISIBILITY AUTO-MERGE 'REQUIRED CHECKS ON main'
for repo in $(gh repo list "$org" --limit 100 --json name --jq '.[].name' | sort); do
  am="$(gh api "repos/$org/$repo" --jq '.allow_auto_merge' 2>/dev/null || echo '?')"
  vis="$(gh api "repos/$org/$repo" --jq '.visibility' 2>/dev/null || echo '?')"
  [ "$vis" = public ] || chk_fail repo-public "$org/$repo is public" \
    "it is $vis, and on the org's free plan a private repo gets no org secrets" \
    "sh scripts/setup-family-repo.sh settle $repo, or by hand: gh repo edit $org/$repo --visibility public --accept-visibility-change-consequences"

  if ! gh api "repos/$org/$repo/contents/.github/workflows/release.yml" --jq '.name' >/dev/null 2>&1; then
    printf '%-28s %-10s %-10s %s\n' "$repo" "$vis" "$am" '(no release.yml — not a product repo)'
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

  printf '%-28s %-10s %-10s %s\n' "$repo" "$vis" "$am" "$ctx"
  [ "$am" = true ] || chk_fail repo-auto-merge "$org/$repo allows auto-merge" \
    "its Allow auto-merge setting is $am, so a green Renovate bump never merges" \
    "sh scripts/setup-family-repo.sh settle $repo (it writes every family repo setting), or by hand: gh api -X PATCH repos/$org/$repo -F allow_auto_merge=true"
  case "$ctx" in
    NONE*) chk_fail repo-required-context "$org/$repo requires a status check on main" \
      "main has no required check ($ctx), so a green Renovate bump never merges" \
      "sh scripts/setup-family-repo.sh settle $repo, or read the build JOB NAME from gh api repos/$org/$repo/commits/main/check-runs --jq '[.check_runs[].name]|unique', then require it: printf '{\"required_status_checks\":{\"strict\":false,\"contexts\":[\"<job>\"]},\"enforce_admins\":false,\"required_pull_request_reviews\":null,\"restrictions\":null}' | gh api -X PUT repos/$org/$repo/branches/main/protection --input -" ;;
  esac

  # spec: SKILL.md "Acceptance on real 10.9" -- main requires the release.yml job that runs
  #       Mavergreen/mavericks-vm, by its check name: its name: if set, else its job id; for a job
  #       calling a local reusable workflow, "<caller> / <called job>", as GitHub names it.
  if ! gh api -H 'Accept: application/vnd.github.raw' "repos/$org/$repo/contents/.github/workflows/release.yml" > "$w/release.yml" 2>/dev/null \
     || [ ! -s "$w/release.yml" ] \
     || ! chk_py "$w/vm.py" "$org/$repo" "$w/release.yml" > "$w/vmjobs" 2>"$w/vm.err"; then
    chk_fail repo-requires-on-target "$org/$repo's main requires its 10.9 acceptance job" \
      "its release.yml's jobs could not be read ($(tr '\n' ' ' < "$w/vm.err" 2>/dev/null)), so whether main requires that job is unknown" \
      "check gh auth status, and that the repo's release.yml parses"
    continue
  fi
  while IFS= read -r vj; do
    [ -n "$vj" ] || continue
    case ",$ctx," in
      *",$vj,"*) ;;
      *) chk_fail repo-requires-on-target "$org/$repo's main requires its 10.9 acceptance job" \
           "main does not require $vj, so a PR can merge without its pkg passing on real 10.9" \
           "sh scripts/setup-family-repo.sh settle $repo, which requires it, or add $vj to main's required status checks" ;;
    esac
  done < "$w/vmjobs"
done

echo
if [ "$chk_status" -eq 0 ]; then
  echo "audit-repo-settings: ok — every repo is public, and every product repo can automerge a green bump and requires its 10.9 acceptance job"
fi
exit "$chk_status"
