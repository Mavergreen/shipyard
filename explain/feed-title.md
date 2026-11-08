feed-title: a product's feed carries the channel and item titles derived from the product.

## Why
<short>.xml's channel title is the product's name, and its item title is <noun> <version>, the same title the Release and the notes heading carry. Sparkle shows these in the update dialog, so a hand-chosen title there is the only name a 10.9 user reads that differs from the rest.

## Incident
2026-10-13: the names survey found feeds titled with the bare short name and with "Version <tag>".

## Limits
It reads <short>.xml for each product this repo declares, the first <title> before the first <item> and the first inside it. A feed named for no declared product is the feed check's.

## Deviating
Write .mavergreen/deviations/feed-title/<label>/ with a scope (<feed file glob>), a reason and a revisit. A good reason says which installed updaters read another title and when they will stop.

New in the flag day (P3, the names spec's Checks)
