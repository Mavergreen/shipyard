#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/cut-release.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/cut-release-test.XXXXXX")" && pwd)"
  export STUB="$WORK/stub" CUT_RELEASE_POLL=0 CUT_RELEASE_WAIT=0
  mkdir -p "$WORK/bin" "$STUB"
  cat > "$WORK/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "run list") case "$*" in *workflow_dispatch*) cat "$STUB/newrun" 2>/dev/null ;; *) cat "$STUB/inflight" 2>/dev/null ;; esac; exit 0 ;;
  "api repos/Mavergreen/thing/contents/.github/workflows/release.yml?ref=main") base64 < "$STUB/release.yml"; exit 0 ;;
  "release view") n=$(cat "$STUB/views" 2>/dev/null || echo 0); echo $((n + 1)) > "$STUB/views"
    if [ "$n" -eq 0 ]; then cat "$STUB/before" 2>/dev/null; else cat "$STUB/after" 2>/dev/null; fi; exit 0 ;;
  "workflow run") echo "dispatch $*" >> "$STUB/log"; exit 0 ;;
  "run watch") exit 1 ;;
  "run view") case "$*" in
      *"--json status"*) n=$(cat "$STUB/polls" 2>/dev/null || echo 0); echo $((n + 1)) > "$STUB/polls"
        sed -n "$((n + 1))p" "$STUB/states" 2>/dev/null | grep . || echo completed ;;
      *"--json conclusion"*) cat "$STUB/conclusion" 2>/dev/null || echo success ;;
      *"--log"*) cat "$STUB/runlog" 2>/dev/null ;;
      *) echo "  build: failure" ;;
    esac; exit 0 ;;
esac
echo "stub gh: unexpected $*" >&2; exit 1
EOF
  chmod +x "$WORK/bin/gh"
  # platform: the system base64 where there is one, since 10.9's reads -d as debug, not decode,
  #           and a base64 earlier on PATH could hide that.
  [ ! -x /usr/bin/base64 ] || ln -s /usr/bin/base64 "$WORK/bin/base64"
  export PATH="$WORK/bin:$PATH"
  echo 4242 > "$STUB/newrun"
  echo 1.0-mavergreen.1 > "$STUB/before"
}
teardown() { rm -rf "$WORK"; }

dispatch_inputs() {
  { printf 'name: release\non:\n  push:\n    branches: [main]\n  workflow_dispatch:\n'
    if [ $# -gt 0 ]; then printf '    inputs:\n'; for i in "$@"; do printf '      %s:\n        type: string\n' "$i"; done; fi
    printf 'jobs:\n  build:\n    runs-on: macos-26\n'; } > "$STUB/release.yml"
}

@test "dispatches plainly by default, and reports the tag it published" {
  dispatch_inputs force_publish reproduce_tag
  echo 1.0-mavergreen.2 > "$STUB/after"
  run sh "$HELPER" thing
  [ "$status" -eq 0 ]
  grep -qx 'dispatch workflow run release.yml -R Mavergreen/thing --ref main' "$STUB/log"
  [[ "$output" == *"released 1.0-mavergreen.2: https://github.com/Mavergreen/thing/releases/tag/1.0-mavergreen.2"* ]] || false
}

@test "--force passes the reason as force_publish" {
  dispatch_inputs force_publish reproduce_tag
  echo 1.0-mavergreen.2 > "$STUB/after"
  run sh "$HELPER" thing --force 'key rotation'
  [ "$status" -eq 0 ]
  grep -qx 'dispatch workflow run release.yml -R Mavergreen/thing --ref main -f force_publish=key rotation' "$STUB/log"
}

@test "--force with an empty or blank reason is a usage error, and dispatches nothing" {
  run sh "$HELPER" thing --force ''
  [ "$status" -eq 2 ]
  run sh "$HELPER" thing --force '   '
  [ "$status" -eq 2 ]
  [ ! -e "$STUB/log" ]
}

@test "--if-needed is refused, naming the new default" {
  run sh "$HELPER" thing --if-needed
  [ "$status" -eq 2 ]
  [[ "$output" == *"cut-release: --if-needed is the default now; drop it"* ]] || false
  [ ! -e "$STUB/log" ]
}

@test "a plain dispatch whose content was unchanged passes, naming the release it matched" {
  dispatch_inputs force_publish reproduce_tag
  echo 1.0-mavergreen.1 > "$STUB/after"
  printf 'publish\tdecide\tskip\npublish\tdecide\tNot published: content identical to 1.0-mavergreen.1.\n' > "$STUB/runlog"
  run sh "$HELPER" thing
  [ "$status" -eq 0 ]
  [[ "$output" == *"cut-release: run 4242 passed; nothing published: content identical to 1.0-mavergreen.1"* ]] || false
}

@test "a plain dispatch that published nothing and says no reason fails" {
  dispatch_inputs force_publish reproduce_tag
  echo 1.0-mavergreen.1 > "$STUB/after"
  run sh "$HELPER" thing
  [ "$status" -eq 1 ]
  [[ "$output" == *"passed but published nothing"* ]] || false
}

@test "a forced publish that publishes nothing fails" {
  dispatch_inputs force_publish reproduce_tag
  echo 1.0-mavergreen.1 > "$STUB/after"
  run sh "$HELPER" thing --force 'notes typo'
  [ "$status" -eq 1 ]
  [[ "$output" == *"passed but published nothing"* ]] || false
}

@test "refuses while a run is in flight, and dispatches nothing" {
  dispatch_inputs force_publish reproduce_tag
  echo '777 in_progress' > "$STUB/inflight"
  run sh "$HELPER" thing
  [ "$status" -eq 1 ]
  [[ "$output" == *"777 in_progress"* ]] || false
  [ ! -e "$STUB/log" ]
}

@test "a failed run fails, naming the run and its failed jobs" {
  dispatch_inputs force_publish reproduce_tag
  echo failure > "$STUB/conclusion"
  run sh "$HELPER" thing
  [ "$status" -eq 1 ]
  [[ "$output" == *"run 4242 ended failure"* ]] || false
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

@test "a run that waits long in the queue is waited out, not reported failed" {
  dispatch_inputs force_publish reproduce_tag
  printf 'queued\nqueued\nin_progress\ncompleted\n' > "$STUB/states"
  echo 1.0-mavergreen.2 > "$STUB/after"
  run sh "$HELPER" thing
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB/polls")" -ge 4 ]
  [[ "$output" == *"released 1.0-mavergreen.2"* ]] || false
}
