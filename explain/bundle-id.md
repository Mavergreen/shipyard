bundle-id: every top-level installed bundle has a CFBundleIdentifier inside dev.mavergreen.*.

## Why
Same reason as identifier: a bundle identity that is not ours can collide with an upstream's. Top-level
means a bundle (.app, .prefPane, .kext, .bundle, .framework and so on) not nested inside another, so
Sparkle.framework inside an updater is not asked.

## Incident
None recorded.

## Limits
Nested bundles are skipped on purpose. The identifier is read from the bundle's Info.plist, as the facts
producer expands the pkg; a bundle whose plist cannot be read fails in artifact-facts, not here.

## Deviating
Write "- bundle-id:<the bundle's identifier>: <reason>", scoped to the identifier it excuses and not the pkg
that ships it. The family's own example: "- bundle-id:as.acidanthera.*: upstream's kext, shipped unmodified
under upstream's identity". A good reason says why the identity must stay upstream's, and the exit.

Formerly the conformance rule bundle-id
