notes: an appcast's description is the release body.

## Why
The Sparkle update dialog on a 10.9 Mac must show the same words the Release page shows. One file,
RELEASE_NOTES.md, becomes both the appcast description and the Release body, so they cannot disagree, and
the Mavergreen-State marker is written into it before signing so both carry it. This check compares them
at package time, the one point where the appcast exists. It fails when an appcast has no description, when
its description is not the body, and when no notes-render fact exists to compare it against.

## Incident
None recorded. The nearest is under artifact-facts: a dist with an empty RELEASE_NOTES.md
printed "conformance: ok" while its appcast described other notes (undated).

## Limits
It compares the rendered text; it does not check the notes' quality, which notes-shape and
release-notes-generated hold. A notes file staged under a name the facts producer does not recognise is
reported, not guessed at.

## Deviating
Write "- notes:<appcast file glob>: <reason>". A good reason says why the appcast has other words, and the
exit.

Formerly the conformance rule notes
