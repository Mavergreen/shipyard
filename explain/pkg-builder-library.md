pkg-builder-library: a repo that holds pkg-building code for others, and publishes no pkg, is not judged as a pkg publisher.

## Why
artifact-checks-wired and on-target judge the repo that publishes a pkg. A build-chain library
(golang-port) holds scripts that build a pkg in the repo that pins it, and its own release is a tarball.
A pkg-builder-library deviation spares it those checks, and artifact-checks-wired refuses the deviation
once any workflow names a .pkg, signs an appcast, or runs a file that builds a pkg or, through any chain
of scripts naming each other, calls one.

## Incident
Undated: golang-port failed the pkg-publisher checks for the pkg golang-127 builds with its scripts.

## Limits
What a release uploads is filled by scripts and cannot be read statically, so the refusal reads the
workflows and the scripts they reach.

## Deviating
Write .mavergreen/deviations/pkg-builder-library/<label>/ with a scope of *, a reason naming the repos
that build the pkg, and a revisit.

New in the flag day (from main's pkg-builder-library)
