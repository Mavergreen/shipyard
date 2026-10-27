# platform: host-agnostic
setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  PATH="$STUBS:$PATH"
}
stub_git() {
  printf '#!/bin/sh\n%s\n' "$1" > "$STUBS/git"
  chmod +x "$STUBS/git"
}
decide() { sh "$ROOT/scripts/retry-decision.sh" "$@"; }

@test "taken tag on main retries" {
  stub_git 'echo "abc123	refs/tags/1.0.0-mavericks.2"'
  run decide 1.0.0-mavericks.2 https://example.invalid/r refs/heads/main false
  [ "$status" -eq 0 ]
  [ "$output" = "RETRY" ]
}

@test "empty reconcile (a push) on main retries" {
  stub_git 'echo "abc123	refs/tags/1.0.0-mavericks.2"'
  run decide 1.0.0-mavericks.2 https://example.invalid/r refs/heads/main ""
  [ "$output" = "RETRY" ]
}

@test "no tag, no retry" {
  stub_git 'exit 0'
  run decide 1.0.0-mavericks.2 https://example.invalid/r refs/heads/main false
  [ "$status" -eq 0 ]
  [ "$output" = "SKIP=tag-free" ]
}

@test "branch never retries" {
  stub_git 'echo "git must not be asked" >&2; exit 9'
  run decide 1.0.0-mavericks.2 https://example.invalid/r refs/heads/x false
  [ "$status" -eq 0 ]
  [ "$output" = "SKIP=not-main" ]
}

@test "reconcile run never retries" {
  stub_git 'echo "git must not be asked" >&2; exit 9'
  run decide 1.0.0-mavericks.2 https://example.invalid/r refs/heads/main true
  [ "$status" -eq 0 ]
  [ "$output" = "SKIP=reconcile-run" ]
}

@test "ls-remote failure is an error" {
  stub_git 'exit 128'
  run decide 1.0.0-mavericks.2 https://example.invalid/r refs/heads/main false
  [ "$status" -eq 1 ]
}

@test "wrong argument count is an error" {
  run decide 1.0.0-mavericks.2 https://example.invalid/r refs/heads/main
  [ "$status" -eq 1 ]
}

@test "an unexpected reconcile value is an error" {
  stub_git 'exit 0'
  run decide 1.0.0-mavericks.2 https://example.invalid/r refs/heads/main maybe
  [ "$status" -eq 1 ]
}
