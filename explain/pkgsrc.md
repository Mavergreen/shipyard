pkgsrc: no use of pkgsrc without a deviation covering the path.

## Why
The family works toward no outside package manager, and every use is counted as a declared deviation. The
check matches the commands pkgin, pkg_add and bmake at command position, and the prefixes /opt/pkg and
/usr/pkg, on a non-comment line of tracked shell scripts outside tests/ and of every workflow and
composite-action run: block. A binary built against the host's pkgsrc libraries loads them from
/opt/pkg at run time (QUEUE #66).

## Incident
None recorded. The rule is the maintainer's decision of 2026-10-14.

## Limits
A script that only names /opt/pkg to keep it out of CMake's search is a use as far as the check goes. The
tests/ tree is not scanned, so a fixture or a test may call it.

## Deviating
Write "- pkgsrc:<path>: <reason>. Revisit when <exit>." The exit names the family product or facility that
replaces the use.

New in the flag day (the maintainer, 2026-10-14: outside package managers are declared deviations)
