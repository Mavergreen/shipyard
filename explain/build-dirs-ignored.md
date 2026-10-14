build-dirs-ignored: every in-tree build output directory the repo writes is covered by .gitignore.

## Why
The mirror of version-sh-tracked. An unignored build tree is one git add -A from being committed, and its
stale CMakeCache.txt keeps resolving a package that was renamed away months ago. The family does not agree
on one spelling for its build directories and does not need to, so the check asks the repo where it writes:
every cmake ... -B <dir> in its workflows and committed shell, and every binaryDir in a committed
CMakePresets.json. A directory outside the tree, or one that cannot be resolved (a variable, an absolute
path), is not the check's to demand.

## Incident
tailscale configured its updater with cmake -S updater -B build/updater, a path the shared presets never
name, so nothing connected it to .gitignore: 7.4MB of CMake output sat untracked and unignored. The
conventions skill does not date it. Separately, a defect in this check reddened two consumers within the
hour it shipped on 2026-09-09, which is why shipyard must satisfy every convention it exports.

## Limits
It finds only the -B and binaryDir spellings above. A build that picks its directory in some other way, or
computes it, is invisible. It asks git whether the directory (with a trailing slash) is ignored.

## Deviating
No deviation is read for this id. Add a pattern that covers the directory to .gitignore, or build outside
the tree under $MAVERICKS_BUILD_ROOT.

Formerly gate check 7d
