#!/usr/bin/env bats
# platform: host-agnostic

bats_require_minimum_version 1.5.0

setup() {
  GRAPH="$BATS_TEST_DIRNAME/../scripts/family-graph.sh"
  W="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/family-graph-test.XXXXXX")" && pwd)"
  mkdir -p "$W/fam"
}
teardown() { rm -rf "$W"; }

pin_in() {
  mkdir -p "$W/fam/$1/.mavergreen/ingredients/$2"
  printf '%s\n' "$2" > "$W/fam/$1/.mavergreen/ingredients/$2/product"
  printf 'Mavergreen/%s\n' "$3" > "$W/fam/$1/.mavergreen/ingredients/$2/REPO"
  printf '1.0\n' > "$W/fam/$1/.mavergreen/ingredients/$2/VERSION"
}

declare_in() {
  r="$1"; shift
  mkdir -p "$W/fam/$r/.mavergreen/ingredients"
  for n in "$@"; do pin_in "$r" "$n" "$n"; done
}

reg() { for n in "$@"; do mkdir -p "$W/fam/$n/.mavergreen"; done; }

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

@test "a self-edge is a one-node cycle, and an ingredient with no REPO is not an edge" {
  declare_in solo solo
  mkdir -p "$W/fam/solo/.mavergreen/ingredients/cmake"
  echo cmake > "$W/fam/solo/.mavergreen/ingredients/cmake/product"
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 3 ]
  [[ "$output" == *"CYCLE solo -> solo"* ]] || false
  [[ "$output" != *cmake* ]] || false
  [ "$stderr" = "UNMAPPED solo: cmake" ]
}

@test "an ingredient without a product is not a family pin" {
  declare_in solo
  mkdir -p "$W/fam/solo/.mavergreen/ingredients/bats"
  echo Mavergreen/elsewhere > "$W/fam/solo/.mavergreen/ingredients/bats/REPO"
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "two products of one repo are one node" {
  reg repo other
  pin_in other p1 repo
  pin_in other p2 repo
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$output" = "other -> repo" ]
}

@test "an ingredient's repo with no clone is skipped on stderr, the graph still prints, and the exit is 3" {
  declare_in a b
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 3 ]
  [ "$output" = "a -> b" ]
  [[ "$stderr" == *"SKIP b: no clone"* ]] || false
}

@test "a directory with no .mavergreen is not a repo" {
  declare_in a b
  declare_in b
  mkdir -p "$W/fam/notes"
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 0 ]
  [ "$output" = "a -> b" ]
  [ -z "$stderr" ]
}

@test "an ingredient with a product and no REPO is UNMAPPED on stderr and the exit is 3" {
  declare_in a b
  declare_in b
  mkdir -p "$W/fam/a/.mavergreen/ingredients/clang"
  echo clang > "$W/fam/a/.mavergreen/ingredients/clang/product"
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

@test "a malformed REPO fails naming the repo" {
  declare_in a b
  declare_in b
  echo elsewhere/b > "$W/fam/a/.mavergreen/ingredients/b/REPO"
  run --separate-stderr sh "$GRAPH" --from-dir "$W/fam"
  [ "$status" -eq 1 ]
  [[ "$stderr" == "family-graph: a: "* ]] || false
}

@test "without --from-dir the org's repos are read through gh" {
  mkdir -p "$W/bin"
  cat > "$W/bin/gh" <<'GHEOF'
#!/bin/sh
case "$*" in
  *orgs/Mavergreen/repos*) printf 'app\nlib\nplain\n' ;;
  *repos/Mavergreen/app/contents/.mavergreen/ingredients/lib/product*) echo lib ;;
  *repos/Mavergreen/app/contents/.mavergreen/ingredients/lib/REPO*) echo Mavergreen/lib ;;
  *repos/Mavergreen/app/contents/.mavergreen/ingredients*) echo lib ;;
  *repos/Mavergreen/lib/contents/.mavergreen/ingredients*) ;;
  *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
GHEOF
  chmod +x "$W/bin/gh"
  PATH="$W/bin:$PATH" run --separate-stderr sh "$GRAPH"
  [ "$status" -eq 3 ]
  [ "$output" = "app -> lib" ]
  [ "$stderr" = "SKIP plain: no .mavergreen/ingredients (HTTP 404)" ]
}

@test "usage errors exit 2" {
  run --separate-stderr sh "$GRAPH" --bogus
  [ "$status" -eq 2 ]
  run --separate-stderr sh "$GRAPH" --from-dir "$W/nope"
  [ "$status" -eq 2 ]
}
