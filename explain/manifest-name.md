manifest-name: a product's manifest carries the name derived from the product.

## Why
The manifest's name is a copy of the product's name, the noun then its line, shipped in the artifact so mavergreen list works offline. A manifest naming the product differently from its Installer title and feed shows the user a fourth name.

## Incident
None recorded. render-manifest.sh took --name by hand until the flag day, and refuses it now.

## Limits
It reads the name in usr/local/mavergreen/<short>/mavergreen.plist of each pkg that carries one. A manifest with no name is reported as none.

## Deviating
Write .mavergreen/deviations/manifest-name/<label>/ with a scope (<pkg file glob>), a reason and a revisit. A good reason says why the installed name must differ.

New in the flag day (P3, the names spec's Checks)
