upstream-version-bare: UPSTREAM_VERSION is one line holding a bare version, with no v and no spaces.

## Why
version.sh and the release tag build on it, so a v or a stray space ends up in the tag. The file is one line,
one version: 1.4.2 or a date. What the version looks like (x.y.z, a date) is the product's own; only the bare
shape is the family's.

## Incident
None recorded.

## Limits
It reads the file at the repo root only. It does not check the content's format or that it matches the
pin Renovate tracks. A repo that derives its upstream (build/derive-upstream-version.sh) writes the file at
build time and has nothing committed to check.

## Deviating
Write "- upstream-version-bare: <reason>", or scope it to "UPSTREAM_VERSION". A good reason says why the file
holds more than one version and what reads the extra line, and the exit.

New in the flag day (K6, hand-rolled in pi, packer-plugin-macosx, recaulk and mavericks-vm)
