version-scheme: the release version is <upstream>-mavericks.N.

## Why
The -mavericks.N suffix means "our Nth repackage of someone else's thing", and the tag, the pkg, the appcast
and the notes all agree on it. Sparkle compares a dotted-numeric form derived from it, so a repackage of the
same upstream compares as newer. The check requires the form 1.2.3-mavericks.1.

## Incident
2026-10-14: the survey found the rule contradicting the conventions skill, which tells an own-upstream repo
to drop the suffix, and found nine scheme deviations excusing it. The design decision (K5) is that this check
follows the names spec, which gives an outside-upstream repo and an own-upstream repo different schemes; the
nine deviations are deleted when that lands.

## Limits
Today it is one scheme for every repo, so an own-upstream repo (porthole, shipyard) needs a deviation until
the names spec's check replaces it. It checks the spelling, not that N follows the previous release.

## Deviating
Write "- version-scheme: <reason>" for the whole repo; the check passes no subject, so a glob would not
match. A good reason names the version scheme the repo uses instead and why it has no upstream to suffix.
shipyard's own entry says its version is <line>.<commit count>, cut on every push. Exit: the names spec's
scheme check.

Formerly the conformance rule scheme
