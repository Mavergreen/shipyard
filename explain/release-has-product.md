release-has-product: a repo with a release workflow has at least one product under .mavergreen/products/.

## Why
A release ships products. Their names, identifiers and requirements are read from .mavergreen/products/, so a
repo that cuts releases with no product directory has nothing to name what it ships, and the catalog would not
list it. A repo with no .github/workflows/release.yml cuts no release and needs none.

## Incident
None recorded.

## Limits
It counts directories under .mavergreen/products/; whether each is complete is product-complete's. It does
not check that the products listed are the ones the release workflow builds.

## Deviating
No deviation is read for this id. Add .mavergreen/products/<short name>/noun for each product the repo ships.

New in the flag day (P2)
