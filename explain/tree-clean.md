tree-clean: a build writes nothing into the source tree that nothing declares.

## Why
A family checkout may live on NFS, and an in-tree build crosses the network for every object, link and test
fixture: measured on macho-tools, the same commit and compiler took 2.96s with the build on local disk and
11.16s in-tree on NFS. The cost is I/O wait, and it compounds, since an agent-driven session runs dozens of
builds per task. The shared presets put the build under $MAVERICKS_BUILD_ROOT (default $TMPDIR/mm-build) so
the tree stays clean. This script is what enforces it, not the presets: it asks only what the source tree
looks like before and after a build, never how the build ran, so it holds for CMake, make, a shell script or
a build system nobody has invented, and cannot be outgrown by a new mechanism. Run --record before the build
and the bare call after it (tree-clean-wired checks both are wired). Forgetting --record makes it stricter,
not weaker: with no manifest it falls back to "nothing untracked or ignored may exist outside the
allowlist" and says so.

## Incident
None recorded.

## Limits
It needs a git checkout, and fails with "refusing to certify a tree nothing could read" otherwise; under
shipyard-check it reports itself not run instead. Plain shipyard-check never selects it: it runs where the
workflow calls it after the build, or under --only tree-clean, and under shipyard-check it never consumes the
--record manifest, so a mid-pipeline check leaves it for the post-build call. It
reports at the level of paths. It warns, with exit 0, when an allowlist entry names something nothing wrote
("prune it"); that warning is false on every run of shipyard's own ci.yml, whose jobs write neither
VERSION nor dist/.

## Deviating
No deviation is read from INGREDIENTS.md. In-tree writes a repo genuinely needs go in a tracked .mavericks-intree
file: one entry per line, everything after "#" a comment where the reason belongs. An untracked allowlist is
ignored, with a warning, because one a build step wrote for itself is not reviewed. An entry ending in "/" is
a prefix and exempts the whole subtree; an entry without the slash is an exact path, so a directory written
without its slash allows nothing. Prefer the narrowest entry: a subtree entry like dist/ means everything
written there is unchecked, and declaring build/ "for one file" hands every later change a repo-wide
exemption.

Formerly assert-tree-clean.sh
