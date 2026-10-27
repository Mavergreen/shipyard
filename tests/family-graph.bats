#!/usr/bin/env bats
# platform: host-agnostic

bats_require_minimum_version 1.5.0

setup() {
  GRAPH="$BATS_TEST_DIRNAME/../scripts/family-graph.sh"
  W="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/family-graph-test.XXXXXX")" && pwd)"
  export MAVERGREEN_PRODUCT_NAMES="$W/product-names"
  : > "$MAVERGREEN_PRODUCT_NAMES"
  mkdir -p "$W/fam"
}
teardown() { rm -rf "$W"; }

reg() { for n in "$@"; do printf '%s dev.mavergreen.%s %s\n' "$n" "$n" "$n" >> "$MAVERGREEN_PRODUCT_NAMES"; done; }

declare_in() {
  r="$1"; shift
  mkdir -p "$W/fam/$r"
  { printf '# %s\n\n## Declared state\n- upstream: UPSTREAM_VERSION\n' "$r"
    for n in "$@"; do printf -- '- %s: pins/%s\n' "$n" "$n"; done
  } > "$W/fam/$r/INGREDIENTS.md"
}

@test "edges are consumer -> ingredient, sorted, one per pair" {
  reg app lib base
  declare_in app lib base
  declare_in lib base
  declare_in base
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 0 ]
  [ "$output" = "app -> base
app -> lib
lib -> base
DIAMOND app: base via lib" ]
}

@test "a diamond names the shared ingredient and the one it comes through" {
  reg top left right bottom
  declare_in top left right
  declare_in left bottom
  declare_in right bottom
  declare_in bottom
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 0 ]
  [[ "$output" != *DIAMOND* ]] || false
  declare_in top left bottom
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [[ "$output" == *"DIAMOND top: bottom via left"* ]] || false
}

@test "a cycle is printed once, rotated to start at its smallest name, and the tool ends" {
  reg a b c
  declare_in c a
  declare_in a b
  declare_in b c
  run --separate-stderr perl -e 'alarm 20; exec @ARGV' sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^CYCLE')" -eq 1 ]
  [[ "$output" == *"CYCLE a -> b -> c -> a"* ]] || false
}

@test "a fixture family with a diamond and a cycle prints both" {
  reg app lib base x y
  declare_in app lib base
  declare_in lib base
  declare_in base
  declare_in x y
  declare_in y x
  run --separate-stderr perl -e 'alarm 20; exec @ARGV' sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DIAMOND app: base via lib"* ]] || false
  [[ "$output" == *"CYCLE x -> y -> x"* ]] || false
}

@test "a self-edge is a one-node cycle, and unregistered names are not edges" {
  reg solo
  declare_in solo solo cmake
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 3 ]
  [[ "$output" == *"CYCLE solo -> solo"* ]] || false
  [[ "$output" != *cmake* ]] || false
  [ "$stderr" = "UNMAPPED solo: cmake" ]
}

@test "two products of one repo are one node" {
  printf 'p1 dev.mavergreen.p1 repo\np2 dev.mavergreen.p2 repo\nq dev.mavergreen.q other\n' > "$MAVERGREEN_PRODUCT_NAMES"
  mkdir -p "$W/fam/other" "$W/fam/repo"
  printf '## Declared state\n- upstream: V\n' > "$W/fam/repo/INGREDIENTS.md"
  printf '## Declared state\n- upstream: V\n- p1: a\n- p2: b\n' > "$W/fam/other/INGREDIENTS.md"
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$output" = "other -> repo" ]
}

@test "a repo with no clone is skipped on stderr, the graph still prints, and the exit is 3" {
  reg a b
  declare_in a b
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 3 ]
  [ "$output" = "a -> b" ]
  [[ "$stderr" == *"SKIP b: no clone"* ]] || false
}

@test "a clone with no INGREDIENTS.md is skipped on stderr" {
  reg a b
  declare_in a b
  mkdir -p "$W/fam/b"
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 3 ]
  [ "$output" = "a -> b" ]
  [[ "$stderr" == *"SKIP b: no INGREDIENTS.md"* ]] || false
}

@test "a declared name the registry does not know is UNMAPPED on stderr and the exit is 3" {
  reg a b
  declare_in a b clang
  declare_in b
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 3 ]
  [ "$output" = "a -> b" ]
  [ "$stderr" = "UNMAPPED a: clang" ]
}

@test "everything read means exit 0 and a silent stderr" {
  reg a b
  declare_in a b
  declare_in b
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "a malformed Declared state fails naming the repo" {
  reg a
  mkdir -p "$W/fam/a"
  printf '## Declared state\n- Bad Name: x\n' > "$W/fam/a/INGREDIENTS.md"
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 1 ]
  [[ "$stderr" == "family-graph: a: "* ]] || false
}

@test "usage errors exit 2" {
  run --separate-stderr sh "$GRAPH" --bogus
  [ "$status" -eq 2 ]
  run --separate-stderr sh "$GRAPH" --from-dir "$W/nope"
  [ "$status" -eq 2 ]
}
