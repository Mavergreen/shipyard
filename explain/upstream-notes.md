upstream-notes: a product repo can link its upstream's release notes, or says why it cannot.

## Why
A release that ships a new upstream links upstream's own notes for that version, so a reader sees what
changed without hunting. Where upstream publishes them is the repo's to say, so the repo commits
.mavergreen/hooks/upstream-release-notes-url, which prints one URL for the version it is given. A repo whose
upstream publishes none, or that is its own upstream, says so as a deviation instead.

## Incident
Undated: signal-desktop's 8.27.0-mavericks.1 shipped a new upstream with no link and nothing red, because
everything returned 0. The release notes now fail a new upstream that has neither the hook nor the deviation,
and this check finds the gap before a release does.

## Limits
It runs only where there is a .github/workflows/release.yml. It checks that the hook is committed, not that
the URL it prints resolves; release-notes.sh fails a release whose hook prints anything but one URL. A hook
in the old places, build/ or scripts/upstream-release-notes-url.sh, is not read.

## Deviating
Write .mavergreen/deviations/upstream-notes/<label>/ with scope *, a reason (why there are no notes to link)
and a revisit (what would give the repo some, such as building someone else's upstream).

Formerly gate check 11 (build/ or scripts/upstream-release-notes-url.sh, or INGREDIENTS.md's "No upstream release notes:" line)
