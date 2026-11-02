#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  SCRIPTS="$BATS_TEST_DIRNAME/../scripts"
  CLOSURE="$SCRIPTS/script-closure.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/script-closure-test.XXXXXX")" && pwd)"
}
teardown() { rm -rf "$WORK"; }

copy_closure() {
  mkdir -p "$2"
  sh "$CLOSURE" "$1" | while IFS= read -r f; do
    mkdir -p "$2/$(dirname "$f")"
    cp "$SCRIPTS/$f" "$2/$f"
  done
}

@test "the closure of build_component_pkg.sh holds the stevedore fetch and its pin" {
  run sh "$CLOSURE" build_component_pkg.sh
  [ "$status" -eq 0 ]
  for need in build_component_pkg.sh fetch_stevedore.sh ../.mavergreen/ingredients/stevedore/VERSION mavergreen-meta.sh fetch-release-pkg.sh source-date-epoch.sh mavericks_fetch.sh; do
    printf '%s\n' "$output" | grep -qx "$need" || { echo "closure lacks $need: $output"; false; }
  done
}

@test "the closure is sorted, one path per line, and names the script itself" {
  sh "$CLOSURE" fetch_stevedore.sh > "$WORK/out"
  LC_ALL=C sort -u "$WORK/out" | cmp - "$WORK/out"
  grep -qx fetch_stevedore.sh "$WORK/out"
}

@test "several names give the union" {
  sh "$CLOSURE" source-date-epoch.sh mavergreen-meta.sh > "$WORK/out"
  [ "$(cat "$WORK/out")" = "mavergreen-meta.sh
source-date-epoch.sh" ]
}

@test "a name that is not under scripts/ is refused" {
  run sh "$CLOSURE" no-such-script.sh
  [ "$status" -eq 2 ]
  run sh "$CLOSURE"
  [ "$status" -eq 2 ]
}

@test "a comment's mention of a sibling is not a dependency" {
  mkdir -p "$WORK/s"
  cp "$CLOSURE" "$WORK/s/"
  printf '#!/bin/sh\n# see helper.sh\necho hi\n' > "$WORK/s/a.sh"
  printf '#!/bin/sh\n' > "$WORK/s/helper.sh"
  run sh "$WORK/s/script-closure.sh" a.sh
  [ "$output" = a.sh ]
}

@test "every script's closure holds each sibling it reaches through \$SELF, \$SCRIPTS or dirname" {
  for f in "$SCRIPTS"/*.sh; do
    name="$(basename "$f")"
    sh "$CLOSURE" "$name" > "$WORK/closure"
    sed '/^[[:space:]]*#/d' "$f" | grep -oE '(\$SELF|\$SCRIPTS|pwd\)|\$0"\))/[A-Za-z0-9_.-]+' | sed 's|.*/||' > "$WORK/refs" || :
    while IFS= read -r ref; do
      [ -f "$SCRIPTS/$ref" ] || continue
      grep -qx "$ref" "$WORK/closure" || { echo "closure of $name misses $ref"; false; }
    done < "$WORK/refs"
  done
}

@test "fetch_stevedore.sh runs from a directory holding only its closure" {
  copy_closure fetch_stevedore.sh "$WORK/only/scripts"
  V="$(sed -n 1p "$WORK/only/.mavergreen/ingredients/stevedore/VERSION")"
  [ -n "$V" ]
  printf '#!/bin/sh\necho "stevedore %s"\n' "$V" > "$WORK/stevedore"
  chmod +x "$WORK/stevedore"
  STEVEDORE="$WORK/stevedore" run sh "$WORK/only/scripts/fetch_stevedore.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "$WORK/stevedore" ]
}

@test "source-date-epoch.sh runs from a directory holding only its closure" {
  copy_closure source-date-epoch.sh "$WORK/only/scripts"
  SOURCE_DATE_EPOCH=7 run sh "$WORK/only/scripts/source-date-epoch.sh"
  [ "$output" = 7 ]
}
