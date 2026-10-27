#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gen-gf-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: needs a python3 with PyYAML"; exit 77; }

# spec: scripts/gen-conventions-grandfathered.sh -- a stand-in gh serves the org's repo list from
#       $FAKE_REPOS and clones from a local source repo, so the generator runs offline.
mkdir -p "$work/bin" "$work/root" "$work/src"
cp -R "$here/../scripts" "$work/root/scripts"; rm -f "$work/root/scripts/conventions-grandfathered"
G="$work/root/scripts/gen-conventions-grandfathered.sh"
cat > "$work/bin/gh" <<'SH'
#!/bin/sh
case "$1 $2" in
  "repo list") cat "$FAKE_REPOS" ;;
  "repo clone")
    name="${3#Mavergreen/}"; dir="$4"
    git clone -q "file://$FAKE_SRC/$name" "$dir" >/dev/null 2>&1
    git -C "$dir" config "url.file://$FAKE_SRC/$name.insteadOf" "https://github.com/Mavergreen/$name.git"
    git -C "$dir" remote set-url origin "https://github.com/Mavergreen/$name.git" ;;
  *) echo "fake gh: $*" >&2; exit 1 ;;
esac
SH
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH"; export PATH
FAKE_REPOS="$work/repos"; FAKE_SRC="$work/src"; export FAKE_REPOS FAKE_SRC

mksrc() {  # $1 = name, $2 = yes: has a release workflow that calls the gate and runs on macos
  d="$work/src/$1"; mkdir -p "$d"
  if [ "$2" = yes ]; then
    mkdir -p "$d/.github/workflows"
    printf '# calls family-conventions.yml\nname: release\non: push\njobs:\n  build:\n    runs-on: macos-14\n    steps:\n      - run: true\n' > "$d/.github/workflows/release.yml"
  else
    printf 'x\n' > "$d/README"
  fi
  (cd "$d" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -q -m init)
}
mksrc alpha yes; mksrc bravo no; mksrc charlie yes
printf 'alpha\nbravo\ncharlie\n' > "$work/repos"

out="$(sh "$G" "$work/clones" 2>"$work/err")" || { echo "FAIL: generator failed: $(cat "$work/err")"; exit 1; }
want='macos-runner alpha release.yml:build
macos-runner charlie release.yml:build'
[ "$out" = "$want" ] || { echo "FAIL: a repo with no workflows must not swallow the repos after it: got [$out]"; exit 1; }
[ -f "$work/clones/.gen-conventions-grandfathered" ] || { echo "FAIL: the generator must mark the directory it owns"; exit 1; }

out="$(sh "$G" "$work/clones" 2>"$work/err")" || { echo "FAIL: a rerun in an owned directory must refresh: $(cat "$work/err")"; exit 1; }
[ "$out" = "$want" ] || { echo "FAIL: rerun differs: [$out]"; exit 1; }

mkdir "$work/foreign"; printf 'mine\n' > "$work/foreign/file"
sh "$G" "$work/foreign" >/dev/null 2>&1 && { echo "FAIL: a non-empty directory without the sentinel must be refused"; exit 1; }
[ "$(cat "$work/foreign/file")" = mine ] && [ ! -e "$work/foreign/.gen-conventions-grandfathered" ] \
  || { echo "FAIL: a refused directory must be left untouched"; exit 1; }

mkdir "$work/empty"; sh "$G" "$work/empty" >/dev/null 2>&1 || { echo "FAIL: an empty directory is the generator's to use"; exit 1; }

git -C "$work/clones/alpha" remote set-url origin https://github.com/Somebody/alpha.git
printf 'dirty\n' > "$work/clones/alpha/keep"
sh "$G" "$work/clones" >/dev/null 2>"$work/err" && { echo "FAIL: a clone whose origin is not Mavergreen/<name> must be refused"; exit 1; }
grep -q 'not Mavergreen/alpha' "$work/err" || { echo "FAIL: the refusal should name the origin: $(cat "$work/err")"; exit 1; }
[ -f "$work/clones/alpha/keep" ] || { echo "FAIL: a refused clone must not be reset or removed"; exit 1; }

git -C "$work/clones/alpha" remote set-url origin https://github.com/Mavergreen/alpha.git
rm -rf "$work/clones/bravo"; mkdir "$work/clones/bravo"; printf 'x\n' > "$work/clones/bravo/f"
sh "$G" "$work/clones" >/dev/null 2>&1 && { echo "FAIL: a non-git directory where a clone belongs must be refused"; exit 1; }
[ -f "$work/clones/bravo/f" ] || { echo "FAIL: that directory must be left alone"; exit 1; }

printf 'alpha\n../escape\n' > "$work/repos"
sh "$G" "$work/clones2" >/dev/null 2>&1 && { echo "FAIL: a repo name that is a path must be refused"; exit 1; }

echo "PASS: gen-conventions-grandfathered"
