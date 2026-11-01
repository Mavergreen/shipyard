unpinned: nothing a build or test fetches is taken as whatever release is newest.

## Why
A pin in a file a Renovate manager tracks makes every change a commit with CI attached; "latest" lets
someone else's release change this repo's results with no commit to blame. The check fails, in tracked
*.sh, *.yml, *.yaml, *.cmake, CMakeLists.txt, *.bats and Dockerfiles (tests included, comments
excepted), a tagless gh release download, a gh release view of another repo without a tag, a curl,
wget or shipyard_curl of a /releases/latest URL, a gh api on one, an @latest install (npm, npx, go
install, pipx, cargo install, uvx) and a :latest image (FROM, image:, docker pull or run).

## Incident
2026-10-18: python-315's CI installed longboat's latest, shipyard's on-target job python-315's latest, and
sign_and_appcast.sh signed every family release with the latest ed25519 pkg, unverified.

## Limits
Only a fetch command's line counts: a feed URL, an install hint or an end-user install.sh names a
newest-release URL without fetching it at build time. A fetch assembled from variables at run time is not
seen, and the first hit per file is reported.

## Deviating
Write "- unpinned:<path>: <why it must be the newest, and when to reconsider>". A good reason says what
the newest release is read for (an audit, a report) and that nothing is built or signed from it.

Formerly gate check 28
