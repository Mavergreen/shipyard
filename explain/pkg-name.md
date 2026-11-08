pkg-name: a product's pkg and its component are named as derived from the product.

## Why
A pkg carrying product P's manifest is named <short>-<version>.pkg, with any leading v dropped, and its component inside is <short>.pkg, both from mavergreen_name. Installer, the helper and every page that links the pkg read these names, so one hand-chosen filename makes the product look like two. A System Replace pkg has its own forms: <short>-system-replace-<version>.pkg, with the component <short>-system-replace.pkg.

## Incident
2026-10-13: the names survey found 12 of 34 pkg filenames that did not match their product's short name, and a component named mavericks-shipyard.pkg inside shipyard's pkg.

## Limits
It reads the pkg's own filename and the component names its Distribution lists. A component package has no Distribution, so its component is not named here; the base check fails such a pkg. A pkg whose product this repo does not declare is the repository check's.

## Deviating
Write .mavergreen/deviations/pkg-name/<label>/ with a scope (<pkg file glob>), a reason and a revisit. A good reason says who reads the pkg under another name and when they will stop.

New in the flag day (P3, the names spec's Checks)
