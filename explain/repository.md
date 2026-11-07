repository: every product a release ships is one of this repo's .mavergreen/products/.

## Why
A product's identity is derived from its short name: the pkg identifier is dev.mavergreen.<short>, and the
updater, its feed and the manifest follow from it. A repo declares the products it releases as directories
in .mavergreen/products/, so a pkg whose manifest names a product the repo does not declare ships an
identity nothing here derived: a product copied from another repo, or a short name typed wrong. The check
reads the manifest of every pkg in the release and fails each product that has no .mavergreen/products/
directory. It needs no GITHUB_REPOSITORY: the declarations travel with the checkout.

## Incident
2026-09-25: the hand-kept registry of short names, pkg identifiers and repos had to be edited in shipyard
before any product could package. By 2026-11-07, 17 of its rows disagreed with the identifiers the products
now derive, so the registry was retired and this check holds a release to its own repo's declarations.

## Limits
It compares names only. It cannot tell that two repos declare the same short name: uniqueness across the
org is the catalog's to check. A product declared but not shipped is not reported.

## Deviating
Write .mavergreen/deviations/repository/<label>/ with a scope (<pkg file glob>), a reason and a revisit. A
good reason says why the pkg ships a product its repo cannot declare, and the revisit says when it will.

Formerly the conformance rule repository
