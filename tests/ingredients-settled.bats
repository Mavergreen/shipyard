#!/usr/bin/env bats
# platform: host-agnostic

RECAULK_PUB=1792929600
RUST_PUB=1792972800
DAY=86400

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/ingredients-settled.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/ingredients-settled-test.XXXXXX")" && pwd)"
  export GH_FIX="$WORK/gh" GH_LOG="$WORK/gh.log"
  export MAVERGREEN_PRODUCT_NAMES="$BATS_TEST_DIRNAME/fixtures/ingredients-settled/product-names"
  cp -R "$BATS_TEST_DIRNAME/fixtures/ingredients-settled/gh" "$GH_FIX"
  : > "$GH_LOG"
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$GH_LOG"
[ "$1" = api ] || { echo "stub gh: unexpected $*" >&2; exit 1; }
for p in "$@"; do :; done
f="$GH_FIX/$(printf '%s' "$p" | sed 's/?ref=/@/')"
if [ -f "$f.error" ]; then cat "$f.error" >&2; exit 1; fi
[ -f "$f" ] || { echo '{"message":"Not Found","status":"404"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
cat "$f"
EOF
  chmod +x "$WORK/bin/gh"
  export PATH="$WORK/bin:$PATH"

  R="$WORK/repo"
  mkdir -p "$R"
  git -C "$R" init -q
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name t
  declared clang22 rust recaulk
  echo 1.0 > "$R/UPSTREAM_VERSION"
  pin clang22 22.1.0-mavericks.3
  pin rust 1.92.0-mavericks.1
  pin recaulk 20261020.1
  git -C "$R" add -A
  git -C "$R" commit -qm base
  git -C "$R" tag pr-base
}
teardown() { rm -rf "$WORK"; }

declared() {
  { printf '# porthole ingredients\n\n## Declared state\n- upstream: UPSTREAM_VERSION\n'
    for n in "$@"; do
      case "$n" in
        *=*) printf -- '- %s: components/%s/version\n' "${n%%=*}" "${n#*=}" ;;
        *) printf -- '- %s: components/%s/version\n' "$n" "$n" ;;
      esac
    done
    printf '\n## Notes\n'; } > "$R/INGREDIENTS.md"
}
pin() { mkdir -p "$R/components/$1"; echo "$2" > "$R/components/$1/version"; }
head_commit() { git -C "$R" add -A; git -C "$R" commit -qm "${1:-pr-head}"; git -C "$R" tag -f "${1:-pr-head}" >/dev/null; }
fx() { mkdir -p "$(dirname "$GH_FIX/repos/Mavergreen/$1")"; printf '%s\n' "$2" > "$GH_FIX/repos/Mavergreen/$1"; }
settled() {
  local now="$1"; shift
  cd "$R"
  run sh "$SCRIPT" --repo Mavergreen/porthole --base pr-base --head pr-head \
    --branch renovate/mavergreen-ingredients --now "$now" "$@"
}
recaulk_bump() { pin recaulk 20261025.1; head_commit; }

@test "no Mavergreen bump is settled" {
  echo 1.1 > "$R/UPSTREAM_VERSION"
  head_commit
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" == SETTLED* ]] || false
  [[ "$output" != *WAITING* ]] || false
}

@test "upstream not caught up waits" {
  recaulk_bump
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 1 ]
  [[ "$output" == *"WAITING clang22 for recaulk 20261025.1"* ]] || false
  [[ "$output" != *SETTLED* ]] || false
}

@test "upstream caught up is settled" {
  recaulk_bump
  fx clang-22/contents/components/recaulk/version@22.1.0-mavericks.3 20261025.1
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" == *"SETTLED clang22 for recaulk 20261025.1"* ]] || false
}

@test "upstream ahead is settled" {
  recaulk_bump
  fx clang-22/contents/components/recaulk/version@22.1.0-mavericks.3 20261026.1
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" == *"SETTLED clang22 for recaulk 20261025.1"* ]] || false
  [[ "$output" != *WAITING* ]] || false
}

@test "Y without the pin is settled" {
  recaulk_bump
  fx clang-22/contents/INGREDIENTS.md@22.1.0-mavericks.3 "## Declared state
- upstream: UPSTREAM_VERSION"
  rm "$GH_FIX/repos/Mavergreen/clang-22/contents/components/recaulk/version@22.1.0-mavericks.3"
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" == SETTLED* ]] || false
  [[ "$output" != *WAITING* ]] || false
}

