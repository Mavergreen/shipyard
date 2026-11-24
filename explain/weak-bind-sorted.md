weak-bind-sorted: every shipped linked Mach-O slice lists its weak-bind info in name order.

## Why
10.9's dyld merges weak symbols across a program and its dylibs on the assumption that each image's
weak-bind info is sorted by symbol name, as Apple's ld64 writes it. ld64.lld wrote it in address order,
so weak symbols such as a header class's type_info stayed duplicated, and dynamic_cast, exception catches
and typeid comparisons failed across images. artifact-facts.sh reads each linked slice with
llvm-objdump --macho --weak-bind and reports the first symbol out of byte order.

## Incident
2026-10-19: measured on 10.9.5, lld-linked images left weak symbols uncoalesced. clang22
22.1.8-mavericks.5 carries the lld patch that writes the info in name order.

## Limits
Only the order of the info is read, not whether dyld coalesced anything. An image with no weak-bind info
passes, and so does one using chained fixups, which 10.9 cannot load anyway.

## Deviating
Write .mavergreen/deviations/weak-bind-sorted/<label>/ with a scope (<path glob>), a reason and a revisit;
its exit is the image rebuilt on clang22 22.1.8-mavericks.5 or later.

New in the flag day (P6, link facts)
