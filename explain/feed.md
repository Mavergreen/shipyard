feed: a product's updater, feed and manifest agree with the registry.

## Why
An updater's identity is derived, never chosen: from the product's registry line the feed is
https://github.com/Mavergreen/<repo>/releases/latest/download/<short>.xml. The check holds that the
updater's SUFeedURL is that feed; that the dist carries <short>.xml for every updater its pkgs install (a
build that does not sign runs stand-in-feeds.sh, which stages an unsigned stand-in); that a manifest's
appcast is that feed when the pkg ships an updater and empty when not; and that a feed describing a product's
pkg is named <short>.xml. A pkg whose updater polls a feed nothing publishes leaves every installed copy
without updates.

## Incident
None recorded.

## Limits
It compares URLs and names; it does not fetch the feed, so a feed that exists but 404s once released is not
seen until feed-upgradeable and update-trusted at publish time. A Sparkle updater retires with the Engine.

## Deviating
Write "- feed:<pkg or feed file glob>: <reason>". A good reason says why this product's feed is not the
derived one, and the exit.

Formerly the conformance rule feed
