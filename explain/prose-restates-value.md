prose-restates-value: no unusual-reason.md contains the value of a value file in its own directory.

## Why
A value lives in one file, which Renovate, the notes and every reader keep current. The same value copied into
prose is not kept current by anything: the first bump makes the prose wrong, and nothing fails. An
unusual-reason.md says why a value is unusual, and the value itself is already one file away (M4).

## Incident
None recorded.

## Limits
It compares each unusual-reason.md under .mavergreen/ with line 1 of each value file beside it, trimmed of
spaces and tabs, and fails when the prose contains that line as a literal substring, case and all. Value files
are those value-file-line checks, so description, why and product count, and role, watch, untracked,
tracked-by and the other prose and list files do not. An empty line 1 is skipped. There is no length floor:
a short value, such as a product name, fails wherever the prose says it. It does not compare prose with values
in other directories, and it cannot tell a restated value from a paraphrase of one.

## Deviating
No deviation is read for this id. Delete the value from the prose, and say what is unusual about it instead.

New in the flag day (P2, the metadata spec's M4)
