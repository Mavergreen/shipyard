release-notes-generated: the release body is built by release-notes.sh, and by nothing else.

## Why
The body becomes both the Sparkle appcast description and the GitHub Release body, so one generator writes
the one file. The check asks for four things on non-comment lines: some workflow calls release-notes.sh (not
merely names it); no workflow hand-writes RELEASE_NOTES.md; no workflow passes --generate-notes; and every
--notes-file a workflow reads is a path the generator wrote. It checks the wiring on the pull request,
where a human can still fix it cheaply. The publisher's notes-shape checks the body's shape at release time,
and conformance's notes checks that the appcast agrees with the Release at package time; each catches
what the others structurally cannot.

## Incident
Undated in the conventions skill: six products published "Automated release for Mac OS X 10.9 (Mavericks)."
as their entire notes, every release, including Renovate repackages whose only reason to exist was an
ingredient bump; tailscale published an empty body. The per-repo migration onto the generator finished
2026-09-12.

## Limits
It sees that a call exists, not that it succeeded, that its arguments are right, or that the file reaches
the release; notes-shape and notes check those later. It does not read a call hidden in a script.

## Deviating
No deviation is read for this id. Call it: sh "$SHIPYARD_SCRIPTS/release-notes.sh" --tag --version
--product <noun> --out dist/RELEASE_NOTES.md, and give the appcast and the publish step that same path.

Formerly gate check 14
