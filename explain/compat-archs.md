compat-archs: a shipped binary holds exactly the architectures MAVERICKS_ALLOW_ARCHS names.

## Why
A product exists for Mavericks, so it ships x86_64 only by default. An arm64 slice is a deviation, warranted
only when the thing is used in CI or by developers to produce, test or investigate Mavericks artifacts: a
cross toolchain, cmake, shipyard's own updater, the static half of a reverse-engineering tool. A library
gets an arm64 slice only for a real arm64 consumer, never speculatively. The default set is "x86_64"; a
universal updater passes "x86_64 arm64". The set must match exactly, in both directions: a missing slice and
an extra one both fail.

## Incident
None recorded.

## Limits
It compares the arch set; it does not check that the arm64 slice has a declared reason in INGREDIENTS.md.
The spec lists "an arm64 slice needs an arm64 deviation" as a rule found unchecked, planned for the flag day.
A file that is not a readable Mach-O fails here.

## Deviating
A "- compat-archs:<glob>: <reason>. Revisit when <exit>." line in
INGREDIENTS.md excuses this id for the binaries whose path the glob matches: under shipyard-check --dist, the
path inside the pkg or tarball (usr/local/mavergreen/<product>/...). That is how one binary in a dist keeps
the allowance its CMake target passes in a knob, since --dist applies one environment to every binary. At build time, state
the set with MAVERICKS_ALLOW_ARCHS; a universal updater beside an x86_64 product is the usual case for a
scoped line. The "- arm64:<glob>: <reason>" form is P5's, and no check reads it yet.

Formerly the compat guard's arch set rule
