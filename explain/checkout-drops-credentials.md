checkout-drops-credentials: every actions/checkout in release.yml sets persist-credentials: false.

## Why
The build jobs run hours of third-party build code. A checkout that keeps its token leaves it readable by
every later step, so a checkout drops it, and only the job that publishes holds a token that writes. Add
persist-credentials: false under with: on each actions/checkout step.

## Incident
None recorded.

## Limits
It reads release.yml only, and every checkout step in every job. It needs the workflow to parse (a workflow
that does not parse is reported, not passed) and python3. A job that checks out through another mechanism is
not seen.

## Deviating
Write "- checkout-drops-credentials: <reason>", or scope it to ".github/workflows/release.yml". A good reason
names the step that needs the token (a push back to the repo) and the exit.

New in the flag day (K6, hand-rolled in rust, longboat and rg)
