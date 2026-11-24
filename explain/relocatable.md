relocatable: not a check but a deviation key: a product's own relocatable deviation (scope: its short name, or a glob other than *) says it cannot run from a cache, and its release manifest tells every consumer.

## Why
shipyard-provision extracts a pinned family product from a pkg into a cache and prints that path. A
product that embeds its build prefix does not work from there. The product's own repo declares a
relocatable deviation; release-manifest.sh then writes `relocatable <short>` into the RELEASE-MANIFEST.txt
it publishes, and shipyard-provision reads the pinned release's manifest (dep-manifest.sh) and stops
("its release manifest says relocatable") unless the installed copy holds the pinned version or --install
installs the pkg at its real prefix.

## Incident
None recorded. Consumers each declared their own copy of the same fact, and a new consumer learned it by
failing.

## Limits
A pin whose release predates manifests (a -mavericks.N or an own-upstream release from before the flag day)
falls back to the consumer's own relocatable deviation, scoped to the ingredient name, until L1 re-pins
every ingredient. An unreadable manifest of any other pin stops the run. It does not make the product
relocatable.

## Deviating
Write .mavergreen/deviations/relocatable/<label>/ in the product's own repo with a scope (<short>, or a glob
naming several), a reason and a revisit. A scope of * is read only as a consumer's, for every ingredient,
until L1; release-manifest.sh never publishes it, so a repo that is both consumer and producer does not
mark every one of its products relocatable by an old consumer deviation. A good reason names what the product embeds (a prefix, an absolute rpath); a good
revisit is the release that no longer does.

New in the flag day (P2, with shipyard-provision; read from the dependency's manifest in P6)
