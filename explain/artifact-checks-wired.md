artifact-checks-wired: a repo that builds a .pkg runs shipyard-check --dist in some workflow.

## Why
The identity and install-path rules live in the artifact checks, so a product that never calls them is
exempt from all of them by omission. Four products were, when those rules landed. A repo builds a .pkg if
it has a tracked, non-test pkgbuild or productbuild call, or a workflow that runs sign_and_appcast.sh. The
family's reusable workflows call shipyard-check --dist dist in the release job, so nothing needs hand-wiring
per repo.

## Incident
Undated in the conventions skill: four products were exempt from the identity and install-path rules when
they landed, for want of this check.

## Limits
It asks whether a workflow mentions shipyard-check --dist on a non-comment line. It does not check that the
job runs on a release, that SHIPYARD_CHECK_VERSION is set, or that the dist directory is the right one.

## Deviating
Write "- artifact-checks-wired: <reason>", for the whole repo. A good reason says why no artifact check can
apply (it builds a pkg only as a test fixture), and the exit.

Formerly gate check 21
