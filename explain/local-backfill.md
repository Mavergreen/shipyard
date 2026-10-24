# local-backfill

A Mavergreen product other than Recaulk does not publish a family-authored OS/API backfill:
a definition, static inline, macro redirect, patch hunk or generated implementation of an API the
pinned 10.9 SDK lacks (or of a system export it replaces). That code belongs in Recaulk
(`src/backfills/`, or `src/overrides/` for a replacement of an existing system export), or upstream
in macports-legacy-support. A product links `librecaulk.a` instead of carrying its own copy.

## What runs

- `scripts/scan-local-backfills.sh REPO` lists candidates in the tracked source. A candidate is not
  a verdict, and an empty scan is not proof that there are none: renamed helpers, new APIs and
  macro-generated functions are not found. Source review finds those and names them in the
  inventory, after which the scanner detects them too.
- `scripts/check-local-backfills.sh [--report] REPO` applies the policy below. Strict, the default,
  exits 1 on any finding. `--report` prints the same findings and exits 0, for an exploratory
  build. Both exit 2 when the scan, the inventory or the deviation section cannot be read.
  Publication always runs strict.

## Publication

Publication runs the rule strict twice, and nothing downgrades either run.

- The build runs `scripts/local-backfill-report.sh REPO DIST SOURCE_SHA REPORT` after its last write
  to the release assets. It writes REPORT only when strict passes on REPO, a clean checkout at
  SOURCE_SHA: a `source-sha` line, then `asset<TAB><sha256><TAB><name>` for each releasable asset,
  sorted by name. The build uploads it as the CI artifact `local-backfill-report`. It is never a
  release asset.
- `publish-release.yml` checks out the caller (its GitHub identity, not anything it was passed) at
  the commit being released, and `scripts/verify-local-backfill-report.sh` refuses, before any tag
  or release is touched: an absent or malformed report, a report for another commit, an asset whose
  hash differs from its record, an asset with no record or a record with no asset, and a source
  that fails strict when it runs again there. A notes-only release needs the report too, with no
  asset records.

The evidence covers the source and the attached assets, not the release body: the notes file is
checked for its shape by `check-release-notes.sh`, and holds no code.

The report is evidence, not permission: a forged one gets no further than a missing one, because
the publisher recomputes it. A workflow that publishes some other way bypasses all of this, so the
conventions gate (check 30) fails it.

Only source is judged. A product that links `librecaulk.a` defines the backfilled symbols in its
binary, as it should, so symbol presence in a binary is never a finding.

## The inventory: `compatibility-inventory.tsv`

At the repo root, tab-separated, with the header `path kind symbols reason`. `path` is one literal
tracked file; `symbols` is comma-separated names, or `-` for a candidate with no symbol (a
compatibility annotation, a shim/compat path). Kinds:

| kind | for |
|---|---|
| `local-backfill` | our implementation of an OS API. It fails strict mode unless an exception (below) names the file and symbol. Classifying it does not authorise shipping it |
| `product-adaptation` | product code that only looks like a backfill: an executable wrapper, a use of an older API, a kernel adaptation. The reason says why moving it into an OS-API library would be wrong |
| `upstream` | unmodified, pinned upstream code. The reason names the pin and says the source is unmodified, e.g. `libfoo 1.2.3 at the commit pinned in components/libfoo/version, unmodified` |
| `test-only` | a test double, never shipped |

The checker fails:

- a candidate no row classifies. A named symbol needs a row listing that symbol; a `-` row covers
  only symbol-less candidates in its file;
- a row, or a symbol in a row, that matches no candidate: stale rows go;
- an `upstream` row on a patch (a `*.patch`/`*.diff`, or a file the scanner recognises as a patch by
  its content). A patch is a local modification of upstream code, and is classified by what it adds;
- an `upstream` row whose reason does not mention the pin and say the source is unmodified or
  unchanged. This is a shape check on the reason, not proof: an in-place edit to a vendored file
  classified `upstream` looks to the scanner exactly like the pinned original. Reviewing a change to
  a vendored file is how that is caught.

## Exceptions

A `local-backfill` row ships only with an exception under `INGREDIENTS.md`'s
`## Conformance deviations`:

```markdown
- local-backfill:src/qos.c: <concrete reason this product alone needs it>; symbols=pthread_set_qos_class_self_np; decision=<the maintainer's decision>; evidence=<where it was reviewed: a PR or commit URL>; revisit=<the exit condition>
```

- The scope is exactly one file, the inventory's path. A bare `- local-backfill: ...`, a glob, a
  path with `.` or `..` segments, or a path no `local-backfill` row names is refused.
- `symbols=` lists every classified symbol it excuses, and only those (for a header classified with
  `-`, the affected API). A candidate symbol the exception does not list still fails.
- The concrete reason, `symbols=`, `decision=`, `evidence=` and `revisit=` are each required, once,
  and not blank. Any other lowercase `label=` is refused.
- A reason saying Recaulk already provides it is refused: then the local copy is deleted and the
  product links Recaulk; a semantic difference is a Recaulk bug, fixed there.
- One exception per file.

**A script cannot authenticate an approval.** `decision=` and `evidence=` are prose the product
itself wrote, so the checker can only require that they are there. Whether the maintainer made that
decision is verified in maintainer review of the change that adds the exception: the evidence field
is where the reviewer looks. `approved=true` or any other self-asserted switch is refused for this
reason.

Other deviations in that section are untouched; this rule reads only `local-backfill` entries,
through the common parser `scripts/deviations.sh` and `scripts/local-backfill-deviations.sh`.

**Transitional.** The `INGREDIENTS.md` reader is the currently deployed deviation grammar. When the
shared metadata directory migration lands (flag-day P2), these records move to the shared deviations
directory schema and `scripts/local-backfill-deviations.sh` is deleted.

## Recaulk

Recaulk is where backfills belong, so the canonical repository `Mavergreen/recaulk` needs no
classification of its candidates and no exception for its `local-backfill` rows. Every other finding
still applies to it: stale rows, patches classified `upstream`, invalid exceptions, malformed input.

The identity is `MAVERGREEN_CHECK_REPOSITORY`, supplied by the caller (publication derives it from
the GitHub context); exactly `Mavergreen/recaulk`, case included. Nothing in the audited tree is
read for it: a directory named `recaulk`, a metadata file or `GITHUB_REPOSITORY` grants nothing.
Unset, it is not Recaulk, so an offline check of Recaulk passes the identity explicitly.

## Fixing a finding

- An unclassified candidate: decide what it is in source review, and add the row.
- An unexcepted `local-backfill`: move it to Recaulk (or upstream), delete it if Recaulk or the SDK
  already covers it, or, if it genuinely belongs to this product for now, add the exception with the
  maintainer's decision, its review evidence and the condition that retires it.
