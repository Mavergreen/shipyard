arch-host: a host binary ships an arm64 slice only where a deviation declares its install path.

## Why
The family ships x86_64 by default; arm64 only with a reason. At package time every arm64 or arm64e slice
of a host binary in a pkg fails unless an arch-host deviation whose scope is a glob matches its install
path. A target file, one .mavergreen/products/<short>/target names, is built for the target and never
decides arches, so it is not judged here.

## Incident
None recorded. The rule follows the decision that arm64 ships only with a reason, with modern-smoke
running what is declared.

## Limits
It reads pkgs, not shipped tarballs. The one exemption is the one packaging uses: a path under
Library/Application Support/Mavergreen/, where the updater lives. Failures are listed for the first twenty
paths, then counted. A repo grandfathered as modern-smoke, known from $GITHUB_REPOSITORY, is warned rather
than failed, so a local run without that variable fails its slices.

## Deviating
Write .mavergreen/deviations/arch-host/<label>/ with a scope (<install-path glob>), a reason (who runs it as
arm64 on Apple Silicon, and why) and a revisit. deviations.sh refuses a glob of only *, ? and /, which would
declare the whole pkg universal.

Formerly conformance's arm64 rule, renamed arch-host by P5
