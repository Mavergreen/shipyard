variant-build-info: variants of one release agree about what they were built from.

## Why
Artifacts cannot answer the question. golang's native pkg carries the CA bundle and the legacy-support shim;
its cross pkg legitimately does not. "Both variants used the same shim" is a claim about inputs, which no
payload inspection can settle, so the build writes it down: sh "$SHIPYARD_SCRIPTS/build-info.sh"
dist/build-info-<variant>.txt key=value ..., shipped as a release asset. Conformance compares any key
appearing in more than one variant, except those that are supposed to differ (variant, arch, prefix, pkg,
identifier). It also means a user can read what a release was made from.

## Incident
None recorded.

## Limits
Only keys present in two or more build-info files are compared, so a key one variant forgot to write is not
a disagreement. It trusts what the build wrote down.

## Deviating
Write "- variant-build-info: <reason>", for the whole release (the check passes no subject). The old name
"ingredients" is still read. A good reason says which input legitimately differs between variants, and the
exit.

Formerly the conformance rule ingredients
