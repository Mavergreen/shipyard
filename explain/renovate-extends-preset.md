renovate-extends-preset: .github/renovate.json extends github>Mavergreen/shipyard.

## Why
The preset carries the family's automerge and ignoreTests defaults and its managers. A config that does not
extend it gets none of them, and a repo with no config at all gets nothing. Add .github/renovate.json with
an extends list naming the preset. The name may be followed by a # ref or a : part and still counts.

## Incident
None recorded. ca-certs, ed25519 and recaulk each asserted this in
a test of their own (the 2026-10-14 inventory).

## Limits
It checks the extends list of the one config renovate-path allows. It does not check that the repo's other
settings are compatible with the preset. If the file cannot be parsed, renovate-json-valid reports that and
this one stays silent.

## Deviating
Write "- renovate-extends-preset: <reason>", or scope it to ".github/renovate.json". A good reason says why
the repo cannot take the preset's defaults, and the exit.

New in the flag day (K6, hand-rolled in ca-certs, ed25519 and recaulk)
