identifier: a pkg's identifier is inside dev.mavergreen.*.

## Why
An identifier that is not ours collides with someone else's. The pkg identifier is what Installer keys its
receipt on, and what the registry (scripts/product-names) derives the updater, the feed and the manifest
from, so it is registered once, family-wide. The 2026-09-22 flag day moved every identifier from
dev.modernmavericks.* to dev.mavergreen.*, with no code to retire the old names from existing installs,
because there were none to protect.

## Incident
None recorded. The collision behind the family's identity rules is tailscale's
(see launchd-label).

## Limits
It reads the identifier recorded in each pkg and in its components. It cannot tell whether a pkg named
under dev.mavergreen.* is registered to this product, which the manifest check holds.

## Deviating
Write "- identifier:<pkg file glob>: <reason>". A good reason says whose identifier the pkg must keep (an
upstream's, shipped unmodified) and the exit.

Formerly the conformance rule identifier
