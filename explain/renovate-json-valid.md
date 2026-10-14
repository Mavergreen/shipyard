renovate-json-valid: .github/renovate.json parses as JSON.

## Why
Renovate ignores a config it cannot parse, so the repo silently stops getting updates, with no failing
check to say so. python3 -m json.tool .github/renovate.json shows where the syntax is wrong. The other
Renovate ids read the parsed file, so they skip a config that does not parse and leave this one to report it.

## Incident
None recorded.

## Limits
It checks syntax, not that Renovate accepts the keys. It needs the python3 id satisfied, and a missing
python3 is reported once, by that id, not here.

## Deviating
No deviation is read for this id. Fix the syntax.

New in the flag day (K6, hand-rolled in ca-certs, ed25519, container-tools, porthole and recaulk)
