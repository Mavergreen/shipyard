requires-pinned: every requirement but an external one names an ingredient of this repo whose product is that requirement.

## Why
The Engine installs, and CI builds and tests against, the one release of a dependency this product was made
with. That release is the pin of the ingredient of the same name, and the ingredient's product file says
which family product the pin is a release of. A requirement with no such ingredient has no pin, so nothing
says which release to install or test with; one whose ingredient names another product pins the wrong thing.
An external requirement is never installed by the Engine and needs no pin.

## Incident
None recorded.

## Limits
This is dependencies rule R1. It compares names in this repo only: whether the product exists in the family,
and whether its release at the pin exists, need the catalog.

## Deviating
No deviation is read for this id. Add .mavergreen/ingredients/<dep>/ with its pin and a product file naming
<dep>, or make the requirement external with a where.

New in the flag day (P2, dependencies rule R1)
