version: every artifact names the version the release claims.

## Why
A release whose pkg, appcast, checksums and tag disagree is incoherent however it was built. Every piece was
already checked in isolation (the compat guard reads binaries, set_install_floor stamps a floor, sign_and_appcast
signs, publish-release checksums), and nothing asserted they agree with each other. This check compares the
version each pkg and each appcast reports to the one the release claims, SHIPYARD_CHECK_VERSION. It also
catches a stale pkg left in dist/ from an earlier build.

## Incident
None recorded.

## Limits
It compares the strings the artifacts carry. It does not check that the version is the right next one, which
is feed-upgradeable's concern for the appcast, and a pkg that embeds the wrong version in a place the facts
producer does not read is not seen.

## Deviating
Write "- version:<file glob>: <reason>", scoped to the artifact's file name; an unscoped line excuses every
artifact. Scoping is the point: swift-toolchain republishing swift.org's pkg must not license the
build-support tarball it does build to drift. A good reason says whose version the artifact carries and why
it cannot match, with the exit.

Formerly the conformance rule version
