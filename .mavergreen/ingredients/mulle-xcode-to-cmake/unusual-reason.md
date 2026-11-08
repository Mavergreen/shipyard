Renovate moves the commit in PIN but cannot write SHA256 beside it, so the host-tool build refuses the
bump until SHA256 holds the digest of GitHub's tarball of the new commit, written after checking that the
tarball's files are that commit's tree (the bump PR says how).

On a bump: `fetch_pinned_source.sh` fetches and verifies that commit's tarball; the host-tool cache key
includes the pin, so a bump rebuilds the exporter on next use.
