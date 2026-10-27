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

@test "unknown result fails" {
  NEEDS_JSON='{"a":{"result":"weird"}}' run sh "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::a weird"* ]] || false
}

@test "missing result key fails" {
  NEEDS_JSON='{"a":{}}' run sh "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::a no result"* ]] || false
}

@test "null result fails" {
  NEEDS_JSON='{"a":{"result":null}}' run sh "$GATE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::a no result"* ]] || false
}

@test "malformed JSON is a misconfiguration" {
  NEEDS_JSON='{"a":' run sh "$GATE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"::error::"* ]] || false
  [[ "$output" != *Traceback* ]] || false
}

@test "top-level array is a misconfiguration" {
  NEEDS_JSON='[{"result":"success"}]' run sh "$GATE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"::error::"* ]] || false
  [[ "$output" != *Traceback* ]] || false
}

@test "non-object value is a misconfiguration" {
  NEEDS_JSON='{"a":"success"}' run sh "$GATE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"::error::"* ]] || false
  [[ "$output" != *Traceback* ]] || false
}
