publish-order: in release.yml, notes come first, then the state record, then signing, then publishing.

## Why
The appcast and the Release must carry the same notes. The order is release-notes.sh, then
release-state-record.sh (which writes the Mavergreen-State marker into the notes file), then
sign_and_appcast.sh, then publish-release.yml: the marker is written before packaging so the appcast
description and the Release body agree, and the notes exist before anything signs them. The check orders the
first non-comment mention of each; a step a repo lacks takes no part (release-notes-generated and
signing-scans-for-key say whether it must exist). Taking the first mention is what lets a workflow that
signs a second product later (clang-22 with libcxx) pass.

## Incident
None recorded.

## Limits
It orders mentions, not execution: a step in a job that runs earlier but is named later in the file reads as
out of order, and two steps in parallel jobs are not ordered at all. It checks only release.yml.

## Deviating
Write "- publish-order: <reason>", or scope it to ".github/workflows/release.yml". A good reason says what
runs in an order the rule forbids and why the appcast and Release still carry the same notes, and the exit.

New in the flag day (K6, hand-rolled in fd and rg)
