rosetta: a use of Rosetta translation is covered by a rosetta:<path> deviation.

## Why
The family is transitioning off Rosetta; macOS 28 removes it. Every use is declared so the family can take
inventory and sweep the remainders before then, and the check finds an undeclared use in tracked
*.sh, *.yml, *.yaml, *.cmake, CMakeLists.txt and *.bats, tests included. It matches arch -x86_64,
arch -arch x86_64, /usr/bin/arch -x86_64 and softwareupdate --install-rosetta, outside a whole comment
line or a trailing remark. Sweep build uses (an arm64-native alternative gives the same output, as nodejs
did by building its host toolset for arm64); keep test uses running. A test that executes the shipped
x86_64 product has no native alternative on an arm64 runner, so run it, declared, and never skip it in CI
to avoid Rosetta. A 77 skip is for a developer's Mac without Rosetta only.

## Incident
None recorded. The rule follows the maintainer's decision that every use of Rosetta is declared.

## Limits
It is a text match, not a command-position check, so a quoted mention on an unrelated line counts. Not
seen: arch -e VAR=... -x86_64 (something between arch and its flag), arch "-x86_64" (the flag quoted), and a
cross build whose make runs an x86_64 host tool it compiled earlier. Those still need a declaration and
rely on it alone.

## Deviating
Write "- rosetta:<path>: <reason>". A good reason says what runs translated, why it cannot be native yet,
what it covers if it is a test, and the exit. For a test, the exit is the x86_64 host it moves to when
Rosetta goes (the 10.9 box or an Intel runner), never "made to skip without Rosetta". Revisit when the
family-wide inventory is empty, or when macOS 28 ships, whichever comes first.

Formerly gate check 25
