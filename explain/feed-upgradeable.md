feed-upgradeable: a release's appcast will be seen as an upgrade by a client running the previous release.

## Why
Sparkle's SUStandardVersionComparator totally orders only X.Y.Z.N and reads the -mavericks.N suffix, or any
stray letter, as equal, so a same-upstream repackage would be invisible to auto-update ("you're up to
date"). The human string stays in shortVersionString; the compared <sparkle:version> is derived to a
numeric-only form by gen_appcast.sh and MavericksSparkle.cmake, which must stay identical. The derivation:
-mavericks.N becomes .N; a monotonic in-version patch letter becomes a dot (OpenSSH-portable's 9.9p2 becomes
9.9.2, order-preserving); the result must be purely dotted-numeric or the step fails closed. A non-monotonic
prerelease suffix (-rc1) must not be dot-joined, since 1.2.3rc1 to 1.2.3.1 would sort above 1.2.3. This
check proves the version is dotted-numeric and strictly greater than the previous published release's, by the
comparator's own component-wise comparison (lib.sh's ver_cmp, not sort -V).

## Incident
None recorded.

## Limits
It runs where the release tags live, in the release job's checkout. With no previous tag (a first release)
the ordering is skipped, and says so; it never passes silently. If tags cannot be listed at all it fails.
--tag-glob and --upstream-glob scope the previous tag for a repo that tags otherwise (shipyard's v*.*.*).

## Deviating
No deviation is read for this id. A new non-numeric upstream shape gets its transform in the shared
derivation, in both files identically, never in a product's build.

Formerly assert_appcast_upgradeable.sh
