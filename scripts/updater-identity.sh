#!/bin/sh
# platform: host-agnostic
#   usage: updater-identity.sh FACT SHORT
#          SHORT's Sparkle updater identity, derived from .mavergreen/products/SHORT/. FACT is one of
#            bundle-id     dev.mavergreen.SHORT.updater
#            agent-label   dev.mavergreen.SHORT-updatecheck
#            app           Library/Application Support/Mavergreen/SHORT-updater.app
#            feed          https://github.com/Mavergreen/<repo>/releases/latest/download/SHORT.xml,
#                          <repo> being the name mg_repo gives this repo
#          Exit 1 when SHORT is not declared, 2 on a usage error or a feed whose repo is unknown.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
usage() { echo "usage: updater-identity.sh bundle-id|agent-label|app|feed SHORT" >&2; exit 2; }
[ $# -eq 2 ] || usage
FACT=$1; SHORT=$2
case "$FACT" in bundle-id|agent-label|app|feed) ;; *) usage ;; esac
case "$SHORT" in
  ''|-*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
    echo "updater-identity: \"$SHORT\" is not a short name (lowercase ASCII letters, digits and hyphens)" >&2; exit 2 ;;
esac
[ -d "$(mg_dir)/products/$SHORT" ] \
  || { echo "updater-identity: $SHORT is not a product of this repo; declare it in .mavergreen/products/$SHORT/" >&2; exit 1; }
ID="$(mavergreen_name identifier "$SHORT")"
case "$FACT" in
  bundle-id) printf '%s.updater\n' "$ID" ;;
  agent-label) printf '%s-updatecheck\n' "$ID" ;;
  app) printf 'Library/Application Support/Mavergreen/%s-updater.app\n' "$SHORT" ;;
  feed)
    REPO="$(mg_repo)" \
      || { echo "updater-identity: cannot tell which repo $SHORT's feed is in; set GITHUB_REPOSITORY (OWNER/REPO)" >&2; exit 2; }
    printf 'https://github.com/Mavergreen/%s/releases/latest/download/%s\n' "${REPO#*/}" "$(mavergreen_name feed "$SHORT")" ;;
esac
