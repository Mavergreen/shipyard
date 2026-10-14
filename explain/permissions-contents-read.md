permissions-contents-read: release.yml has a top-level permissions: block holding contents: read.

## Why
Without it, every job holds the repository default token, which can write.
Only the job that publishes declares contents: write for itself. A top-level read-all or {} also satisfies it.

## Incident
None recorded.

## Limits
It checks the top-level block only. It does not check that the publishing job declares its own write: the
caller of a reusable workflow names permissions in several shapes, and a check would encode one of them.

## Deviating
Write "- permissions-contents-read: <reason>", or scope it to ".github/workflows/release.yml". A good reason
says why the default token must stay writable, and the exit.

New in the flag day (K6, hand-rolled in rust, longboat and rg)
