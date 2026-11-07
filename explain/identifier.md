identifier: a pkg's identifier is inside dev.mavergreen.*.

## Why
An identifier that is not ours collides with someone else's. The pkg identifier is what Installer keys its
receipt on. It is dev.mavergreen.<short>, derived from the product's short name, and the updater, the feed
and the manifest are derived from it. The 2026-09-22 flag day moved every identifier from
dev.modernmavericks.* to dev.mavergreen.*, with no code to retire the old names from existing installs,
because there were none to protect.

## Incident
None recorded. The collision behind the family's identity rules is tailscale's
(see launchd-label).

## Limits
It reads the identifier recorded in each pkg and in its components. It cannot tell whether a pkg named
under dev.mavergreen.* is this product's, which the manifest check holds.

## Deviating
Write .mavergreen/deviations/identifier/<label>/ with a scope (<pkg file glob>), a reason and a revisit. A good reason says whose identifier the pkg must keep (an
upstream's, shipped unmodified).

Formerly the conformance rule identifier
