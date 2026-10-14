compat-required-defined: a shipped binary defines every symbol MAVERICKS_REQUIRE_DEFINED_SYMBOLS names.

## Why
It is the opposite assertion to compat-imports: "this symbol must be defined in the binary". It is meant only
for a product that deliberately uses a post-10.9 API and links a 10.9 backport shim that defines it: golang
uses clock_gettime and links macports-legacy-support, so it sets '_clock_gettime' to prove the shim got
linked. A port that builds against the 10.9 SDK and takes the 10.9 fallback (openssh uses gettimeofday)
links no shim and must leave the list empty. The check runs only when the list is non-empty.

## Incident
None recorded. The conventions skill warns that copying golang's value into a repo with no shim makes the
guard demand a shim that is not there, so every binary fails "required symbol not DEFINED".

## Limits
It checks that nm shows the symbol defined. It does not check that the definition is the shim's rather than
another library's.

## Deviating
A "- compat-required-defined:<glob>: <reason>. Revisit when <exit>." line in
INGREDIENTS.md excuses this id for the binaries whose path the glob matches: under shipyard-check --dist, the
path inside the pkg or tarball (usr/local/mavergreen/<product>/...). That is how one binary in a dist keeps
the allowance its CMake target passes in a knob, since --dist applies one environment to every binary. Decide
the value from your build (do you link a legacy-support shim?), not from golang's template; leave it empty
when you do not.

Formerly the compat guard's required-defined rule
