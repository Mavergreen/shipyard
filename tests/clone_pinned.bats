#!/usr/bin/env bats
# Tests for scripts/clone_pinned.sh -- the git-source supply-chain boundary. No network: a local
# fixture repo (tag v1 on commit A, then commit B on the default branch) stands in for upstream. The
# fixture allows fetching a ref-reachable sha (as GitHub does), so the fetch-by-digest path is exercised.

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/clone_pinned.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/clone_pinned_test.XXXXXX")"
  UP="$WORK/upstream"; mkdir -p "$UP"
  git -C "$UP" init -q
  git -C "$UP" config user.email t@t; git -C "$UP" config user.name t
  git -C "$UP" config uploadpack.allowReachableSHA1InWant true
  git -C "$UP" config uploadpack.allowAnySHA1InWant true
  echo a > "$UP/f"; git -C "$UP" add f; git -C "$UP" commit -qm A
  git -C "$UP" tag v1
  A="$(git -C "$UP" rev-parse HEAD)"
  echo b > "$UP/f"; git -C "$UP" commit -qam B
  BR="$(git -C "$UP" symbolic-ref --short HEAD)"   # default branch, tip = commit B
  DEST="$WORK/dest"
}
teardown() { rm -rf "$WORK"; }

@test "pinned digest == the tag's commit: clones and verifies" {
  run sh "$HELPER" "$UP" v1 "$A" "$DEST"
  [ "$status" -eq 0 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$A" ]
}

@test "commit BEHIND the ref tip (branch pin): fetched exactly, not the tip" {
  run sh "$HELPER" "$UP" "$BR" "$A" "$DEST"   # branch tip is B; we pin A
  [ "$status" -eq 0 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$A" ]
}

@test "unknown digest (moved/forced tag, tamper): bails non-zero, leaves no dest" {
  BAD="$(printf 'a%.0s' $(seq 40))"   # 40 hex chars, not a real commit
  run sh "$HELPER" "$UP" v1 "$BAD" "$DEST"
  [ "$status" -ne 0 ]
  [ ! -d "$DEST/.git" ]
}

@test "empty digest: TOFU clone of the ref (migration affordance)" {
  run sh "$HELPER" "$UP" v1 "" "$DEST"
  [ "$status" -eq 0 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$A" ]
}

@test "cache hit: second call no-ops even with a bogus repo" {
  run sh "$HELPER" "$UP" v1 "$A" "$DEST"; [ "$status" -eq 0 ]
  run sh "$HELPER" /no/such/repo v1 "$A" "$DEST"
  [ "$status" -eq 0 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$A" ]
}

# stdout must stay clean -- progress goes to stderr -- so a caller with a stdout contract (e.g.
# ed25519's fetch-ed25519.sh prints only the src dir) can capture it. Regression: 2026-07-31.
@test "stdout is empty on fetch AND on cache hit (progress goes to stderr)" {
  out="$(sh "$HELPER" "$UP" v1 "$A" "$DEST" 2>/dev/null)"
  [ -z "$out" ]
  out="$(sh "$HELPER" "$UP" v1 "$A" "$DEST" 2>/dev/null)"   # second call: cache hit
  [ -z "$out" ]
}
