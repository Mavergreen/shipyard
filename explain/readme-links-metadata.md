readme-links-metadata: a repo with .mavergreen/ has a top-level README.md that links to it.

## Why
The metadata that used to sit at the top level, where a reader of the repo saw it, is now in .mavergreen/,
a directory a file listing hides. The README is where a reader starts, so it points at the metadata: what the
repo pins, what it ships and the deviations it declares.

## Incident
None recorded.

## Limits
It reads the top-level README.md only. A link is a Markdown inline link, [text](target), or a reference
definition, [label]: target, whose target, with any #fragment dropped, is .mavergreen or a path under it, with
or without a leading ./. It does not check that the path the link names exists. A repo with no .mavergreen/
is not checked.

## Deviating
No deviation is read for this id. Add a link to README.md, as in [.mavergreen/](.mavergreen/).

New in the flag day (P2)
