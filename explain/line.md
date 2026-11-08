line: a lined product's manifest, version and repo agree about the line.

## Why
A lined product's line lives in .mavergreen/products/<short>/line, dotted as upstream spells it (1.27, 22),
and the manifest's line is a copy of it, minus any -cross until variants are settled. The version is the
line or starts with the line and a dot: 1.26.8 is line 1.26, 22.1.1 is line 22. A line repo's numeric
suffix is the line with its dots removed (golang-126, clang-22), and a product of a line repo must declare
its line. Without this agreement two lines could share a bare-name selection or an updater, and a line
repo could release another line's version.

## Incident
None recorded.

## Limits
It reads the product's line back from its derived name. A product this repo does not declare is held only
to its manifest's line, its version and its repo. With no repo known (no GITHUB_REPOSITORY and no GitHub
origin) the repo is not compared. It does not check the repo's Renovate cap or that the
bare names are selected correctly, which the helper's tests cover.

## Deviating
Write .mavergreen/deviations/line/<label>/ with a scope (<pkg file glob>), a reason and a revisit. A good reason says why the version and the line differ (an
upstream that renumbered).

Formerly the conformance rule line
