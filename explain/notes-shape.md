notes-shape: the release body is the family shape: the derived heading, a "Release <tag>" line, a "### What changed", no empty section, a non-empty body.

## Why
The shape is small on purpose, since it has to pass for every product from a Go toolchain to a kext: it
asserts only what a reader is entitled to, that the release says which version it is and what changed. Line 1
must equal the derived heading, "## <noun> <version>", from .mavergreen/products/<short>/noun (a leading v and any
-mavergreen.N suffix are dropped from the version); line 2 must be "Release <tag>", optionally followed by
" · Requires Mac OS X <x> or later" (U+00B7, one space each side). A hand-chosen noun, a parenthesised version or
"for Mavericks" fails. The
generator self-checks what it wrote with this, and publish-release.yml checks it again at release time,
structurally: the call carries no fallback (no ||, &&, ;, pipe) and no set +e precedes it, so "|| true" or
wrapping the call is caught like an outright missing call. publish-release.yml fetches the noun and line at the
release commit (its required short input) and names the Release from the same derivation. This is the publisher layer of three: the gate asks
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
