line: a lined product's manifest, version and repo agree about the line.

## Why
A product of a line repo (a registered repo ending in -<number>, such as golang-126) must declare its line,
and the line, minus any -cross, is both the repo's suffix and the first one or two components of the version
without the dot: 1.26.8 is line 126, 22.1.1 is line 22. Without this agreement two lines could share a
bare-name selection or an updater, and a line repo could release another line's version.

## Incident
None recorded.

## Limits
It derives the line from the registered repo and the version; it does not check the repo's Renovate cap or
that the bare names are selected correctly, which the helper's tests cover.

## Deviating
Write "- line:<pkg file glob>: <reason>". A good reason says why the version and the line differ (an
upstream that renumbered), and the exit.

Formerly the conformance rule line
