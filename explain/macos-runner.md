macos-runner: every job on a macos-* runner declares why it needs macOS.

## Why
macOS runners are scarce, and a job lands on one by default. Every job in .github/workflows/*.yml whose
runs-on names a macos-* runner, as a string, a list, or ${{ matrix.X }} read through the job's matrix,
is grandfathered or declared, so each one is counted and the count can only go down.

## Incident
2026-10-18: the maintainer recorded that the family has no self-hosted runner and rate-limits itself on
macOS runners instead, moving portable jobs to ubuntu-latest.

## Limits
It reads runs-on and the job's matrix, not a reusable workflow's jobs, which the called file's own entry
covers. A runs-on built from another expression is read as text. A job in
scripts/conventions-grandfathered for this repo is excused until its line is deleted.

## Deviating
Write "- macos-runner:<workflow file>:<job>: <why it needs macOS, and its exit>" (ci.yml:build). The key
names one job of one file, so a new build job in another workflow is still caught; deviations.sh refuses a
wildcard. A good reason says what in the job needs macOS and what would let it move to Linux.

Formerly gate check 36
