newer-macos: a product serves macOS 10.11 and later only when a deviation says why.

## Why
Architectures A2: a product exists for 10.9, so by default its pkg refuses 10.11 and later. One that
serves modern developers, such as a toolchain they run on a current Mac to build for 10.9, says why in a
newer-macos deviation, and set_install_floor.sh then writes no before. arch-distribution expects the
same.

## Incident
2026-10-14: the architectures spec found that no pkg had a maximum OS.

## Limits
It also drops the 10.11 ceiling on Intel: an x86_64 product with newer-macos installs on any Intel Mac
from its floor up. A universal product must declare it, since a universal pkg has no ceiling. The
subject is the product's short name, so every pkg of a product gets one OS range.

## Deviating
Write .mavergreen/deviations/newer-macos/<label>/ with a scope (the product's short name, or * for every
product in the repo), a reason naming the modern-Mac use, and a revisit.

New in the flag day (P5, architectures A2)
