apt: no use of apt without a deviation covering the path.

## Why
The family works toward no outside package manager, and every use is counted as a declared deviation. The
check matches the commands apt-get, apt and dpkg -i at command position, on a non-comment line of tracked
shell scripts outside tests/ and of every workflow and composite-action run: block. It has no prefix: apt
has no tree the family would name.

## Incident
None recorded. The rule is the maintainer's decision of 2026-10-14. shipyard's first cases are the Linux CI
job's llvm, and bats-core on a Linux runner.

## Limits
dpkg without -i, and dpkg-deb, are not matched. A command behind a prefix other than sudo, env, command or
time is not seen.

## Deviating
Write "- apt:<path>: <reason>. Revisit when <exit>." The exit names the family product or facility that
replaces the use: shipyard's reads "Revisit when area 14's pinned LLVM tarball supplies the readers."

New in the flag day (the maintainer, 2026-10-14: outside package managers are declared deviations)
