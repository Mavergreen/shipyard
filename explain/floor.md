floor: a product archive declares an install floor of 10.9.5, and a component package an appcast that declares its minimum.

## Why
Structure matters. A product archive (Distribution) declares an install floor; a component package
(PackageInfo) cannot, since floors are a productbuild concept, so its minimum lives in the appcast
instead. golang's cross product targets 10.9 but runs on 11.0 and later, so demanding 10.9.5 of it would be
wrong; its own appcast says 11.0. The release notes' floor line describes the native pkg while each appcast
enforces its own artifact's real minimum, and the two are allowed to disagree on purpose.

## Incident
None recorded.

## Limits
It reads the floor the pkg's Distribution declares and the minimum system version in the appcast. It does not
install anything, so it cannot say that the product really runs at the stated floor. That is the compat
guard's job and the on-target run's.

## Deviating
Write "- floor:<pkg or appcast file glob>: <reason>". A good reason says what the artifact's real minimum is
and why it differs from 10.9.5, and the exit. A floor below 10.9 is a different decision (QUEUE #42).

Formerly the conformance rule floor
