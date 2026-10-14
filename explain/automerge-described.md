automerge-described: a packageRules entry that touches automerge carries a description saying why.

## Why
The family default is ship-if-green: patch, minor and major automerge once the build passes, and breakage
that gets through is fixed forward in the next -mavericks.N. A restriction is legitimate only where a bad
bump would build fine and be wrong, which a green build cannot catch. Written down in the rule's
description, an exception is a decision; unexplained, it is indistinguishable from drift. The live example
is swift-toolchain, which gates minor and major Swift bumps because LLVM_BRANCH is swift/release/<minor> and
must follow, which no regex can infer. golang needs none: its Renovate cap on go-126 already stops a minor
that belongs to a new line.

## Incident
None recorded.

## Limits
It checks that a description exists and is not blank. It cannot check that the description gives a real
reason, or that the reason is the build-fine-and-be-wrong kind. It reads only .github/renovate.json, and
needs a python3 that can parse it.

## Deviating
No deviation is read for this id. Add a description to the rule that says what would build fine and be
wrong, or drop the rule and take the family default.

Formerly gate check 4b
