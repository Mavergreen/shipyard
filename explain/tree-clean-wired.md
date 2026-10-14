tree-clean-wired: a repo whose CI builds records the source tree before the build and asserts after it.

## Why
assert-tree-clean.sh asks what the source tree looks like after a build, never how the build ran, so one
mechanism covers every build shape in the family and any build system nobody has invented yet. The check
requires the call, not a build location: the design it replaced inspected CMakePresets.json's binaryDir,
which would have exempted clang and golang, the two repos with the most in-tree build references, because
they build from shell scripts. Exempt-by-default is the opposite of a convention. Both halves are required:
--record before the build, and the bare call after it. --record alone returns 0 unconditionally, so a repo
that calls only that half has adopted the half that can never fail. A step name or a trailing comment that
merely spells assert-tree-clean.sh does not count.

## Incident
None recorded.

## Limits
It matches the call shape on non-comment lines. It does not check the order of the steps or that the
assertion runs in a job that builds. Whether the tree stayed clean is the tree-clean id's, at run time.

## Deviating
No deviation is read for this id. Wire both calls. In-tree writes a build genuinely needs are declared in
the tracked .mavericks-intree allowlist, which is the tree-clean id's business.

Formerly gate check 19
