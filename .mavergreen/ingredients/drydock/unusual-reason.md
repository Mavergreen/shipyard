The digest beside it is written by hand from the release's SHA256SUMS (the bump PR says how).

On a bump: `scripts/fetch_drydock.sh` fetches that release (a Mac: the installed one at that version, else
the pkg through `fetch_product_pkg.sh`, verified against the release's SHA256SUMS; x86_64 Linux: the
archive, verified against the pinned digest); the pkg build stages its reference set. A bump must pass
`tests/objc-guard-test.sh` on 10.9 and `tests/objc-source-inventory-host-test.sh` on a Mac and in the
Linux job, and the merge releases shipyard. Its `LICENSE` dedicates it to the public domain, so shipping
its reference set carries no notice obligation.
