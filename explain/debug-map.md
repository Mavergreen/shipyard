debug-map: no shipped linked Mach-O keeps a debug map or names a builder's home or temporary directory.

## Why
A linked image built with -g keeps a debug map: N_OSO stabs naming each object file it was linked from, so
a debugger can find the DWARF in them. On a user's Mac those objects do not exist, the paths name the
build machine, and the image is larger than it needs to be. MavergreenToolchain.cmake builds with -g,
maps the source and build directories to . and records objects relative to the build root;
split-debug.sh writes each image's dSYM and strips the debug map with strip -S, keeping local symbols, so
a crash report still symbolicates. artifact-facts.sh reads every linked slice (EXECUTE, DYLIB, BUNDLE)
of every pkg payload and tarball: an N_OSO entry fails, and so does a string naming /Users/<user>/,
/home/<user>/, /private/var/folders/ or /var/folders/.

## Incident
None recorded. Products have shipped unstripped images naming the CI runner's checkout.

## Limits
Kexts, static archives and object files are not read. A home path is matched as text, so a string that
names /Users/Shared/ is caught too, and one that names a home without a trailing slash is not. Only
the first three such strings per file are reported.

## Deviating
Write .mavergreen/deviations/debug-map/<label>/ with a scope (<path glob>, as the payload or archive
installs it), a reason, such as an upstream prebuilt this repo cannot rebuild, and a revisit.

New in the flag day (P6, split debug)
