build-equivalence-interface: two builds of a product differ in a Mach-O interface only where a deviation says why.

## Why
build-equivalence.sh compares a Mach-O or archive at two levels: bytes, and its interface (exports,
imports, linked dylibs, install name, rpaths, deployment target, SDK and section names, through the
pinned clang22's readers). A build-equivalence-interface deviation excuses interface differences, and
bytes, on the paths its scope matches; one that excuses nothing fails as unused.

## Incident
None recorded.

## Limits
A broad glob excuses every interface change under it, so name the files it means. Crate hashes,
_rust_metadata_ hashes, _anon. hashes and .llvm.N suffixes are normalised before comparing.

## Deviating
Write .mavergreen/deviations/build-equivalence-interface/<label>/ with a scope (<payload-path glob>), a
reason and a revisit. deviations.sh refuses a glob of only *, ? and /.

New in the flag day (from main's build-equivalence entries)
