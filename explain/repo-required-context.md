repo-required-context: main requires a status check, the PR build job.

## Why
Auto-merge is only armed when a required check is pending, so a main with no required check never merges a
green Renovate bump. Set strict:false (no forced rebases) and enforce_admins:false (maintainers keep direct
push). The context is the build job name, read from a real check-run, never by analogy: a typo requires a
check that never reports and blocks every merge, and a job that does not run on pull requests blocks every
pull request forever. shipyard's own release job is named build but its workflow is push-only, so the
PR-visible job there is test, from ci.yml. Read it with gh api repos/OWNER/REPO/commits/main/check-runs
--jq '[.check_runs[].name]|unique'.

## Incident
Same as repo-auto-merge: four repos created 2026-08-02 to 2026-08-04 had neither setting, and signal-desktop's
Signal 8.26.0 sat green and unmerged for a month.

## Limits
It checks that main requires some context; it does not check that the context is the right job, or that the
job runs on every pull request. GitHub treats a skipped required check as passed, so a required
job that is skipped on some commits can let auto-merge fire early.

## Deviating
No deviation is read for this id. Set the protection with the command in the conventions skill's Renovate
section, using the exact context string from a real check-run.

Formerly audit-repo-settings.sh
