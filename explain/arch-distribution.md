arch-distribution: a pkg's Distribution declares hostArchitectures x86_64,arm64 and the OS range and installation-check its class gets from its host slices.

## Why
Architectures A2: every pkg is a product archive whose Distribution states its class. A pkg with no
host binary is neutral, one whose host binaries carry only x86_64 is x86_64, and one with any arm64 host
slice is universal. Neutral and x86_64 pkgs refuse 10.11 and later unless the product declares
newer-macos. An x86_64 pkg's installation-check refuses Apple Silicon, and a universal pkg's refuses
Apple Silicon below its arm64 floor (A3). Every pkg declares hostArchitectures="x86_64,arm64", so Installer
runs the check natively rather than prompting for Rosetta. The class is derived from the pkg's Mach-O
slices as set_install_floor.sh derives it, through lib/arch-rules.sh, minus the product's target files
and anything under Library/Application Support/Mavergreen/. The script is compared word for word with
one of the three fixed texts, so an edited message fails. A pkg with no Distribution fails, and so does
a universal pkg whose product declares no newer-macos, or a host file with arm64 and no x86_64.

## Incident
2026-10-14: go126-cross declared an 11.0 floor while its binaries record 12.0 (architectures survey).
2026-10-15: on Golden Gate, hostArchitectures x86_64,arm64 and the installation-check refused an x86_64
pkg with no Rosetta prompt (P0 spikes).

## Limits
Installer's behaviour on macOS 11 to 13 is not measured (Q5); the rule is inferred from 10.9.5, 14, 15,
26 and 27. before is judged against the target volume as Installer reads it. Only the allowed-os-versions,
options, installation-check and script elements are read.

## Deviating
No deviation is read. The newer-macos and arch-host deviations shape what is expected;
deviations/newer-macos/ drops the 10.11 ceiling.

New in the flag day (P5, architectures A2)
