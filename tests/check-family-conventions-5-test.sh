#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"

# spec: SKILL.md "Family conventions" check 29 -- a repo that builds a .pkg has a job in release.yml
#       whose steps use Mavergreen/mavericks-vm, and the publish job needs it directly, unless
#       INGREDIENTS.md declares an unscoped "- on-target: <reason>".
vm() {  # $1 = name, $2 = the jobs appended to release.yml
  d="$work/vm-$1"; pkrepo "$d"
  printf '%s\n' "$2" >> "$d/.github/workflows/release.yml"
  (cd "$d" && git add -A) >/dev/null 2>&1
}
vm_fails() {  # $1 = name, $2 = the phrase the failure must carry
  out="$(cd "$work/vm-$1" && sh "$S" 2>&1)" && { echo "FAIL: check 29: $1 must fail"; exit 1; }
  printf '%s\n' "$out" | grep -q "$2" || { echo "FAIL: check 29: $1 should fail with '$2': $out"; exit 1; }
}
vm_passes() {  # $1 = name
  (cd "$work/vm-$1" && sh "$S" >/dev/null 2>&1) \
    || { echo "FAIL: check 29: $1 must pass: $(cd "$work/vm-$1" && sh "$S" 2>&1)"; exit 1; }
}
PUB='  publish:
    uses: Mavergreen/shipyard/.github/workflows/publish-release.yml@v1'
VMJOB='  vm-test:
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v8
      - uses: Mavergreen/mavericks-vm@v1
        with:
          run: sudo installer -pkg w.pkg -target /'
NOVM='no job in .github/workflows/release.yml installs and runs the pkg on real 10.9'
UNNEEDED='does not need its 10.9 acceptance job'

vm none "$PUB
    needs: [build]"
vm_fails none "$NOVM"

vm unneeded "$VMJOB
$PUB
    needs: [build]"
vm_fails unneeded "$UNNEEDED"

vm both "$VMJOB
$PUB
    needs: [build, vm-test]"
vm_passes both

vm scalar "$VMJOB
$PUB
    needs: vm-test"
vm_passes scalar

vm named "$(printf '%s\n    name: on-target (10.9)' "$VMJOB" | sed 's/^  vm-test:/  on-mavericks:/')
$PUB
    needs: [build, on-mavericks]"
vm_passes named

H='#'
vm comment "  vm-test:
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v8
      $H - uses: Mavergreen/mavericks-vm@v1
$PUB
    needs: [build, vm-test]"
vm_fails comment "$NOVM"

vm nopublish "$VMJOB"
vm_fails nopublish 'no publish job that needs its 10.9 acceptance job'

# spec: SKILL.md "Acceptance on real 10.9" -- publish can only need jobs in its own workflow, so a
#       mavericks-vm job in another workflow file does not count.
vm otherfile "$PUB
    needs: [build]"
printf 'name: e2e\non: push\njobs:\n%s\n' "$VMJOB" | sed '/needs: \[build\]/d' \
  > "$work/vm-otherfile/.github/workflows/e2e.yml"
(cd "$work/vm-otherfile" && git add -A) >/dev/null 2>&1
vm_fails otherfile "$NOVM"

vm declared "$PUB
    needs: [build]"
printf '\n## Conformance deviations\n\n- on-target: drives a kext that needs the real trackpad; exit: a VM with USB passthrough\n' \
  >> "$work/vm-declared/INGREDIENTS.md"
(cd "$work/vm-declared" && git add -A) >/dev/null 2>&1
vm_passes declared

# spec: SKILL.md "Acceptance on real 10.9" -- a scoped on-target:<part> declares one gap in the VM
#       job's coverage; only the unscoped form stands in for the job itself.
vm scoped "$PUB
    needs: [build]"
printf '\n## Conformance deviations\n\n- on-target:docker-vm: Fusion cannot nest inside the QEMU guest; exit: a nested-virt runner\n' \
  >> "$work/vm-scoped/INGREDIENTS.md"
(cd "$work/vm-scoped" && git add -A) >/dev/null 2>&1
vm_fails scoped "$NOVM"

vm gap "$(printf '%s\n    if: needs.ver.outputs.publish == '"'"'true'"'"'' "$VMJOB" | sed 's/^  vm-test:/  on-mavericks:/')
$PUB
    needs: [build, on-mavericks]"
printf '\n## Conformance deviations\n\n- on-target:menubar-gui: the guest has no logged-in GUI session; exit: a guest with one\n' \
  >> "$work/vm-gap/INGREDIENTS.md"
(cd "$work/vm-gap" && git add -A) >/dev/null 2>&1
vm_passes gap

# spec: SKILL.md "Acceptance on real 10.9" -- a release.yml job calling a LOCAL reusable workflow
#       that runs mavericks-vm is the VM job; a remote reusable workflow is not read, so it is not.
CALLEE='name: on-mavericks
on: workflow_call
jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: Mavergreen/mavericks-vm@v1'
CALLER='  on-mavericks:
    needs: [build]
    uses: ./.github/workflows/on-mavericks.yml'
callee() {  # $1 = name, $2 = the called workflow
  printf '%s\n' "$2" > "$work/vm-$1/.github/workflows/on-mavericks.yml"
  (cd "$work/vm-$1" && git add -A) >/dev/null 2>&1
}
vm local "$CALLER
$PUB
    needs: [build, on-mavericks]"
callee local "$CALLEE"
vm_passes local

vm localunneeded "$CALLER
$PUB
    needs: [build]"
callee localunneeded "$CALLEE"
vm_fails localunneeded "$UNNEEDED"

vm localcomment "$CALLER
$PUB
    needs: [build, on-mavericks]"
callee localcomment "$(printf '%s\n' "$CALLEE" | sed "s/^      - uses: Mavergreen/      $H - uses: Mavergreen/")"
vm_fails localcomment "$NOVM"

vm remote "  on-mavericks:
    needs: [build]
    uses: Mavergreen/elsewhere/.github/workflows/on-mavericks.yml@v1
$PUB
    needs: [build, on-mavericks]"
vm_fails remote "$NOVM"

# spec: scripts/deviations.sh -- on-target:<part> is one word naming a coverage gap; a glob there
#       would read as the bare form and exempt the repo, so it is refused, not honoured.
vm globpart "$PUB
    needs: [build]"
printf '\n## Conformance deviations\n\n- on-target:*: everything is a gap\n' >> "$work/vm-globpart/INGREDIENTS.md"
(cd "$work/vm-globpart" && git add -A) >/dev/null 2>&1
vm_fails globpart 'on-target:<part> is one word'

# spec: scripts/check-family-conventions.sh check 21 -- test/ holds fixtures exactly as tests/ does.
mkrepo "$work/vm-testdir" novm; mkdir -p "$work/vm-testdir/test"
printf '#!/bin/sh\npkgbuild --root x t.pkg\n' > "$work/vm-testdir/test/fixture.sh"
(cd "$work/vm-testdir" && git add -A) >/dev/null 2>&1
vm_passes testdir

(cd "$work/ok" && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 29: a repo that builds no pkg needs no 10.9 acceptance job: $(cd "$work/ok" && sh "$S" 2>&1)"; exit 1; }

echo "PASS: check-family-conventions-5"
