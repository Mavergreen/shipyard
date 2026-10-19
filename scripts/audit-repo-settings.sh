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
org="${1:-Mavergreen}"
command -v gh >/dev/null 2>&1 || { echo "audit-repo-settings: needs the gh CLI" >&2; exit 1; }

bad=0
printf '%-28s %-10s %-10s %s\n' REPO VISIBILITY AUTO-MERGE 'REQUIRED CHECKS ON main'
for repo in $(gh repo list "$org" --limit 100 --json name --jq '.[].name' | sort); do
  am="$(gh api "repos/$org/$repo" --jq '.allow_auto_merge' 2>/dev/null || echo '?')"
  vis="$(gh api "repos/$org/$repo" --jq '.visibility' 2>/dev/null || echo '?')"
  [ "$vis" = public ] || bad=$((bad + 1))

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
  [ "$am" = true ] || { bad=$((bad + 1)); }
  case "$ctx" in NONE*) bad=$((bad + 1)) ;; esac

  # spec: SKILL.md "Acceptance on real 10.9" -- main requires the release.yml job that runs
  #       Mavergreen/mavericks-vm, by its check name: its name: if set, else its job id; for a job
  #       calling a local reusable workflow, "<caller> / <called job>", as GitHub names it.
  if ! relyml="$(gh api -H 'Accept: application/vnd.github.raw' "repos/$org/$repo/contents/.github/workflows/release.yml" 2>/dev/null)" \
     || [ -z "$relyml" ] \
     || ! vmjobs="$(printf '%s\n' "$relyml" | python3 -c '
import subprocess, sys, yaml
def jobs_of(wf):
    j = wf.get("jobs") if isinstance(wf, dict) else None
    return [(k, b) for k, b in j.items() if isinstance(b, dict)] if isinstance(j, dict) else []
def runs_vm(b):
    return any(isinstance(st, dict) and isinstance(st.get("uses"), str)
               and st["uses"].lower().startswith("mavergreen/mavericks-vm@")
               for st in (b.get("steps") or []))
for j, b in jobs_of(yaml.safe_load(sys.stdin) or {}):
    if runs_vm(b):
        print(b.get("name") or j)
    elif isinstance(b.get("uses"), str) and b["uses"].startswith("./.github/workflows/"):
        called = subprocess.run(["gh", "api", "-H", "Accept: application/vnd.github.raw",
                                 "repos/%s/contents/%s" % (sys.argv[1], b["uses"][2:])],
                                capture_output=True, text=True, check=True).stdout
        for cj, cb in jobs_of(yaml.safe_load(called) or {}):
            if runs_vm(cb):
                print("%s / %s" % (b.get("name") or j, cb.get("name") or cj))
' "$org/$repo")"; then
    printf '%-28s %s\n' '' "-> cannot read release.yml's jobs (needs gh, and python3 with PyYAML)"
    bad=$((bad + 1)); continue
  fi
  [ -n "$vmjobs" ] || continue
  while IFS= read -r vj; do
    case ",$ctx," in
      *",$vj,"*) ;;
      *) printf '%-28s %s\n' '' "-> main does not require $vj, its 10.9 acceptance job"; bad=$((bad + 1)) ;;
    esac
  done <<EOF
$vmjobs
EOF
done

echo
if [ "$bad" -eq 0 ]; then
  echo "audit-repo-settings: ok — every repo is public, and every product repo can automerge a green bump and requires its 10.9 acceptance job"
  exit 0
fi
echo "audit-repo-settings: $bad setting(s) keep org secrets from a private repo, would stop a green Renovate bump from merging, or let a PR merge without its 10.9 acceptance job" >&2
echo "    fix: sh scripts/setup-family-repo.sh settle <repo>   (writes every family repo setting, idempotently)" >&2
echo "    or by hand: gh api -X PATCH repos/$org/<repo> -F allow_auto_merge=true" >&2
echo "    fix: printf '{\"required_status_checks\":{\"strict\":false,\"contexts\":[\"<job>\"]},\"enforce_admins\":false,\"required_pull_request_reviews\":null,\"restrictions\":null}' | gh api -X PUT repos/$org/<repo>/branches/main/protection --input -" >&2
echo "    the context is the build JOB NAME; read it from a real run first:" >&2
echo "    gh api repos/$org/<repo>/commits/main/check-runs --jq '[.check_runs[].name]|unique'" >&2
exit 1
