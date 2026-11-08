app-name: a product's .app is named as its app file says, and its bundle name agrees with its filename.

## Why
.mavergreen/products/<short>/app says how the installed .app is named. With noun, the pkg installs a top-level <noun>.app whose CFBundleName and CFBundleDisplayName are the noun and whose CFBundleIdentifier is dev.mavergreen.<short>. With upstream, upstream's own bundle name is kept, so every top-level .app outside Library/Application Support/Mavergreen/ has a CFBundleName equal to its filename, and a CFBundleDisplayName that is absent or the same; its identifier stays upstream's so its preferences carry over, and bundle-id does not ask about it. Finder, the Dock and the menu bar each show a different one of these three, so a disagreement shows the user two names for one app.

## Incident
2026-10-13: the names survey found Mavericks Container Tools.app with the identifier dev.mavergreen.DockerMenu and no display name, and Mavericks Tailscale.app as dev.mavergreen.tailscale-systray.

## Limits
It reads top-level bundles in the pkg carrying the product's manifest. An app a postinstall makes (Porthole's) is not in the pkg and is not asked. Where the app installs is the install-path check's.

## Deviating
Write .mavergreen/deviations/app-name/<label>/ with a scope (<pkg file glob>), a reason and a revisit. A good reason says which app keeps another name and why.

New in the flag day (P3, the names spec's Checks; ruling R12)
