# platform: host-agnostic
bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/src" "$T/patches"
  printf 'one\ntwo\nthree\n' > "$T/src/f.txt"
  cat > "$T/patches/01-a.patch" <<'P'
--- a/f.txt
+++ b/f.txt
@@ -1,3 +1,3 @@
 one
-two
+TWO
 three
P
  cat > "$T/patches/02-b.patch" <<'P'
--- a/f.txt
+++ b/f.txt
@@ -1,3 +1,3 @@
 one
-TWO
+2
 three
P
}
apply() { sh "$ROOT/scripts/apply_patches.sh" "$@"; }

@test "applies_in_order" {
  run --separate-stderr apply "$T/src" "$T/patches"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$T/src/f.txt")" = "2" ]
  [ -f "$T/src/.mavergreen-patches" ]
  [ "$(wc -l < "$T/src/.mavergreen-patches" | tr -d ' ')" = "2" ]
}

@test "second_run_is_noop" {
  apply "$T/src" "$T/patches"
  run --separate-stderr apply "$T/src" "$T/patches"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]]
  [ "$(sed -n 2p "$T/src/f.txt")" = "2" ]
}

@test "different_set_refuses" {
  apply "$T/src" "$T/patches"
  rm "$T/patches/02-b.patch"
  run --separate-stderr apply "$T/src" "$T/patches"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"patched with a different set"* ]]
}

@test "rejected_hunk_names_patch" {
  printf 'one\nzzz\nthree\n' > "$T/src/f.txt"
  run --separate-stderr apply "$T/src" "$T/patches"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"01-a.patch"* ]]
}

@test "no_orig_files_left" {
  apply "$T/src" "$T/patches"
  [ -z "$(find "$T/src" -name '*.orig')" ]
}

@test "relative_paths_work" {
  cd "$T"
  run --separate-stderr apply src patches
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$T/src/f.txt")" = "2" ]
}

@test "empty_patchdir_is_noop" {
  mkdir "$T/none"
  run --separate-stderr apply "$T/src" "$T/none"
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$T/src/f.txt")" = "two" ]
  run --separate-stderr apply "$T/src" "$T/patches"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"patched with a different set"* ]]
}

@test "missing_patchdir_fails" {
  run --separate-stderr apply "$T/src" "$T/nonexistent"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cannot read"* ]]
}

teardown() { chmod -R u+rwx "$BATS_TEST_TMPDIR" 2>/dev/null || true; }

@test "unreadable_patchdir_fails" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  chmod 311 "$T/patches"
  run --separate-stderr apply "$T/src" "$T/patches"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cannot read"* ]]
  [ ! -e "$T/src/.mavergreen-patches" ]
}
