signing-scans-for-key: a workflow that runs sign_and_appcast.sh has some workflow calling scan-for-key.yml.

## Why
A public repo's Actions logs are public, and GitHub masks only the literal secret: a trace, a slice or a
re-encoding goes out as-is. So every signing run proves its logs do not carry the key before publishing.
scan-for-key.yml fetches the finished job logs and scans them, plus the files about to be released, for
every 12-byte window of the key's secret half in raw, hex and base64 forms. It runs under always(), because
a run that fails after signing leaves public logs written while the key was in use. It is a separate
workflow because reading logs needs actions: read, and a called workflow cannot ask for more than its
caller grants. publish-release.yml refuses a signed release with no scan record, so this check finds the
missing job on a pull request instead of at publish time. A commented-out mention does not vouch for it.

## Incident
Until 2026-09-10 the signing key was passed to ed25519-sign as an argv, beside a comment saying it never
was; sign_and_appcast.sh now feeds it on stdin. Separately, swift-runtime's first org-key bridge stopped on
a missing notes file right after signing, which is why the scan job runs under always() (undated).

## Limits
It asks whether some workflow mentions scan-for-key.yml on a non-comment line. It does not check that the
scan job is ordered between signing and publish, runs under always(), or that publish needs it; the
publisher's own refusal is the backstop for that. The SPARKLE_PRIVATE_KEY rules retire with Sparkle.

## Deviating
No deviation is read for this id. Add the scan job, using the snippet at the top of shipyard's
scan-for-key.yml, and make the publish job need it.

Formerly gate check 12a
