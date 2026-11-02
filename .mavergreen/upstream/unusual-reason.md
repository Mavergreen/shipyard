This repo is consumed through a **moving** tag. Fifteen repos pin `@v1`, so anything merged here reaches
all of them within minutes — which is why the version is derived from the commit count (see
`scripts/shipyard-version.sh`) rather than bumped by hand.

shipyard itself carries no `## Declared state` section. Its version is
`<line>.<commit count>`, the line in `.mavergreen/upstream/VERSION`, so its own state changes
on every push, and every push already publishes by design. Adopting the digest path here would only
describe that status quo more slowly -- it is shipyard's declared exception, not a pattern to copy.
