feed: a product's manifest names its derived feed, and the dist carries <short>.xml unless it is built on install.

## Why
A product's feed is derived, never chosen: from the product's short name and the repo it is released from,
it is https://github.com/Mavergreen/<repo>/releases/latest/download/<short>.xml (mavergreen_name feed-url).
The check holds that the dist carries <short>.xml for every product its pkgs ship (a build that does not
sign runs stand-in-feeds.sh, which stages an unsigned stand-in); that a manifest's feed is that feed for
every product, and empty only for a product that is built-on-install
(.mavergreen/products/<short>/built-on-install exists); and that a feed describing a product's pkg is
named <short>.xml. A product whose feed nothing publishes is never updated by the Engine on any box that
installed it, and a manifest naming another feed sends the Engine to the wrong place.

## Incident
None recorded.

## Limits
It compares URLs and names; it does not fetch the feed, so a feed that exists but 404s once released is not
seen until feed-upgradeable and update-trusted at publish time.

## Deviating
Write .mavergreen/deviations/feed/<label>/ with a scope (<pkg or feed file glob>), a reason and a revisit. A good reason says why this product's feed is not the
derived one.

Formerly the conformance rule feed
