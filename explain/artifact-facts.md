artifact-facts: the artifacts were read to the end, so the conformance checks saw every record.

## Why
The checks run as a pipeline: the facts producer, then the checker. A pipeline's exit status is the last
command's, no workflow sets pipefail, and every conformance check stays quiet when it has no records. So a
producer that dies cuts the stream short and every check passes. artifact-facts.sh ends a successful run
with an end-of-facts record and the checker refuses a stream without one; a deliberate give-up emits abort
<reason> first, so the operator reads why. The check also fails when the release version is not given
(SHIPYARD_CHECK_VERSION), since there is nothing to compare artifacts to. No deviation can excuse it:
deviations are emitted early enough to survive a truncation, so they cannot vouch for what follows.

The general rule: never let a fallible producer's exit status travel through a pipe you rely on. Capture
and check, or end the stream with a sentinel the consumer refuses to do without.

## Incident
Undated in the conventions skill: a dist with an empty RELEASE_NOTES.md printed "conformance: ok" while its
appcast described other notes and pointed at another release's file. One added exit 1 had switched the
whole conformance layer off in the eight repos that run it.

## Limits
It proves the stream ended, not that the producer saw every artifact it should have. An artifact the
producer never knew about is not in the dist and is not checked.

## Deviating
No deviation can excuse this check. Fix what the abort reason names and rebuild; re-run artifact-facts.sh
and read its stderr when the end-of-facts record is missing.

Formerly the conformance abort