@test "components fallback when Declared state lacks X" {
  recaulk_bump
  fx clang-22/contents/INGREDIENTS.md@22.1.0-mavericks.3 "## Declared state
- upstream: UPSTREAM_VERSION"
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 1 ]
  [[ "$output" == *"WAITING clang22 for recaulk 20261025.1"* ]] || false
}

@test "components fallback when Y has no INGREDIENTS.md" {
  recaulk_bump
  rm "$GH_FIX/repos/Mavergreen/clang-22/contents/INGREDIENTS.md@22.1.0-mavericks.3"
  fx clang-22/contents/components/recaulk/version@22.1.0-mavericks.3 20261025.1
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" == *"SETTLED clang22 for recaulk 20261025.1"* ]] || false
}

@test "a Declared-state entry with a KEY is read from the file at the tag" {
  recaulk_bump
  fx clang-22/contents/INGREDIENTS.md@22.1.0-mavericks.3 "## Declared state
- upstream: UPSTREAM_VERSION
- recaulk: build/pins.env:RECAULK_VERSION"
  fx clang-22/contents/build/pins.env@22.1.0-mavericks.3 'OTHER=1
RECAULK_VERSION="20261020.1"'
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 1 ]
  [[ "$output" == *"WAITING clang22 for recaulk 20261025.1"* ]] || false
}

clang_caught_up() {
  fx clang-22/releases/latest '{"tag_name":"22.1.0-mavericks.4","draft":false,"prerelease":false,"published_at":"2026-10-25T18:00:00Z"}'
  fx clang-22/contents/INGREDIENTS.md@22.1.0-mavericks.4 "## Declared state
- upstream: UPSTREAM_VERSION
- recaulk: components/recaulk/version"
  fx clang-22/contents/components/recaulk/version@22.1.0-mavericks.4 20261025.1
}

@test "upstream caught up but PR pins old Y waits" {
  recaulk_bump
  clang_caught_up
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 1 ]
  [[ "$output" == *"WAITING Mavergreen/porthole to take clang22 22.1.0-mavericks.4 (it carries recaulk 20261025.1)"* ]] || false
  [[ "$output" != *SETTLED* ]] || false
}

@test "upstream caught up and PR takes it is settled" {
  pin recaulk 20261025.1
  pin clang22 22.1.0-mavericks.4
  head_commit
  clang_caught_up
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" == *"SETTLED clang22 for recaulk 20261025.1"* ]] || false
}

@test "a PR left behind by Y is released anyway after 24h" {
  recaulk_bump
  clang_caught_up
  settled $((RECAULK_PUB + DAY))
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::ingredients-settled: Mavergreen/porthole has not taken clang22 22.1.0-mavericks.4 (it carries recaulk 20261025.1)"* ]] || false
  [[ "$output" == *RELEASED-ANYWAY* ]] || false
}

@test "both ends of a diamond in one PR" {
  clang_caught_up
  pin recaulk 20261025.1
  head_commit
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 1 ]
  [[ "$output" == *"WAITING Mavergreen/porthole to take clang22 22.1.0-mavericks.4"* ]] || false

  pin clang22 22.1.0-mavericks.4
  head_commit
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" == *"SETTLED clang22 for recaulk 20261025.1 (clang22 22.1.0-mavericks.4 pins 20261025.1)"* ]] || false
  [[ "$output" != *WAITING* ]] || false
  [[ "$output" != *"recaulk for clang22"* ]] || false
}

@test "rename is not a bump" {
  fx rust/contents/INGREDIENTS.md@1.92.0-mavericks.1 "## Declared state
- upstream: UPSTREAM_VERSION
- clang22: components/clang22/version"
  fx rust/contents/components/clang22/version@1.92.0-mavericks.1 22.1.0-mavericks.2
  declared clang=clang22 rust recaulk
  git -C "$R" add -A
  git -C "$R" commit -qm base-renamed
  git -C "$R" tag -f pr-base >/dev/null
  declared clang22 rust recaulk
  head_commit
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" == SETTLED* ]] || false
  [[ "$output" != *WAITING* ]] || false

  pin clang22 22.1.0-mavericks.4
  head_commit
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 1 ]
  [[ "$output" == *"WAITING rust for clang22 22.1.0-mavericks.4"* ]] || false
}

@test "a newly declared ingredient is not a bump" {
  pin make 4.4.1-mavericks.1
  declared clang22 rust recaulk make
  head_commit
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" != *WAITING* ]] || false
}

@test "urgent label passes" {
  recaulk_bump
  settled $((RECAULK_PUB + 3600)) --labels "automerge,urgent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"::notice::"*urgent* ]] || false
  [[ "$output" == *SETTLED* ]] || false
  [ ! -s "$GH_LOG" ]
}

