renovate-suffix-versioning: a pin whose line 1 ends in -mavericks.N has a line 2 whose versioning compares N.

## Why
Renovate's default versioning coerces the -mavericks.N suffix away, so .1 and .4 compare equal and the bot
proposes nothing: no pull request, no error, and the dashboard still lists the dependency as tracked. The
shared preset's one manager takes a pin's versioning from its line 2, so a VERSION, or a PIN's ref, that
ends in -mavericks.N needs " versioning=regex:..." there, capturing major, minor, patch and build. The
manager reads line 2 only as '# renovate: datasource=... depName=...[ versioning=...][ extractVersion=...]',
keys in that order and no others, and tracks nothing from any other annotation; so a line 2 it cannot read
fails too.

## Incident
swift-runtime's pin on swift-toolchain sat at 6.3.3-mavericks.1 through .2, .3 and .4, after its manager was
wired (undated in the conventions skill).

## Limits
It reads the tracked .mavergreen/upstream/ and .mavergreen/ingredients/<name>/ VERSION, PIN and COMMIT
files, and needs python3. A COMMIT has no version to compare. A pin tracked some other way (a repo's own
customManagers, a built-in manager) is not seen; tests/renovate_preset.sh and
tests/renovate-captures-test.sh hold the preset's manager to the line-2 grammar this check reads.

## Deviating
No deviation is read for this id. Add the versioning the message prints to that line 2, or rewrite line 2
in the order the message gives.

Formerly gate check 13
