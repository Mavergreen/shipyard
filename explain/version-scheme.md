version-scheme: a port's release version is <upstream>-mavergreen.N, and an own-upstream repo's is YYYYMMDD.N.

## Why
A repo that ports someone else's upstream versions each release <upstream>-mavergreen.N: "our Nth release of
that upstream". A repo that is its own upstream has no upstream to suffix, so it versions by date,
YYYYMMDD.N. The tag, the pkg, the appcast and the notes all carry the one version, and Sparkle compares a
dotted-numeric form of it, so either scheme orders a repackage after its predecessor.

The repo's kind is read from .mavergreen/: it is a port when the value file under .mavergreen/upstream/ has a
Renovate line 2, or when .mavergreen/hooks/derive-upstream-version exists. Anything else is its own upstream.

## Incident
2026-10-14: the survey found the rule contradicting the conventions skill, which tells an own-upstream repo
to drop the suffix, and found nine scheme deviations excusing it. The names spec gives an outside-upstream
repo and an own-upstream repo different schemes, and this check now follows it. The flag day restarts the
counter: the first release after it is <upstream>-mavergreen.1, whatever -mavericks.N came before.

## Limits
It checks the spelling, not that N follows the previous release, nor that the date is a real day. A release
whose facts do not name the repo's kind fails, since neither scheme can be chosen for it.

## Deviating
Write .mavergreen/deviations/version-scheme/<label>/ with scope *, for the whole repo (the check passes no
subject, so a glob would not match), a reason and a revisit. A good reason names the scheme the repo uses
instead and why neither family scheme fits. shipyard's own says it is consumed as @v1, so its version is
v<line>.<count>. Revisit: when neither shipyard nor mavericks-vm is consumed as an Action.

Formerly the conformance rule scheme
