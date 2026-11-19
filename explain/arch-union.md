arch-union: a file in only one of the two trees lipo-merge-tree.sh merges is declared in the product's union file.

## Why
Architectures A5: the x86_64 and arm64 builds of one product are two slices of one thing, so a file only
one of them produces is either a build difference nobody meant or a file that ships from one arch by
design. The product's .mavergreen/products/<short>/union lists globs, relative to its install tree, for the
latter; the merge copies each such entry from its own side. An undeclared one-sided file, and a glob that
matches no one-sided entry, fail the merge and remove OUT.

## Incident
2026-10-14: clang22's cross build had 160 files the native build lacked (architectures survey §3)

## Limits
Only lipo-merge-tree.sh judges it, so a merge done another way is not judged.

## Deviating
No deviation is read; the product's .mavergreen/products/<short>/union declares the one-sided files.

New in the flag day (P5, architectures A5)
