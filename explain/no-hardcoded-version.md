no-hardcoded-version: no tracked build file contains UPSTREAM_VERSION's whole dotted version.

## Why
The next Renovate bump changes UPSTREAM_VERSION and the stale copy fails the bump's own CI, which blocks the
automerge. Files under build/, packaging/ and .github/workflows/, and CMakeLists.txt, read the pin instead
of spelling it out. The match is the whole dotted version: 12.3 is not found inside 112.34, ABC12.3 or
12.3.1, and v12.3 is. The same holds for a test that encodes the upstream version: it must read it from
UPSTREAM_VERSION. The one exception worth keeping is a test that pins a transform with fixed inputs
(V_9_9_P2 becomes 9.9p2), which is true forever.

## Incident
2026-09-13: openssh's tests/derive-upstream-version.bats asserted the derived value equals "9.9p2". Moving
the pin to V_10_5_P1 failed it, run-repo-tests gates the build, and the release never ran; fixed in
bba3750 (QUEUE #1). clang's tests/version-test.sh hardcoded the version in the same way and blocked its
automerge, unfixed when it was filed.

## Limits
It scans only the files named above, so a hardcoded version in tests/ is outside it (QUEUE #1 proposed
scanning tests with an escape hatch for fixtures). It needs a UPSTREAM_VERSION that is a full dotted version
(or at least five characters). A repo whose upstream is derived has no such file.

## Deviating
Write "- no-hardcoded-version:<path>: <reason>". A good reason says why the file must name the version (a
changelog that quotes it, say), and the exit; the usual answer is to read UPSTREAM_VERSION instead.

New in the flag day (K6, hand-rolled in gh and icu)
