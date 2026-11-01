tag-publishable: the tag being published is free, or is the one that triggered this run.

## Why
Two runs can compute the same -mavericks.(N+1) and both build it. The loser must not publish and must not
relabel, since the version is baked into the pkg filename, pkgbuild --version and the appcast; it re-dispatches
and rebuilds. So an existing tag refuses the publish, with one exception: a run started by a pushed tag always
finds its own tag. The exception holds only when the run's ref is this version's tag and the tag names the
commit being published (an annotated tag's peeled commit is read too). It serves only the legacy tags:
triggers still in existing repos, and goes with them when they are removed family-wide. If the remote's tags cannot be read at all,
the publish is refused rather than guessed.

## Incident
Undated in the conventions skill: clang had no working release path at all, because blanket refusal made the
documented "publish from a tag" model impossible; that is why the exception exists.

## Limits
It asks the caller's remote by URL (publish-release.yml checks out shipyard, never the calling repo), which is
public for every family repo, so it needs no token. It checks the tag at the moment of the check; a tag
created a moment later is the next run's problem, and the publisher's own refusal is the backstop.

## Deviating
No deviation is read for this id. Re-dispatch the release so it computes the next -mavericks.N, or move the
tag to the commit being published, or publish from a branch.

Formerly assert_tag_publishable.sh
