identifier: a pkg's identifier is inside dev.mavergreen.*, and a product's is its derived one.

## Why
An identifier that is not ours collides with someone else's. The pkg identifier is what Installer keys its
receipt on. It is dev.mavergreen.<short>, derived from the product's short name, and the updater, the feed
and the manifest are derived from it. The 2026-09-22 flag day moved every identifier from
dev.modernmavericks.* to dev.mavergreen.*, with no code to retire the old names from existing installs,
because there were none to protect. A pkg carrying product P's manifest, and P's component in it, are
identified as exactly dev.mavergreen.<short>: a nested identifier such as dev.mavergreen.golang.go127 is
inside the namespace but is no product's.

## Incident
None recorded. The collision behind the family's identity rules is tailscale's
(see launchd-label).

## Limits
It reads the identifier recorded in each pkg and in its components. A pkg that carries no manifest is
held only to dev.mavergreen.*; one whose product this repo does not declare is the repository check's.

## Deviating
Write .mavergreen/deviations/identifier/<label>/ with a scope (<pkg file glob>), a reason and a revisit. A good reason says whose identifier the pkg must keep (an
upstream's, shipped unmodified).

Formerly the conformance rule identifier
