no-standalone: a release that ships a product's pkg ships its standalone archive beside it.

## Why
A user who cannot or will not run the installer still gets the product: the release carries
<short>-<version>-macos-<universal|x86_64|arm64>.tar.gz for every product a pkg installs, built with
stage_standalone.sh. Without it, the product exists only for those who install it at its prefix.

## Incident
None recorded.

## Limits
A product in scripts/conventions-grandfathered as "standalone <repo> <short>", the repo known from
$GITHUB_REPOSITORY, is warned rather than failed. A deviation for a product whose archive the release
carries anyway fails, so the declaration cannot outlive its reason.

## Deviating
Write .mavergreen/deviations/no-standalone/<label>/ with a scope (the product's short name), a reason
saying why a standalone form is meaningless for it, and a revisit.

Formerly conformance's no-standalone rule
