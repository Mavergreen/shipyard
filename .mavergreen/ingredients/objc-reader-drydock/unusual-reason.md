Renovate moves the commit in PIN but cannot write SHA256 beside it: a bump fails closed until SHA256 holds
the digest of GitHub's tarball of the new commit, written after checking with git that the tarball holds
exactly the commit's tree.

On a bump: `scripts/objc-compat-build.sh` fetches that tarball with `scripts/fetch_pinned_source.sh`,
verified against SHA256 (no git needed), and extracts it fresh into a private directory for each build. It
compiles only the read-only core modules the reader reuses (`mi_*`, `mfat_*`, `mx_decode`,
`mo_bind_observe`, `mrb_*`, `mml_*`, plus the `grow`/`linkedit`/`trie`/`hdrref`/`exports` modules `mml_*`
links). A bump must pass `tests/objc-reader-test.sh` and `tests/objc-binding-test.sh`. Drydock's `LICENSE`
dedicates it to the public domain, so compiling its modules carries no notice obligation; none of its
source is copied into this repository.
