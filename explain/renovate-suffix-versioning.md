renovate-suffix-versioning: a Renovate manager whose captured pin ends in -mavericks.N compares N.

## Why
Renovate's default versioning coerces the -mavericks.N suffix away, so .1 and .4 compare equal and the bot
proposes nothing: no pull request, no error, and the dashboard still lists the dependency as tracked. A
manager that tracks a sibling's -mavericks.N release needs "versioningTemplate": a regex: versioning that
captures major, minor, patch and build. The shared preset's legacysupport manager and the golang consumers
already do this.

## Incident
swift-runtime's pin on swift-toolchain sat at 6.3.3-mavericks.1 through .2, .3 and .4, after its manager was
wired (undated in the conventions skill).

## Limits
It reads only .github/renovate.json, and needs a python3 that can parse it. It recognises a manager whose
captured pin ends in -mavericks.N by the shape of its match strings. A pin tracked some other way (a script,
a different file) is not seen.

## Deviating
No deviation is read for this id. Add the versioning template the message prints to that manager.

Formerly gate check 13
