readme-reviewed: a repo's first release needs a README that a human has read.

## Why
The README is the page every visitor lands on, and nobody reads their own front door until something makes
them. A new repo ships a README carrying a visible marker line, "This README has not been read or edited by a
human yet", and publish-release.yml refuses the first release while it is there. A human reads the README,
makes it say what the project is, and deletes the line. The check keys on the substring "not been read or
edited by a human" so a repo can word its own marker. Only the first release is gated: "has released before"
is read as "has any release" from the Releases API, because a repo that has published has a README somebody
shipped. The README is read at the commit being released, not the default branch's head.

## Incident
None recorded. The conventions skill records that an earlier version tested "has any tag" and failed open,
since a repo with an unrelated tag (a backup/* from a rebase) looked as if it had published; three such tags
were found in one family checkout. That is why it asks the Releases API.

## Limits
Nothing inspects git authorship: it cannot tell a human's edit from an assistant committing a human's words,
and the publish job has no checkout of the calling repo to inspect. The point is narrow: a README that says
nothing fails, and a README that is wrong passes.

## Deviating
No deviation is read for this id. Read the README, edit it, and delete the marker line.

Formerly check-readme-reviewed.sh
