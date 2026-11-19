arch-floors: a pkg's x86_64 floor is its product's, and its arm64 floor the highest minimum OS its arm64 host slices record.

## Why
Architectures A3: floors are derived, never chosen. A pkg's allowed-os-versions min is its product's
floor, .mavergreen/products/<short>/floor, else 10.9.5; a pkg whose payload names no product is held to
10.9.5. A universal pkg's installation-check refuses Apple Silicon below its arm64 floor, which is the
highest minimum OS any arm64 host slice records, compared as versions, so 12.10 is above 12.9. Architectures
A2 puts both floors in the Distribution, and arch-distribution checks its shape.

## Incident
2026-10-14: go126-cross declared an 11.0 floor while its binaries record 12.0 (architectures survey).
2026-10-15: on Golden Gate, hostArchitectures x86_64,arm64 and the installation-check refused an x86_64
pkg with no Rosetta prompt (P0 spikes).

## Limits
Installer's behaviour on macOS 11 to 13 is not measured (Q5). before is judged against the target
volume as Installer reads it. An arm64 floor is read only from an installation-check whose text is one
of the fixed ones; arch-distribution fails any other, and a pkg whose slices cannot be classed.

## Deviating
No deviation is read. The newer-macos and arch-host deviations shape what is expected;
deviations/newer-macos/ drops the 10.11 ceiling.

New in the flag day (P5, architectures A3); it replaces conformance's floor rule
