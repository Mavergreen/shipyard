from-parent: an ingredient with a from names self, or another ingredient here that has a product, and pins nothing of its own.

## Why
A from ingredient is published by its parent's release (libcxx22 by clang22's), or by this run's own build
(self). Its version is its parent's, so a VERSION or PIN of its own could disagree with it. Its parent must be
an ingredient of this repo, so that the version exists here at all, and must name the family product it
comes from in product, since only a family release can carry the from ingredient beside it.

## Incident
None recorded.

## Limits
This is the local half of dependencies rule R3. Whether the parent's release really publishes this product
needs the catalog, and is checked in P8. A repo with no ingredient directories reports it not run.

## Deviating
No deviation is read for this id. Name an ingredient with a product, or self, in from, and delete any
VERSION or PIN beside it.

New in the flag day (P2, the local half of dependencies rule R3)
