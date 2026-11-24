dsym-asset: every shipped linked Mach-O slice has its dSYM, by LC_UUID, in a *-dSYM.tar.gz of the same release.

## Why
split-debug.sh strips each image's debug map and keeps its DWARF in S-V-dSYM.tar.gz. A crash report
names an image by its LC_UUID, so the dSYM that symbolicates it is the one with the same LC_UUID, and it
must be published beside the pkg and the standalone archive that ship the image, whichever channel a
user installed from. artifact-facts.sh reads the LC_UUID of every linked slice (EXECUTE, DYLIB, BUNDLE)
in the release's pkgs and tarballs, and the LC_UUID of every DWARF file under *.dSYM/Contents/Resources/DWARF/
in its *-dSYM.tar.gz; a slice whose LC_UUID none of them carries fails.

## Incident
None recorded. Without a dSYM a crash in a shipped tool could not be symbolicated.

## Limits
The DWARF is matched by LC_UUID alone; whether it describes the code is not read. A tarball is a dSYM
tarball by its name, *-dSYM.tar.gz, and is read for nothing else.

## Deviating
Write .mavergreen/deviations/dsym-asset/<label>/ with a scope (<path glob>), a reason, such as an
upstream prebuilt or a Go binary that keeps its DWARF in the image, and a revisit.

New in the flag day (P6, split debug)
