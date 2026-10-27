#!/usr/bin/env bats
# platform: host-agnostic
# Tests for scripts/required-gate.sh -- the one `required` job a pull-request workflow exposes to branch protection.

setup() {
  GATE="$BATS_TEST_DIRNAME/../scripts/required-gate.sh"
}

@test "all success passes" {
  NEEDS_JSON='{"build":{"result":"success"},"vm-test":{"result":"success"}}' run sh "$GATE"
  [ "$status" -eq 0 ]
}

@test "all skipped passes" {
  NEEDS_JSON='{"build":{"result":"skipped"},"vm-test":{"result":"skipped"}}' run sh "$GATE"
  [ "$status" -eq 0 ]
}

@test "failed dependency with skipped dependent fails" {
  NEEDS_JSON='{"build":{"result":"failure"},"vm-test":{"result":"skipped"}}' run sh "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::build failure"* ]] || false
  [[ "$output" != *"vm-test"* ]] || false
}

@test "cancelled fails" {
  NEEDS_JSON='{"build":{"result":"success"},"vm-test":{"result":"cancelled"}}' run sh "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::vm-test cancelled"* ]] || false
}

@test "empty needs is a misconfiguration" {
  NEEDS_JSON='{}' run sh "$GATE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"wire every other job into needs:"* ]] || false
}

@test "unset needs is a misconfiguration" {
  run env -u NEEDS_JSON sh "$GATE"
  [ "$status" -eq 2 ]
}
