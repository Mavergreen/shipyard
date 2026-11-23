standalone: every standalone archive in a release passes check-standalone-archive.sh.

## Why
A product's standalone archive, <short>-<version>-macos-<arch>.tar.gz from stage_standalone.sh, is the
product unpacked anywhere by a user who does not run the installer. check-standalone-archive.sh refuses
an archive that is not relocatable: a Mach-O loading from a Mavergreen prefix other than its declared
requires, a link leaving the archive, pkg scripts, AppleDouble entries, or a script or text file naming
a Mavergreen prefix. artifact-facts.sh judges each archive in the dist with the mavergreen.plist its pkg
installs, and a standalone-text deviation that excused nothing in any archive fails here too.

## Incident
None recorded.

## Limits
Documentation naming a Mavergreen prefix only warns. A pkg-first product (no
packaging/<short>.standalone-bundled) is told to convert to archive-first, as a warning.

## Deviating
No deviation is read: fix the archive, or excuse its text with a standalone-text deviation.

Formerly conformance's standalone rule
