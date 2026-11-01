no-tracked-backlog: no backlog file is tracked anywhere in the repo.

## Why
A repo's backlog is QUEUE.md under the gitignored .superpowers/, with every other piece of working state.
A backlog is a plan by another name: it describes work in flight, and once the work lands it is wrong
about the system it produced, so committed it misleads the next reader. The check fails a tracked file
named BACKLOG, QUEUE or TODO, in any case, bare or with .md, .markdown or .txt, anywhere outside
.superpowers/.

## Incident
Undated: two repos kept their backlog as a tracked BACKLOG.md, and a code comment cited one of its
entries by number.

## Limits
It matches file names only. A backlog kept under another name (NOTES.md, PLANS.txt) is not seen, nor one
inside a file whose name is something else.

## Deviating
No deviation is read for this id. Move the entries into .superpowers/QUEUE.md and git rm the file.

Formerly gate check 27
