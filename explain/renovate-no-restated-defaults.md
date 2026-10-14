renovate-no-restated-defaults: .github/renovate.json does not restate a key the shared preset already sets.

## Why
The preset (github>Mavergreen/shipyard) sets ignoreTests: false, so automerge waits for a green build. A
local copy of the same value looks harmless and silently stops tracking the preset the day the preset
changes. Overriding with a different value stays legal, since that is a decision and not a duplicate: a repo
with no build to gate sets ignoreTests: true, and shipyard itself does.

## Incident
None recorded.

## Limits
Today it knows one key, ignoreTests set to false. It matches the text of the file, not the parsed config,
and it does not compare packageRules or managers to the preset's. A restated value spelled some other way
(inside an extended local preset) is invisible to it.

## Deviating
No deviation is read for this id. Delete the key, or set it to a different value if that is the decision.
The repo that has no build gates sets "ignoreTests": true and explains why in its INGREDIENTS.md.

Formerly gate check 4
