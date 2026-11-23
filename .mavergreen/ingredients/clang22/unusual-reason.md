On a bump: `scripts/fetch_clang22.sh` fetches that release (the Linux archive and a pkg against its
release's SHA256SUMS, or the installed one at that version); a bump rebuilds the updater in shipyard's
full CI and the merge releases shipyard.
