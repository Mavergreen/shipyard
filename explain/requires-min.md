requires-min: a library requirement states its min, and every min is at or below the pin of its ingredient.

## Why
A library's min is its ABI floor: the lowest release the product's binaries still load against. It is what
the preinstall refuses below, so a library states it rather than defaulting to the build pin, which would
refuse every older release that works. A min above the pin would refuse the very release the product was
built and tested with. A min the family comparator cannot order with the pin (an -rc1, a v prefix) could
hold either way, so it fails rather than pass unproven.

## Incident
None recorded.

## Limits
This is dependencies rule R2 and decision 3. It compares with the comparator generated preinstalls carry,
mavergreen_vercmp in scripts/lib/vercmp.sh. The pin is the ingredient's VERSION, its parent's VERSION for a
from ingredient, or the ref of its PIN. A min with no ingredient beside it (an external requirement's) is not
compared. Whether the min is the true floor is not checked.

## Deviating
No deviation is read for this id. Write the lowest working release in min, at or below the pin, in a form
the comparator orders.

New in the flag day (P2, dependencies rule R2 and decision 3)
