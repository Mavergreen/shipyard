modern-smoke: release.yml runs the arm64 slice before it ships, exactly when the repo declares one.

## Why
An arm64 slice is a deviation (x86_64 by default; arm64 only with a reason), and one shipped untested runs
first on a developer's Apple Silicon Mac. So release.yml has a job named modern-smoke, on a macos-*
runner, that the publish job (the one calling publish-release.yml, else publish) lists in needs:, exactly
when INGREDIENTS.md declares "- arm64:<glob>: <reason>". The job is that slice's on-target acceptance, as
on-target's is the x86_64 slice's on 10.9. A declaration with no job and a job with no declaration fail
with different messages.

## Incident
None recorded. The rule follows the decision that arm64 ships only with a reason.

## Limits
It reads that the job exists, where it runs and that publish needs it, not what it runs. The modern-smoke
job also needs its own macos-runner declaration. A repo in scripts/conventions-grandfathered as
modern-smoke skips this check, and the arm64 id warns about its slices instead of failing them.

## Deviating
No deviation is read for this id: the arm64 declaration is what it holds the job to. Declare
"- arm64:<install-path glob>: <reason>" and add the job, or ship x86_64 only and remove both.

Formerly gate check 37
