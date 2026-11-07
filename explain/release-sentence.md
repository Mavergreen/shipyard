release-sentence: each release-note sentence (a .mavergreen/release-notes/<tag>/changes/<slug>, a rebuild, a product's notice) is one plain sentence a reader of the update dialog can use.

## Why
A sentence reaches every user verbatim, in the update dialog and on the release page, so it carries no
markup, no link, no identifier and none of the project's own process vocabulary. Agents write these files,
so the check that passes is the approval: nothing in a release waits on a human. release-notes.sh runs it on
every sentence of a new release and refuses one that fails, naming the file.

## Incident
None recorded.

## Limits
It tests form, not meaning: the writing rules in SKILL.md "Release notes" (lead with the effect on the user,
one bounded thing per sentence, concrete names, no history) are not checked. Its header lists every rule, one
per line, and the first rule broken is the one named. A minted tag's notes are not checked again, so a rule
added later never fails the regeneration of a published release. shipyard's own notes pass --allow shipyard.

## Deviating
No deviation is read for this id. Rewrite the sentence; a word the internal-term rule refuses can be
allowed only by the caller's --allow.

New in the flag day (merged from main's check-release-sentence.sh)