@test "security label passes" {
  recaulk_bump
  settled $((RECAULK_PUB + 3600)) --labels security
  [ "$status" -eq 0 ]
  [[ "$output" == *"::notice::"*security* ]] || false
  [ ! -s "$GH_LOG" ]
}

@test "a label that merely contains urgent does not pass" {
  recaulk_bump
  settled $((RECAULK_PUB + 3600)) --labels not-urgent
  [ "$status" -eq 1 ]
}

@test "non-renovate branch is not checked" {
  recaulk_bump
  cd "$R"
  run sh "$SCRIPT" --repo Mavergreen/porthole --base pr-base --head pr-head --branch port/fix-10.9 --now $((RECAULK_PUB + 3600))
  [ "$status" -eq 0 ]
  [[ "$output" == *NOT-CHECKED* ]] || false
  [ ! -s "$GH_LOG" ]
}

@test "release boundary" {
  pin recaulk 20261025.1
  pin rust 1.93.0-mavericks.1
  head_commit

  settled $((RECAULK_PUB + DAY))
  [ "$status" -eq 1 ]
  [[ "$output" == *"WAITING clang22 for recaulk 20261025.1"* ]] || false

  settled $((RUST_PUB + DAY - 60))
  [ "$status" -eq 1 ]
  [[ "$output" == *"WAITING clang22 for recaulk 20261025.1"* ]] || false

  settled $((RUST_PUB + DAY))
  [ "$status" -eq 0 ]
  [[ "$output" == *RELEASED-ANYWAY* ]] || false
  [[ "$output" == *"::warning::"*clang22*recaulk\ 20261025.1* ]] || false
}

@test "each release and file is read once per run" {
  pin recaulk 20261025.1
  pin rust 1.93.0-mavericks.1
  head_commit
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 1 ]
  [ "$(grep -c 'repos/Mavergreen/clang-22/releases/latest' "$GH_LOG")" -eq 1 ]
  [ "$(grep -c 'repos/Mavergreen/clang-22/contents/INGREDIENTS.md' "$GH_LOG")" -eq 1 ]
}

@test "api failure is failure" {
  recaulk_bump
  printf 'gh: API rate limit exceeded for installation ID 1. (HTTP 403)\n' \
    > "$GH_FIX/repos/Mavergreen/clang-22/releases/latest.error"
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 2 ]
  [[ "$output" == *"rate limit"* ]] || false
  [[ "$output" != *SETTLED* ]] || false
}

@test "server error reading a file is failure" {
  recaulk_bump
  printf 'gh: Bad Gateway (HTTP 502)\n' \
    > "$GH_FIX/repos/Mavergreen/clang-22/contents/components/recaulk/version@22.1.0-mavericks.3.error"
  fx clang-22/contents/INGREDIENTS.md@22.1.0-mavericks.3 "## Declared state
- upstream: UPSTREAM_VERSION"
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 2 ]
  [[ "$output" == *"HTTP 502"* ]] || false
}

@test "an unparseable release is failure" {
  recaulk_bump
  fx clang-22/releases/latest '{"tag_name":'
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 2 ]
  [[ "$output" != *Traceback* ]] || false
}

@test "a failure past the backstop is still failure" {
  recaulk_bump
  printf 'gh: Service Unavailable (HTTP 503)\n' > "$GH_FIX/repos/Mavergreen/clang-22/releases/latest.error"
  settled $((RECAULK_PUB + 30 * DAY))
  [ "$status" -eq 2 ]
}

@test "a malformed Declared state at Y's tag is failure" {
  recaulk_bump
  fx clang-22/contents/INGREDIENTS.md@22.1.0-mavericks.3 "## Declared state
- recaulk: components/recaulk/version"
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 2 ]
}

@test "non-version pin fails" {
  recaulk_bump
  fx clang-22/contents/components/recaulk/version@22.1.0-mavericks.3 latest
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 2 ]
  [[ "$output" == *latest* ]] || false
}

@test "a non-version pin in the PR fails" {
  pin recaulk main
  head_commit
  settled $((RECAULK_PUB + 3600))
  [ "$status" -eq 2 ]
  [[ "$output" == *main* ]] || false
}

@test "an unknown revision is failure" {
  recaulk_bump
  cd "$R"
  run sh "$SCRIPT" --repo Mavergreen/porthole --base nosuchrev --head pr-head --branch renovate/x --now 1
  [ "$status" -eq 2 ]
}
