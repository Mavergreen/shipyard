shipyard-cmake-only: no plain cmake, ctest or cpack at command position.

## Why
MavericksShipyardConfig.cmake refuses any other cmake at configure time, by name. This finds the call on
the pull request instead of in the release. Workflows and committed *.sh outside tests/ are scanned;
tests/ is excluded because fixtures quote the command on purpose. The fix is shipyard-cmake,
shipyard-ctest and shipyard-cpack, which the mavergreen helper links into /usr/local/mavergreen/bin.

## Incident
None recorded.

## Limits
It reads lines, not shell syntax. A whole comment line and a bare "(" before the command are not treated as
a call; the "(" blind spot is deliberate, to let echo "not built (cmake --build <dir>)" through. A quoted
string or heredoc with ";", "&&", "|" or a backtick before the command still fails, since telling those from
a call needs a parser. Not seen: a bare subshell, a path (/usr/local/bin/cmake), a variable ("$CMAKE") and
anything behind a prefix command (sudo, env, command, xcrun, time). Configure time still catches each.

## Deviating
Write "- shipyard-cmake-only:<path>: <reason>" for a file whose prose must quote the command. Better:
reword it as a # comment. A good reason says what the line is (a usage message) and that no cmake runs.

Formerly gate check 18
