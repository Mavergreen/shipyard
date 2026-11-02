renovate-suffix-versioning: a Renovate manager whose captured pin ends in -mavericks.N compares N.

## Why
Renovate's default versioning coerces the -mavericks.N suffix away, so .1 and .4 compare equal and the bot
proposes nothing: no pull request, no error, and the dashboard still lists the dependency as tracked. A
manager that tracks a sibling's -mavericks.N release needs "versioningTemplate": a regex: versioning that
captures major, minor, patch and build. The shared preset's legacysupport manager and the golang consumers
already do this. Renovate compiles matchStrings with the g flag alone, so ^ and $ are the ends of the whole
file, never of a line: a manager anchored with $ on a value file that carries a line-2 annotation captures
nothing, and the bot proposes nothing just the same. So a manager that captures no currentValue from a file
it matches fails too.

## Incident
swift-runtime's pin on swift-toolchain sat at 6.3.3-mavericks.1 through .2, .3 and .4, after its manager was
wired (undated in the conventions skill).

## Limits
It reads only .github/renovate.json, and needs a python3 that can parse it; tests/renovate-captures-test.sh
holds shipyard's own managers, and the preset's, to their files. It recognises a manager whose
captured pin ends in -mavericks.N by the shape of its match strings. A pin tracked some other way (a script,
a different file) is not seen.

## Deviating
No deviation is read for this id. Add the versioning template the message prints to that manager, or
match line 1 without an end anchor.

Formerly gate check 13
