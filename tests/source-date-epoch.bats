#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  EPOCHSH="$BATS_TEST_DIRNAME/../scripts/source-date-epoch.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/source-date-epoch-test.XXXXXX")" && pwd)"
  unset SOURCE_DATE_EPOCH MAVERICKS_ROOT
  export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  commit_at "$WORK/product" 1700000000
  commit_at "$WORK/other" 1600000000
  mkdir "$WORK/plain"
}
teardown() { rm -rf "$WORK"; }

commit_at() {
  mkdir -p "$1"
  git -C "$1" init -q
  GIT_AUTHOR_DATE="$2 +0000" GIT_COMMITTER_DATE="$2 +0000" git -C "$1" commit -q --allow-empty -m c
}

@test "SOURCE_DATE_EPOCH wins" {
  SOURCE_DATE_EPOCH=42 MAVERICKS_ROOT="$WORK/product" run sh "$EPOCHSH"
  [ "$status" -eq 0 ]
  [ "$output" = 42 ]
}

@test "seam run from / with MAVERICKS_ROOT set takes that repo's time" {
  cd /
  MAVERICKS_ROOT="$WORK/product" run sh "$EPOCHSH"
  [ "$status" -eq 0 ]
  [ "$output" = 1700000000 ]
}

@test "MAVERICKS_ROOT beats the cwd's repo, and says nothing on stderr" {
  cd "$WORK/other"
  MAVERICKS_ROOT="$WORK/product" sh "$EPOCHSH" > "$WORK/out" 2> "$WORK/err"
  [ "$(cat "$WORK/out")" = 1700000000 ]
  [ ! -s "$WORK/err" ]
}

@test "cwd fallback names the repo on stderr" {
  cd "$WORK/other"
  sh "$EPOCHSH" > "$WORK/out" 2> "$WORK/err"
  [ "$(cat "$WORK/out")" = 1600000000 ]
  [ "$(cat "$WORK/err")" = "source-date-epoch: no SOURCE_DATE_EPOCH; using the commit time of $WORK/other" ]
}

@test "a MAVERICKS_ROOT that is not a work tree falls back to the cwd's repo" {
  cd "$WORK/other"
  MAVERICKS_ROOT="$WORK/plain" run sh "$EPOCHSH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using the commit time of $WORK/other"* ]] || falsen  [[ "$output" == *"MAVERICKS_ROOT=$WORK/plain is not a git work tree"* ]] || false
  [[ "$output" == *1600000000 ]] || false
}

@test "no SOURCE_DATE_EPOCH and no repo anywhere fails naming it" {
  cd "$WORK/plain"
  MAVERICKS_ROOT="$WORK/plain" run sh "$EPOCHSH"
  [ "$status" -eq 1 ]
  [[ "$output" == *SOURCE_DATE_EPOCH* ]] || false
}
