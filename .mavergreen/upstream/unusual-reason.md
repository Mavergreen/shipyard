This repo is consumed through a **moving** tag. Fifteen repos pin `@v1`, so anything merged here reaches
all of them within minutes — which is why the version is derived from the commit count (see
`scripts/shipyard-version.sh`) rather than bumped by hand.

Its version is `<line>.<commit count>`, the line in `.mavergreen/upstream/VERSION`, so every push to
`main` is a new version, and every push publishes by design, even when its content manifest matches the
last release's: the `publish-unchanged` deviation says why. That is shipyard's declared exception, not a
pattern to copy.
