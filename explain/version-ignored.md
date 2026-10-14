version-ignored: .gitignore has a line ignoring /VERSION.

## Why
VERSION is written by every build, and the first git add -A would commit it. no-tracked-version only catches
it once it is committed; this keeps it from being committed at all.

## Incident
None recorded.

## Limits
It looks for a line that is exactly /VERSION or VERSION in .gitignore. A pattern that covers it indirectly
(a parent directory's, a wildcard) does not count.

## Deviating
No deviation is read for this id. Add a line /VERSION to .gitignore.

New in the flag day (K6, hand-rolled in packer-plugin-macosx and recaulk)
