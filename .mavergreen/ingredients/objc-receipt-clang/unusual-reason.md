The digest beside it is written by hand from the release's SHA256SUMS (the bump PR says how).

On a bump: `scripts/fetch_clang22.sh . objc-receipt-clang` fetches that release, on a Mac and on x86_64
Linux; a bump must pass `tests/objc-source-inventory-host-test.sh` on a Mac and in the Linux job.
