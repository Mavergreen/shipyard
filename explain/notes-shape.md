notes-shape: the release body is the family shape: a title naming this exact version, a "### What changed", no empty section, a non-empty body.

## Why
The shape is small on purpose, since it has to pass for every product from a Go toolchain to a kext: it
asserts only what a reader is entitled to, that the release says which version it is and what changed. The
generator self-checks what it wrote with this, and publish-release.yml checks it again at release time,
structurally: the call carries no fallback (no ||, &&, ;, pipe) and no set +e precedes it, so "|| true" or
wrapping the call is caught like an outright missing call. A leading v is not part of the version (shipyard
tags v1.0.209 but its title reads ## Shipyard 1.0.209). This is the publisher layer of three: the gate asks
whether release.yml is wired to the generator (release-notes-generated), this asks whether the body about to
ship has the shape, and conformance's notes asks whether the appcast agrees.

## Incident
Undated in the conventions skill: six products published "Automated release for Mac OS X 10.9 (Mavericks)."
as their entire notes, for every release, including Renovate repackages whose only reason to exist was an
ingredient bump. That body passes no check here.

## Limits
It checks the shape, not the truth: it cannot tell that a compare link is the right one or that the prose is
good. A sentence a hand-writer copies from the generator's shape would pass.

## Deviating
No deviation is read for this id. Generate the body with release-notes.sh and publish exactly that file.

Formerly check-release-notes.sh
