#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/cut-release.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/cut-release-test.XXXXXX")" && pwd)"
  export STUB="$WORK/stub" CUT_RELEASE_POLL=0
  mkdir -p "$WORK/bin" "$STUB"
  cat > "$WORK/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "run list") case "$*" in *workflow_dispatch*) cat "$STUB/newrun" 2>/dev/null ;; *) cat "$STUB/inflight" 2>/dev/null ;; esac; exit 0 ;;
  "api repos/Mavergreen/thing/contents/.github/workflows/release.yml?ref=main") base64 < "$STUB/release.yml"; exit 0 ;;
  "release view") n=$(cat "$STUB/views" 2>/dev/null || echo 0); echo $((n + 1)) > "$STUB/views"
    if [ "$n" -eq 0 ]; then cat "$STUB/before" 2>/dev/null; else cat "$STUB/after" 2>/dev/null; fi; exit 0 ;;
  "workflow run") echo "dispatch $*" >> "$STUB/log"; exit 0 ;;
  "run watch") exit "$(cat "$STUB/watch-rc" 2>/dev/null || echo 0)" ;;
  "run view") echo "  build: failure"; exit 0 ;;
esac
echo "stub gh: unexpected $*" >&2; exit 1
EOF
  chmod +x "$WORK/bin/gh"
  # platform: the system base64 where there is one, since 10.9's reads -d as debug, not decode,
  #           and a base64 earlier on PATH could hide that.
  [ ! -x /usr/bin/base64 ] || ln -s /usr/bin/base64 "$WORK/bin/base64"
  export PATH="$WORK/bin:$PATH"
  echo 4242 > "$STUB/newrun"
  echo 1.0-mavericks.1 > "$STUB/before"
}
teardown() { rm -rf "$WORK"; }

dispatch_inputs() {  # the release.yml's workflow_dispatch inputs, one name per argument
  { printf 'name: release\non:\n  push:\n    branches: [main]\n  workflow_dispatch:\n'
    if [ $# -gt 0 ]; then printf '    inputs:\n'; for i in "$@"; do printf '      %s:\n        type: boolean\n' "$i"; done; fi
    printf 'jobs:\n  build:\n    runs-on: macos-26\n'; } > "$STUB/release.yml"
}

@test "asks for a publish through local_release, and reports the tag it published" {
  dispatch_inputs local_release
  echo 1.0-mavericks.2 > "$STUB/after"
  run sh "$HELPER" thing
  [ "$status" -eq 0 ]
  grep -qx 'dispatch workflow run release.yml -R Mavergreen/thing --ref main -f local_release=true' "$STUB/log"
  [[ "$output" == *"released 1.0-mavericks.2: https://github.com/Mavergreen/thing/releases/tag/1.0-mavericks.2"* ]] || false
}

@test "uses repackage where that is the repo's publish-anyway input, ignoring reconcile" {
  dispatch_inputs repackage reconcile
  echo 1.0-mavericks.2 > "$STUB/after"
  run sh "$HELPER" thing
  [ "$status" -eq 0 ]
  grep -qx 'dispatch workflow run release.yml -R Mavergreen/thing --ref main -f repackage=true' "$STUB/log"
}

@test "dispatches plainly where the release.yml declares no input" {
  dispatch_inputs
  echo 20261018.1 > "$STUB/after"
  run sh "$HELPER" thing
  [ "$status" -eq 0 ]
  grep -qx 'dispatch workflow run release.yml -R Mavergreen/thing --ref main' "$STUB/log"
}

@test "--if-needed dispatches plainly, and a run that publishes nothing is fine" {
  dispatch_inputs local_release
  echo 1.0-mavericks.1 > "$STUB/after"
  run sh "$HELPER" thing --if-needed
  [ "$status" -eq 0 ]
  grep -qx 'dispatch workflow run release.yml -R Mavergreen/thing --ref main' "$STUB/log"
  [[ "$output" == *"published nothing: none was needed"* ]] || false
}

@test "a requested publish that publishes nothing fails" {
  dispatch_inputs local_release
  echo 1.0-mavericks.1 > "$STUB/after"
  run sh "$HELPER" thing
  [ "$status" -eq 1 ]
  [[ "$output" == *"passed but published nothing"* ]] || false
}

@test "refuses while a run is in flight, and dispatches nothing" {
  dispatch_inputs local_release
  echo '777 in_progress' > "$STUB/inflight"
  run sh "$HELPER" thing
  [ "$status" -eq 1 ]
  [[ "$output" == *"777 in_progress"* ]] || false
  [ ! -e "$STUB/log" ]
}

@test "a failed run fails, naming the run and its failed jobs" {
  dispatch_inputs local_release
  echo 1 > "$STUB/watch-rc"
  run sh "$HELPER" thing
  [ "$status" -eq 1 ]
  [[ "$output" == *"run 4242 failed"* ]] || false
  [[ "$output" == *"build: failure"* ]] || false
}

@test "usage errors exit 2" {
  run sh "$HELPER"
  [ "$status" -eq 2 ]
  run sh "$HELPER" Mavergreen/thing
  [ "$status" -eq 2 ]
  run sh "$HELPER" thing --frobnicate
  [ "$status" -eq 2 ]
}
