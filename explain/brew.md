brew: no use of Homebrew, Linuxbrew or Tigerbrew without a deviation covering the path.

## Why
The family works toward no outside package manager, and every use is counted as a declared deviation so the
inventory can shrink to nothing. Each is replaced by the family product or facility that supplies the
tool. The check matches the command brew at command position, and the prefixes /opt/homebrew,
/usr/local/Homebrew and /home/linuxbrew anywhere on a non-comment line, in tracked shell scripts outside
tests/ and in every workflow and composite-action run: block. Prose does not trip it.

## Incident
None recorded. The rule is the maintainer's decision of 2026-10-14. shipyard's first cases: the fallback in
install-macho-readers.sh for llvm-lipo and llvm-strings, which Xcode does not ship.

## Limits
Command position follows shipyard-cmake-only's rule; a brew behind a prefix other than sudo, env, command or
time is not seen. It names a prefix only as text, so a script that merely excludes /opt/homebrew from a
search path (build-cmake.sh) is a use, and declared as one.

## Deviating
Write "- brew:<path>: <reason>. Revisit when <exit>." The exit names the family product or facility that
replaces the use: shipyard's own reads "Revisit when every job that runs the compat guard has clang22
installed (vision area 14)." A reason that only says the tool is convenient is not an exit.

New in the flag day (the maintainer, 2026-10-14: outside package managers are declared deviations)
