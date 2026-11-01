arm64: a pkg ships an arm64 slice only where INGREDIENTS.md declares its install path arm64.

## Why
The family ships x86_64 by default; arm64 only with a reason. At package time every pkg Mach-O slice that
is arm64 or arm64e fails unless an "- arm64:<glob>: <reason>" deviation matches its install path. A
Sparkle updater bundle's slices are exempt, since the updater is built universal for every product; where
the registry derives the product's updater app, only that bundle is.

## Incident
None recorded. The rule follows the decision that arm64 ships only with a reason, with modern-smoke
running what is declared.

## Limits
It reads pkgs, not shipped tarballs. Failures are listed for the first twenty paths, then counted. A repo
grandfathered as modern-smoke, known from $GITHUB_REPOSITORY, is warned rather than failed, so a local run
without that variable fails its slices.

## Deviating
Write "- arm64:<install-path glob>: <who runs it on Apple Silicon, and why>". deviations.sh refuses a bare
form and a glob of only *, ? and /, which would declare the whole pkg universal.

Formerly conformance's arm64 rule
