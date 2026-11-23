On a bump: `scripts/fetch_clang22.sh . objc-receipt-clang` fetches that release, on a Mac and on x86_64
Linux, verified against its SHA256SUMS; a bump must pass `tests/objc-source-inventory-host-test.sh` on a
Mac and in the Linux job.
