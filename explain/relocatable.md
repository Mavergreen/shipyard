relocatable: not a check but a deviation key: a relocatable deviation whose scope is an ingredient name (or *) says that ingredient cannot run from a cache.

## Why
shipyard-provision extracts a pinned family product from a pkg into a cache and prints that path. A
product that embeds its build prefix does not work from there. With a relocatable deviation naming it,
shipyard-provision stops ("deviation relocatable") unless the installed copy holds the pinned version or
--install installs the pkg at its real prefix.

## Incident
None recorded.

## Limits
Only shipyard-provision reads it, and only as the consumer's tree declares it: a product's own repo cannot
declare it for its consumers. The scope is an ingredient name, as in .mavergreen/ingredients/<name>/, or *
for every ingredient. It does not make the product relocatable.

## Deviating
Write .mavergreen/deviations/relocatable/<label>/ with a scope (<ingredient name> or *), a reason and a revisit. A good reason names what the product embeds (a prefix, an absolute rpath); a good revisit is the release that no longer does.

New in the flag day (P2, with shipyard-provision)
