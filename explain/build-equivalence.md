build-equivalence: two builds of a product differ only where a deviation says why.

## Why
A product moving its build host (10.9 to modern macOS, or a Mac to Linux) proves the move with
build-equivalence.sh, which pairs two builds' files by path and reports each difference as bytes,
interface, meta, only-a or only-b. A build-equivalence deviation excuses bytes differences on the paths
its scope matches; one that excuses nothing in the comparison fails as unused, so a fixed cause forces
it out.

## Incident
Undated: vendored OpenSSL stamped "built on: <date>" into binaries, which build-equivalence reported as
bytes until the product's build exported SOURCE_DATE_EPOCH.

## Limits
Only build-equivalence.sh reads it, from the repo --repo names (default .). The scope is a shell case
pattern over the normalised path, with * crossing /. meta, only-a and only-b are never excusable.

## Deviating
Write .mavergreen/deviations/build-equivalence/<label>/ with a scope (<payload-path glob>), a reason and
a revisit. deviations.sh refuses a glob of only *, ? and /.

New in the flag day (from main's build-equivalence entries)
