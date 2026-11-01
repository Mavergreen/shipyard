packager: no tracked build file calls the system pkgbuild or productbuild directly.

## Why
A family pkg is built by stevedore, which runs on any host; a direct call to the system packager keeps the
build on a scarce macOS runner. The check fails a non-comment pkgbuild or productbuild in a tracked *.sh,
*.yml, *.yaml, *.cmake or CMakeLists.txt outside tests/ and test/, which build throwaway pkgs on
purpose. It steers repos off the system packager one path at a time.

## Incident
None recorded. The rule follows the move of every family pkg to stevedore, 2026-10-26.

## Limits
It is a text match at any position on a non-comment line, so a mention in a string counts. A call through
a variable ("$PKGBUILD") is not seen. A path in scripts/conventions-grandfathered for this repo is excused
until its line is deleted.

## Deviating
Write "- packager:<path>: <why it must, and its exit>". The path is one file; deviations.sh refuses a
wildcard. A good reason names what still needs the system tool (an oracle comparison) and what retires it.

Formerly gate check 35
