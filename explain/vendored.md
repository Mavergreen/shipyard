vendored: every tracked path under a vendor/ or third_party/ directory is covered by a vendored deviation.

## Why
A vendored copy is code the family does not build, and an undeclared one is code nobody counts. Each is
declared, with a reason that says what deletes the copy. Any tracked path under a directory named vendor or
third_party fails, once per vendored entry (the first path component below the directory), until a
"vendored" deviation whose glob covers it exists. The fixtures under tests/fixtures/checks are excluded, like
every other check's.

## Incident
None recorded. Ruling R11 of the flag-day ledger (2026-10-14): shipyard's PyYAML entry must not become prose,
and the exit condition is stated explicitly.

## Limits
It sees directories by name only. A copy kept under any other name (deps/, lib/) is invisible. It does not
check that the exit has happened, only that one is written.

## Deviating
Write .mavergreen/deviations/vendored/<label>/ with a scope (<glob>), a reason and a revisit. shipyard's own has the scope scripts/vendor/yaml/** and the reason
"PyYAML is vendored because python-315's phase 1 has no ssl, so pip cannot fetch it on 10.9", revisiting when
python-315 ships ssl and pip works, when the vendored copy is deleted. Files that maintain the copy (the pin,
checksum and sync script) are listed too, each saying it goes when the copy does. A good revisit names the
condition that deletes the copy.

New in the flag day (ruling R11)
