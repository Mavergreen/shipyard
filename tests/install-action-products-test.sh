#!/bin/sh
# platform: host-agnostic
#   usage: install-action-products-test.sh
#          install@v1's optional `products` input installs named products and their requires on macOS,
#          after shipyard, and fails on any other runner when non-empty. Exit 0 clean, 1 on failure.
# spec: tests/install-products-test.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
python3 - "$here/../.github/actions/install/action.yml" <<'PY'
import sys, yaml
a = yaml.safe_load(open(sys.argv[1]))
steps = a["runs"]["steps"]
bad = []
inp = (a.get("inputs") or {}).get("products")
if inp is None:
    bad.append("no `products` input")
else:
    if inp.get("required"):
        bad.append("`products` must be optional")
    if inp.get("default") != "":
        bad.append("`products` must default to the empty string")
def run(s): return s.get("run") or ""
mac = [s for s in steps if "install-products.sh" in run(s) and "runner.os == 'macOS'" in (s.get("if") or "")]
shipyard = [s for s in steps if "mavericks-shipyard-" in run(s)]
if len(mac) != 1:
    bad.append("expected exactly one macOS step running install-products.sh, got %d" % len(mac))
if len(shipyard) != 1:
    bad.append("expected exactly one shipyard install step, got %d" % len(shipyard))
if mac and shipyard:
    m = mac[0]
    if steps.index(m) < steps.index(shipyard[0]):
        bad.append("products must install after shipyard")
    if "MAVERGREEN_INSTALLED" not in run(m) or "GITHUB_ENV" not in run(m):
        bad.append("the macOS step must export MAVERGREEN_INSTALLED via GITHUB_ENV")
    if "inputs.products" not in str(m.get("env")):
        bad.append("products must reach the script through env, not interpolated into the script")
    if "inputs.products" not in (m.get("if") or ""):
        bad.append("the macOS step must run only when products is non-empty")
msg = "products: needs a macOS runner (Installer and Longboat are macOS-only)"
non = [s for s in steps if msg in run(s)]
if len(non) != 1:
    bad.append("expected exactly one step failing non-macOS with the exact message, got %d" % len(non))
elif "runner.os != 'macOS'" not in (non[0].get("if") or "") or "inputs.products" not in (non[0].get("if") or "") + str(non[0].get("env")):
    bad.append("the failure step must run on non-macOS and test products")
if bad:
    print("FAIL: install-action-products:\n  " + "\n  ".join(bad)); sys.exit(1)
print("PASS: install-action-products")
PY
