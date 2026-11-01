macports: no use of MacPorts without a deviation covering the path.

## Why
The family works toward no outside package manager, and every use is counted as a declared deviation. The
check matches the command port at command position and the prefix /opt/local, on a non-comment line, in
tracked shell scripts outside tests/ and in every workflow and composite-action run: block.

## Incident
None recorded. The rule is the maintainer's decision of 2026-10-14.

## Limits
A script that only names /opt/local to keep it out of CMake's search is a use as far as the
check goes, and is declared as one. A port invoked behind a prefix other than sudo, env, command or time is
not seen.

## Deviating
Write "- macports:<path>: <reason>. Revisit when <exit>." The exit names the family product or facility that
replaces the use. shipyard's one entry says it names the prefix only to exclude it, and revisits if the
exclusion list moves into a shared CMake module.

New in the flag day (the maintainer, 2026-10-14: outside package managers are declared deviations)
