bare-curl: no curl at command position in a tracked shell script outside tests/, or in a workflow or composite-action run: block.

## Why
A bare curl does not retry. One connection reset cost rust a two-hour rerun, and curl's own options cannot
cover it: --retry treats a reset mid-transfer (error 56) as non-transient, --retry-all-errors needs curl
7.71 and --retry-connrefused 7.52, and 10.9 ships 7.30 and the fetchers run there. The family's answer is one
helper, shipyard_curl, a loop around single attempts that retries curl exits 6, 7, 18, 28, 35, 52, 55 and 56 and
HTTP 429 and 5xx (never a 404), restarts from scratch, and never retries a checksum mismatch. The check scans
tracked shell scripts and every run: block of every workflow and composite action, Linux jobs included. Only
the fetch library itself (mavericks_fetch.sh, later mavergreen_fetch.sh) may call curl.

## Incident
2026-10-14 (designed then, from rust-link-backfill): rust PR #9, run 38547677558, job build-native. The first
download failed 49 seconds in with "curl: (56) Recv failure: Connection reset by peer", and the rerun cost two
hours. No family fetcher retried; repos had also hand-rolled their own (rust's fetch-clang.sh,
fetch-rust-src.sh and fetch-stage0-onbox.sh, and fd's and rg's fetch-rust.sh).

## Limits
Command position follows shipyard-cmake-only's rule, with "{", "!" and the shell keywords added; a curl
behind a wrapper other than sudo, env, command or time is not seen. A workflow that does not parse is
reported. Prose and comments do not trip it. The helper itself, shipyard_curl, is one shared fetcher that retries transient failures.

## Deviating
Write "- bare-curl:<path>: <reason>. Revisit when <exit>." for one tracked file. A good reason says what the
script needs that shipyard_curl does not give (it probes the live HTTP status, or runs before the library can be
sourced), and the exit is the change that lets it use shipyard_curl.

New in the flag day (the shared retrying fetcher, designed 2026-10-14 from rust-link-backfill)
