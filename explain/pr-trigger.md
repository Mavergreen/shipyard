pr-trigger: release.yml builds pull requests to main, or a ci.yml does.

## Why
Renovate's automerge waits on a CI check (the preset defaults ignoreTests to false). With no build on the
bump pull request, the check never reports and the merge stalls forever, with nothing red. Give release.yml a
pull_request trigger on branches [main] (or push on every branch), or add a ci.yml that builds pull requests.
A repo with no build to gate sets "ignoreTests": true in .github/renovate.json, the one legitimate way out,
which shipyard itself uses. The publish decision stays guarded: a pull request must resolve release=no, so
adding the trigger without that guard would try to publish from a PR.

## Incident
None recorded. fd and rg each asserted this rule in a test of their own before the check existed (the
2026-10-14 hand-rolled-checks inventory).

## Limits
It reads the on: block as text. It accepts pull_request without a branches filter, or one that names main or
"**". It does not run the workflow or check that its jobs produce the context branch protection requires
(repo-required-context holds that).

## Deviating
Write "- pr-trigger: <reason>", or scope it with ".github/workflows/release.yml" as the glob. A good reason
says why no pull request needs a build here, and the exit; the cleaner answer is "ignoreTests": true.

New in the flag day (K6, hand-rolled in fd and rg)
