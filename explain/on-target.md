on-target: a repo that builds a pkg accepts it on real 10.9 before it publishes.

## Why
A pkg nobody installed on 10.9 is the one failure every modern-host gate misses by construction: the
runner that would catch a missing symbol, a postinstall that assumes a newer tool or a stale install is
never 10.9. So release.yml has a job whose steps use Mavergreen/mavericks-vm, or that calls a local
reusable workflow (./.github/workflows/<file>.yml) whose steps do, and the job calling
publish-release.yml (else the job named publish) lists one such job in needs:, as a list or a scalar.
It applies where artifact-checks-wired finds a pkg being built.

## Incident
None recorded. The rule follows the maintainer's decision that every pkg is installed on real 10.9 before
it ships.

## Limits
Comments do not count, and neither do an uncalled job in another workflow file or a remote reusable
workflow, since publish can only need jobs in its own workflow. It reads that the job exists and gates
publish, not what it tests in the guest. A workflow that does not parse is workflow-yaml's.

## Deviating
Write "- on-target: <reason>" (unscoped) where no 10.9 acceptance job exists yet; a good reason says why
and its exit. A scoped "- on-target:<part>: <reason>" names one gap in the job's coverage (a GUI session,
a nested VM) and exempts nothing; <part> is one word, and deviations.sh refuses a glob there.

Formerly gate check 29
