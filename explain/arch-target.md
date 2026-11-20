arch-target: every target glob matches a file its product installs, and no host binary of the pkg loads a target file.

## Why
Architectures A1: target files never decide arches. A product's .mavergreen/products/<short>/target lists
globs, relative to its tree under opt/mavergreen/<short>/, for the files it ships for the target rather
than to run on the host: an SDK's stubs, a cross toolchain's target runtime. They are skipped when a pkg's
class and floors are derived and when arch-host judges slices, so a glob that matches nothing is stale, and
a host binary that loads a target file would run code built for another machine.

## Incident
2026-10-14: sdk109's 10.9 stubs would have made a merged clang22 refuse Apple Silicon (architectures survey §2)

## Limits
A load is resolved from the loading binary: an absolute path to that payload path, @loader_path/ and
@executable_path/ from the binary's directory, and @rpath/ against each of its rpaths, resolved the same
way. The result is normalized lexically, with . and .. resolved and no symlink followed. @executable_path
is approximated by the loader's own directory, and a symlinked directory is not followed. Only a load that
resolves to a file the same pkg installs is judged, and a product that no pkg in the release ships is not.
A load is flagged if any one of the binary's rpaths reaches a target file. Rpaths inherited from the loading
executable are not consulted. arch-target has no deviation, so a false positive needs a code fix.

## Deviating
No deviation is read; correct .mavergreen/products/<short>/target.

New in the flag day (P5, architectures A1)
