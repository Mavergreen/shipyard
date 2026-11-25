# platform: host-agnostic
bats_require_minimum_version 1.5.0

# assert_tag_publishable.sh VERSION REPO_URL -- publish-release.yml's guard: any existing tag refuses.
setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  T="$BATS_TEST_TMPDIR"
  git init -q "$T/remote"
  (cd "$T/remote" && git config user.email t@example.invalid && git config user.name t \
     && echo one > a && git add a && git commit -qm one \
     && git tag 1.0.0-mavericks.1 \
     && echo two > a && git commit -qam two) || return 1
  URL="$T/remote"
}
guard() { sh "$ROOT/scripts/assert_tag_publishable.sh" "$@"; }

@test "a free tag publishes" {
  run --separate-stderr guard 1.0.0-mavericks.2 "$URL"
  [ "$status" -eq 0 ]
}

@test "a taken tag refuses, and says to re-dispatch" {
  run --separate-stderr guard 1.0.0-mavericks.1 "$URL"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"already exists"* ]] || false
  [[ "$output$stderr" == *"e-dispatch"* ]] || false
}

@test "an annotated taken tag refuses" {
  (cd "$T/remote" && git tag -a -m v 1.0.0-mavericks.3 HEAD) || return 1
  run --separate-stderr guard 1.0.0-mavericks.3 "$URL"
  [ "$status" -eq 1 ]
}

@test "three arguments is a usage error" {
  run --separate-stderr guard 1.0.0-mavericks.2 "$URL" extra
  [ "$status" -eq 2 ]
}

@test "a remote it cannot read refuses rather than publish blind" {
  run --separate-stderr guard 1.0.0-mavericks.2 "$T/no-such-repo"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"could not read tags"* ]] || false
}
