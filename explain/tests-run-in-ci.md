tests-run-in-ci: when tests/ holds test files, some workflow runs them.

## Why
A suite nobody runs rots without a sign. Hand-listing test files in CI is how a new file lands and never
runs. The family's runner, run-repo-tests.sh, runs every top-level tests/*.sh and tests/*.bats, so a new
test runs the day it lands. The check asks for the runner (or ctest, where ctest is the driver) on a
non-comment line of some workflow, so a commented-out line does not count as wired.

## Incident
macports-legacy-support had nine test files that CI never ran. Two had rotted: one asserted Renovate's
pre-migration fileMatch key, the other an .icns filename that changed when the repo was renamed. Neither
was a product bug; both were invisible because nothing ran them (undated in the conventions skill).

## Limits
It asks whether a workflow names the runner, not whether the job that names it runs on pull requests, or
whether it passes. A job that mentions run-repo-tests.sh in an echo satisfies it. Tests in a directory
other than top-level tests/ are not counted as tests.

## Deviating
No deviation is read for this id. Wire the runner in: sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh" (add the
ctest preset name if ctest is the driver). A test that cannot run in CI exits 77 and says why, rather than
being left out.

Formerly gate check 2
