On a bump: `scripts/fetch_drydock.sh` fetches that release (a Mac: the installed one at that version, else
the pkg through `fetch_product_pkg.sh`; x86_64 Linux: the archive; each verified against the release's
SHA256SUMS); the pkg build stages its reference set. The receipt tool's digest in
`tests/fixtures/objc-api/provider-body.tool` is still written by hand (the bump PR says how). A bump must
pass `tests/objc-guard-test.sh` on 10.9 and `tests/objc-source-inventory-host-test.sh` on a Mac and in the
Linux job, and the merge releases shipyard. Its `LICENSE` dedicates it to the public domain, so shipping
its reference set carries no notice obligation.
