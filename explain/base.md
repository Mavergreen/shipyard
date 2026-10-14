base: a pkg carrying a manifest lists dev.mavergreen.base as its first component.

## Why
Every product archive carries the helper as the component dev.mavergreen.base, listed first, so any single
product installs on a clean box. Installer lays down every payload before running any postinstall, then runs
the postinstalls in Distribution order, so a base listed first has installed or upgraded
/usr/local/bin/mavergreen before the product's postinstall runs it. set_install_floor.sh adds the component
and checks it came out first. The base never downgrades: it installs the helper only over a missing,
malformed or older one.

## Incident
None recorded.

## Limits
It reads the order of the components in the Distribution. A product's preinstall runs before the base's
payload lands, so it can use the helper only if one is already installed; this check does not see that.

## Deviating
Write "- base:<pkg file glob>: <reason>". A good reason says why the pkg cannot carry the base, and the
exit. Rarely warranted; build the archive with set_install_floor.sh.

Formerly the conformance rule base
