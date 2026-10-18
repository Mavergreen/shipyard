#!/bin/sh
# platform: host-agnostic
#   usage: setup-family-repo.sh create NAME DESCRIPTION
#          setup-family-repo.sh settle NAME [CHECK...]
#          create makes Mavergreen/NAME, empty and public, then settles it. settle writes the family's
#          repo settings, idempotently: public; issues and projects on, wiki off; every merge method and
#          auto-merge allowed; Actions' token read-only and unable to approve pull requests; once main
#          exists, main as the default branch, after moving the open PRs based on the old default to
#          main (deleting a PR's base closes it, and Renovate then ignores that update), and its branch
#          protection. The protection requires each
#          CHECK, or else every job that ran in the newest green release.yml run off main (a pull request
#          or a branch push, where publish is skipped); with neither, settle leaves main unprotected and
#          says so. Prints what GitHub's API cannot set. Needs gh with admin on the repo.
# spec: SKILL.md "Creating a family repo"
set -eu
org=Mavergreen
die() { echo "setup-family-repo: $*" >&2; exit 1; }
usage() { echo "usage: setup-family-repo.sh create NAME DESCRIPTION | settle NAME [CHECK...]" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || die "needs the gh CLI"
[ $# -ge 2 ] || usage
cmd=$1; name=$2; shift 2
case "$name" in ''|*/*|.*) die "'$name' is not a repo name" ;; esac
repo="$org/$name"

json_string() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

settle() {
  if gh api "repos/$repo/branches/main" --jq .name >/dev/null 2>&1; then main=yes; else main=no; fi
  if [ "$main" = yes ]; then
    old="$(gh api "repos/$repo" --jq .default_branch)" || die "could not read $repo's default branch"
    if [ "$old" != main ]; then
      prs="$(gh pr list -R "$repo" --base "$old" --state open --json number --jq '.[].number')" \
        || die "could not list $repo's open PRs on $old"
      n=0
      for p in $prs; do
        gh pr edit "$p" -R "$repo" --base main >/dev/null || die "could not move $repo#$p from $old to main"
        n=$((n + 1))
      done
      echo "setup-family-repo: moved $n open PRs from $old to main, so deleting $old closes none of them"
    fi
  fi
  {
    printf '{"visibility":"public","has_issues":true,"has_projects":true,"has_wiki":false,'
    printf '"allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":true,'
    printf '"allow_auto_merge":true,"delete_branch_on_merge":false'
    [ "$main" = no ] || printf ',"default_branch":"main"'
    printf '}\n'
  } | gh api -X PATCH "repos/$repo" --input - >/dev/null || die "could not write $repo's settings"
  printf '{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}\n' \
    | gh api -X PUT "repos/$repo/actions/permissions/workflow" --input - >/dev/null \
    || die "could not write $repo's Actions token permissions"
  echo "setup-family-repo: $repo is public, with the family's merge, auto-merge and Actions settings"

  if [ "$main" = no ]; then
    echo "setup-family-repo: $repo has no main yet: settle it again once main exists, to protect main"
  else
    checks="$(printf '%s\n' "$@")"
    if [ $# -eq 0 ]; then
      run="$(gh run list -R "$repo" --workflow release.yml --status success --limit 50 \
               --json databaseId,headBranch --jq '[.[] | select(.headBranch != "main")][0].databaseId // ""')"
      [ -z "$run" ] || checks="$(gh run view "$run" -R "$repo" --json jobs \
                                   --jq '.jobs[] | select(.conclusion != "skipped") | .name')"
    fi
    if [ -z "$checks" ]; then
      echo "setup-family-repo: main is NOT protected: $repo has no green release.yml run off main to read" \
        "its checks from; push a branch, then settle again (or name the checks)"
    else
      ctx="$(printf '%s\n' "$checks" | while IFS= read -r c; do json_string "$c"; echo; done | paste -sd, -)"
      printf '{"required_status_checks":{"strict":false,"contexts":[%s]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}\n' "$ctx" \
        | gh api -X PUT "repos/$repo/branches/main/protection" --input - >/dev/null \
        || die "could not protect $repo's main"
      echo "setup-family-repo: main requires: $(printf '%s\n' "$checks" | paste -sd';' - | sed 's/;/; /g')"
    fi
  fi
  cat <<EOF
setup-family-repo: by hand, since GitHub's API cannot set them:
  - if a workflow runs Mavergreen/mavericks-vm, give $name Write on the mavericks-vm-images package:
    https://github.com/orgs/$org/packages/container/mavericks-vm-images/settings
  - if a workflow runs the pins bot, add $name to the mavergreen-pins-bot installation:
    https://github.com/organizations/$org/settings/installations
EOF
}

case "$cmd" in
  create)
    [ $# -eq 1 ] && [ -n "$1" ] || usage
    if gh repo view "$repo" --json name >/dev/null 2>&1; then die "$repo already exists; settle it instead"; fi
    gh repo create "$repo" --public --description "$1" --disable-wiki >/dev/null || die "could not create $repo"
    echo "setup-family-repo: created $repo (empty)"
    settle ;;
  settle)
    settle "$@" ;;
  *) usage ;;
esac
