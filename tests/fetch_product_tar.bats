#!/usr/bin/env bats
# platform: host-agnostic
setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/fetch_product_tar.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/linux-host.XXXXXX")"
  printf 'widget dev.mavergreen.widget widget-repo\n' > "$WORK/names"
  export MAVERGREEN_PRODUCT_NAMES="$WORK/names" MAVERGREEN_RELEASES="file://$WORK/releases" MAVERGREEN_TAR_CACHE="$WORK/cache"
  REL="$WORK/releases/Mavergreen/widget-repo/releases/download/1.0"
  mkdir -p "$REL"
  ASSET="$REL/widget-1.0-linux-x86_64.tar.gz"
  ln -s "$WORK" "$WORK/alias"
  DEST="$WORK/alias/out with spaces/widget"
}
teardown() { rm -rf "$WORK"; }
fixture() {
  python3 - "$ASSET" "${1:-safe}" <<'PY'
import io,sys,tarfile
p='opt/mavergreen/widget/'
with tarfile.open(sys.argv[1],'w:gz') as t:
 def file(n,data=b'W'):
  m=tarfile.TarInfo(n);m.mode=0o755;m.size=len(data);t.addfile(m,io.BytesIO(data))
 file(p+'bin/tool')
 m=tarfile.TarInfo(p+'bin/alias');m.type=tarfile.SYMTYPE;m.linkname='tool';t.addfile(m)
 kind=sys.argv[2]
 if kind=='absolute':file('/tmp/escaped')
 if kind=='traversal':file(p+'../../escaped')
 if kind=='duplicate':file(p+'bin/tool',b'bad')
 if kind=='escape':
  m=tarfile.TarInfo(p+'outside');m.type=tarfile.SYMTYPE;m.linkname='../../../../tmp';t.addfile(m)
 if kind=='parent-link':file(p+'bin/alias/overwrite')
 if kind=='special':
  m=tarfile.TarInfo(p+'device');m.type=tarfile.FIFOTYPE;t.addfile(m)
PY
  SHA="$(python3 -c 'import hashlib,pathlib,sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' "$ASSET")"
}
@test 'fetches by pinned hash, preserves links/modes and returns only prefix' {
  fixture
  out="$(sh "$HELPER" widget 1.0 "$SHA" "$DEST" 2>/dev/null)"
  [ "$out" = "$(cd "$DEST" && pwd -P)" ]
  [ "$(cat "$DEST/bin/tool")" = W ]
  [ -x "$DEST/bin/tool" ] && [ -L "$DEST/bin/alias" ]
}
@test 'rejects wrong digest and poisoned cached archive' {
  fixture
  run sh "$HELPER" widget 1.0 "$(printf '%064d' 0)" "$DEST"; [ "$status" -ne 0 ]
  run sh "$HELPER" widget 1.0 "$SHA" "$DEST"; [ "$status" -eq 0 ]
  printf poison >> "$WORK/cache/widget-repo/1.0/widget-1.0-linux-x86_64.tar.gz"
  run sh "$HELPER" widget 1.0 "$SHA" "$DEST"; [ "$status" -ne 0 ]
}
@test 'validates cached executable contents and retains an unchanged prefix' {
  fixture
  run sh "$HELPER" widget 1.0 "$SHA" "$DEST"; [ "$status" -eq 0 ]
  echo kept > "$DEST/marker"
  run sh "$HELPER" widget 1.0 "$SHA" "$DEST"; [ "$status" -eq 0 ]
  [ -f "$DEST/marker" ]
  echo corrupt > "$DEST/bin/tool"
  run sh "$HELPER" widget 1.0 "$SHA" "$DEST"; [ "$status" -ne 0 ]
}
@test 'rejects unsafe archives and preserves an existing destination' {
  for kind in absolute traversal duplicate escape parent-link special; do
    fixture "$kind"
    rm -rf "$WORK/cache"
    mkdir -p "$DEST"; echo kept > "$DEST/marker"
    run sh "$HELPER" widget 1.0 "$SHA" "$DEST"; [ "$status" -ne 0 ]
    [ "$(cat "$DEST/marker")" = kept ]
  done
}
@test 'concurrent fetches return one complete unchanged prefix' {
  fixture
  for i in 1 2 3; do sh "$HELPER" widget 1.0 "$SHA" "$DEST" > "$WORK/out$i" 2> "$WORK/err$i" & done
  wait
  for i in 1 2 3; do [ "$(cat "$WORK/out$i")" = "$(cd "$DEST" && pwd -P)" ]; done
  [ "$(cat "$DEST/bin/tool")" = W ]
}
@test 'rejects a cached implicit parent replaced with a symlink' {
  fixture
  run sh "$HELPER" widget 1.0 "$SHA" "$DEST"; [ "$status" -eq 0 ]
  mv "$DEST/bin" "$DEST/other"
  ln -s other "$DEST/bin"
  run sh "$HELPER" widget 1.0 "$SHA" "$DEST"; [ "$status" -ne 0 ]
}
