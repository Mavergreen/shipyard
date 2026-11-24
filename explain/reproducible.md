reproducible: a release's content manifest leaves out the paths a reproducible deviation scopes, and a scope of * exempts the repo from the reproduce check.

## Why
Reproducible releases: a rebuild publishes only when what a user installs changed, judged by comparing
content-manifest.sh's rows with the previous release's CONTENT-MANIFEST.txt. Bytes a repo can't make
stable, such as an upstream binary that embeds its own build time, would make every rebuild look
changed, so a reproducible deviation removes those paths from the manifest, for the release decision and
the reproduce check alike.

## Incident
None recorded.

## Limits
A scope is matched against the path as installed, relative to / for a pkg and to the archive root for a
tarball, before the version is normalized. A removed path is invisible: a real change to it publishes
nothing until something else changes.

## Deviating
Write .mavergreen/deviations/reproducible/<label>/ with a scope (a shell case pattern of installed
paths, or * to exempt the whole repo from the reproduce check), a reason naming what can't be made
stable, and a revisit.

New in the flag day (P6, reproducible releases)
