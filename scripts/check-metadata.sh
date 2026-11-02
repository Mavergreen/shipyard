#!/bin/sh
# platform: host-agnostic
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
. "$SELF/lib/vercmp.sh"
. "$SELF/deviation-reason.sh"
MAVERGREEN_ROOT="$(pwd)"
shipyard_deviations . >/dev/null 2>&1 || :
REL=.github/workflows/release.yml
TAB="$(printf '\t')"
CR="$(printf '\r')"

if [ -f "$REL" ]; then
  chk_ran upstream-complete
  if [ ! -d .mavergreen/upstream ]; then
    chk_fail upstream-complete "there is no .mavergreen/upstream/" \
      "the release version is derived from it, so without it there is no version to cut" \
      "create .mavergreen/upstream/ with VERSION (or COMMIT or PIN) and a one-line description"
  else
    _kinds=""
    for _k in VERSION COMMIT PIN; do
      if mg_has "upstream/$_k"; then _kinds="$_kinds $_k"; fi
    done
    set -- $_kinds
    if [ "$#" -eq 0 ]; then
      chk_fail upstream-complete ".mavergreen/upstream/ has none of VERSION, COMMIT or PIN" \
        "the release version is derived from one of them" \
        "add .mavergreen/upstream/VERSION holding the upstream's version (or COMMIT or PIN)"
    elif [ "$#" -gt 1 ]; then
      chk_fail upstream-complete ".mavergreen/upstream/ has more than one of VERSION, COMMIT or PIN:$_kinds" \
        "which one the version comes from would be a guess" \
        "keep the one Renovate tracks and delete the others"
    elif [ "$1" != VERSION ] && ! mg_has hooks/derive-upstream-version; then
      chk_fail upstream-complete ".mavergreen/upstream/$1 has no .mavergreen/hooks/derive-upstream-version" \
        "a $1 is not a version, and nothing turns it into one" \
        "add .mavergreen/hooks/derive-upstream-version, printing the upstream's version"
    fi
    mg_has upstream/description \
      || chk_fail upstream-complete ".mavergreen/upstream/ has no description" \
           "nothing says what the upstream is" \
           "add .mavergreen/upstream/description: one line saying what the upstream is"
  fi
else
  chk_notrun upstream-complete "no $REL, so this is not a product repo and the rule has nothing to hold to"
fi

chk_ran value-file-line
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/check-metadata.XXXXXX")"
trap 'rm -rf "$w"' EXIT
if [ -d .mavergreen ]; then
  find .mavergreen -type f | LC_ALL=C sort > "$w/files"
  while IFS= read -r f; do
    rel="${f#.mavergreen/}"
    case "/$rel" in
      */.*|/hooks/*|*/hooks/*|/config/*|/release-notes/*|*.md) continue ;;
    esac
    case "${rel##*/}" in
      reason|revisit|untracked|tracked-by|role|watch|target|union|intree) continue ;;
    esac
    shipyard_deviated value-file-line "$f" >/dev/null && continue
    bad=""
    if grep -q "$CR" "$f"; then
      bad="it holds a carriage return (a CRLF line ending)"
    else
      n=0
      while IFS= read -r l || [ -n "$l" ]; do
        n=$((n + 1))
        if [ "$n" -eq 1 ]; then
          case "$l" in
            [" $TAB"]*|*[" $TAB"]) bad="line 1 has a space or a tab before or after the value" ;;
          esac
          if [ "$rel" = upstream/VERSION ]; then
            case "$l" in [vV][0-9]*) bad="${bad:-line 1 starts with a v}" ;; esac
          fi
        elif [ "$n" -eq 2 ]; then
          case "$l" in '# renovate:'*) ;; *) bad="${bad:-line 2 is not a '# renovate:' annotation}" ;; esac
        else
          bad="${bad:-it has more than two lines}"
          break
        fi
      done < "$f"
    fi
    [ -z "$bad" ] || chk_fail value-file-line "$f is not a value file: $bad" \
      "every reader takes line 1 as the value, so whitespace, a CR or a v becomes part of it, and any line 2 but a Renovate annotation is a value nobody reads" \
      "write the value alone on line 1, and nothing after it but a '# renovate: datasource=... depName=...' line"
  done < "$w/files"
fi

chk_ran pin-well-formed
for _p in upstream $(mg_list ingredients | sed 's|^|ingredients/|'); do
  mg_has "$_p/PIN" || continue
  _f=".mavergreen/$_p/PIN"
  if ! _c="$(mg_pin_commit "$_p")"; then
    _bad="line 1 has no @, so it names no commit"
  else
    case "$_c" in
      *[!0-9a-f]*) _bad="the commit $_c holds a character that is not a lowercase hex digit" ;;
      *) if [ "${#_c}" -ne 40 ]; then _bad="the commit $_c is ${#_c} characters, not 40"; else _bad=""; fi ;;
    esac
  fi
  [ -z "$_bad" ] || chk_fail pin-well-formed "$_f is not <ref>@<commit>: $_bad" \
    "a PIN names a ref and the full commit it pointed at, so the build and Renovate fetch exactly that commit" \
    "write line 1 as <ref>@<the full 40-character lowercase commit the ref names>"
done

chk_ran repackage-wiring
: > "$w/callers"
for _f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$_f" ] || continue
  grep -v '^[[:space:]]*#' "$_f" | grep -Fq 'repackage-on-ingredient-bump.yml' && echo "$_f" >> "$w/callers"
done
if [ -n "$(mg_list ingredients)" ]; then _has_ings=1; else _has_ings=""; fi
if [ -s "$w/callers" ]; then
  while IFS= read -r _f; do
    [ -n "$_has_ings" ] || chk_fail repackage-wiring "$_f calls repackage-on-ingredient-bump.yml but .mavergreen/ingredients/ holds no ingredient" \
      "there is nothing for it to repackage on, so every push would run a job that can only skip" \
      "delete $_f, or describe the ingredients under .mavergreen/ingredients/"
    if grep -v '^[[:space:]]*#' "$_f" | grep -Eq '^[[:space:]]*(paths|paths-ignore|own-upstream-paths):'; then
      chk_fail repackage-wiring "$_f filters on paths or names own-upstream-paths" \
        "the decision reads .mavergreen/ and decides from what changed, so a filter either hides a change it needs or repeats what the tree says" \
        "delete the paths:, paths-ignore: and own-upstream-paths: lines; the caller has no filter"
    fi
  done < "$w/callers"
elif [ -n "$_has_ings" ] && ! shipyard_deviated repackage-wiring >/dev/null; then
  chk_fail repackage-wiring "the repo has ingredients under .mavergreen/ingredients/ but no workflow calls repackage-on-ingredient-bump.yml" \
    "a bumped ingredient would change what ships and release nothing" \
    "add .github/workflows/repackage-on-ingredient-bump.yml calling Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1, with no paths: filter"
fi

_prods="$(mg_list products)"
chk_ran release-has-product
if [ -f "$REL" ] && [ -z "$_prods" ]; then
  chk_fail release-has-product "the repo has $REL but no product under .mavergreen/products/" \
    "a release ships products, and their names, identifiers and requirements are read from there" \
    "add .mavergreen/products/<short name>/noun holding each shipped product's display noun"
fi

if [ -z "$_prods" ]; then
  for _id in product-complete requires-pinned requires-min; do
    chk_notrun "$_id" "there is no product under .mavergreen/products/"
  done
else
  chk_ran product-complete
  chk_ran requires-pinned
  chk_ran requires-min
fi
for _s in $_prods; do
  _d="products/$_s"
  _at=".mavergreen/$_d"
  if [ ! -d "$(mg_dir)/$_d" ]; then
    chk_fail product-complete "$_at is not a directory" \
      "each product is a directory of one value per file" \
      "make $_at a directory holding at least its noun"
    continue
  fi
  _rc=0; mavergreen_name_ok "$_s" || _rc=$?
  case "$_rc" in
    1) chk_fail product-complete "the short name \"$_s\" ($_at) is not lowercase ASCII letters, digits and hyphens, starting with a letter or digit" \
         "the short name becomes a directory under the prefix and part of the pkg identifier" \
         "rename $_at to a short name of a-z, 0-9 and -" ;;
    2) chk_fail product-complete "the short name \"$_s\" ($_at) is reserved by the install layout" \
         "the prefix already uses $_s for the link farm, var/, the helper or its base component" \
         "rename $_at to a short name that is not one of: $mavergreen_reserved_names" ;;
  esac
  if [ -z "$(mg_value "$_d/noun" 2>/dev/null)" ]; then
    chk_fail product-complete "$_at has no noun" \
      "every name the product shows is derived from its display noun" \
      "add $_at/noun holding the display noun, as in OpenSSH, Go or Porthole"
  fi
  if mg_has "$_d/app"; then
    _v="$(mg_value "$_d/app" 2>/dev/null)" || _v=""
    case "$_v" in
      noun|upstream) ;;
      *) chk_fail product-complete "$_at/app holds \"$_v\", which is neither noun nor upstream" \
           "it says how the installed .app is named, and nothing names it any other way" \
           "write noun (the bundle is <noun>.app) or upstream (upstream's own bundle name is kept)" ;;
    esac
  fi
  if mg_has "$_d/edition"; then
    _v="$(mg_value "$_d/edition" 2>/dev/null)" || _v=""
    [ "$_v" = system ] || chk_fail product-complete "$_at/edition holds \"$_v\", which is not system" \
      "system is the one edition the install layout knows" \
      "write system for a system edition in /usr, or delete $_at/edition for a regular one"
  fi
  for _dep in $(mg_list "$_d/requires"); do
    _r="$_d/requires/$_dep"
    _rat=".mavergreen/$_r"
    _kind="$(mg_value "$_r/kind" 2>/dev/null)" || _kind=""
    case "$_kind" in
      library|data|service|tool|external) ;;
      '') chk_fail product-complete "$_rat has no kind" \
            "the kind says whether the Engine installs the dependency, shares it or leaves it to the user" \
            "add $_rat/kind holding one of library, data, service, tool or external" ;;
      *) chk_fail product-complete "$_rat/kind holds \"$_kind\", which is not a kind" \
           "the kind says whether the Engine installs the dependency, shares it or leaves it to the user, and an unknown one says neither" \
           "write one of library, data, service, tool or external" ;;
    esac
    mg_has "$_r/why" || chk_fail product-complete "$_rat has no why" \
      "nothing else says what the product does with the dependency" \
      "add $_rat/why: one line saying what the product does with it"
    if [ "$_kind" = external ] && ! mg_has "$_r/where"; then
      chk_fail product-complete "$_rat is external and has no where" \
        "the Engine never installs an external dependency, so the preinstall can only say where to get it" \
        "add $_rat/where: one line saying where to get it"
    fi
    case "$_kind" in library|data|service|tool) ;; *) continue ;; esac
    if [ "$_kind" = library ] && ! mg_has "$_r/min"; then
      chk_fail requires-min "$_rat is a library and has no min" \
        "a library states its ABI floor, which the preinstall refuses below, rather than defaulting to the build pin" \
        "add $_rat/min holding the lowest $_dep release the product's binaries load against"
    fi
    _i="ingredients/$_dep"
    if [ ! -d "$(mg_dir)/$_i" ]; then
      chk_fail requires-pinned "$_rat names no ingredient: there is no .mavergreen/$_i/" \
        "a $_kind requirement is installed, built and tested at one pin, and only an ingredient holds it" \
        "add .mavergreen/$_i/ with its pin and a product file holding $_dep"
      continue
    fi
    _prod="$(mg_value "$_i/product" 2>/dev/null)" || _prod=""
    [ "$_prod" = "$_dep" ] || chk_fail requires-pinned ".mavergreen/$_i/product holds \"$_prod\", not $_dep, which $_rat names" \
      "the pin must be a release of the product required, or it pins something else" \
      "write $_dep in .mavergreen/$_i/product"
    mg_has "$_r/min" || continue
    _min="$(mg_value "$_r/min" 2>/dev/null)" || _min=""
    _pin=""
    if mg_has "$_i/VERSION"; then
      _pin="$(mg_value "$_i/VERSION")"
    elif _par="$(mg_value "$_i/from" 2>/dev/null)" && [ -n "$_par" ]; then
      _pin="$(mg_value "ingredients/$_par/VERSION" 2>/dev/null)" || _pin=""
    else
      _pin="$(mg_pin_ref "$_i" 2>/dev/null)" || _pin=""
    fi
    _cmp=0; _ord="$(mavergreen_vercmp "$_min" "$_pin")" || _cmp=$?
    if [ "$_cmp" -ne 0 ]; then
      chk_fail requires-min "$_rat/min \"$_min\" cannot be ordered against .mavergreen/$_i's pin \"$_pin\"" \
        "a min the comparator cannot order with the pin might be above it, so it is refused rather than passed unproven" \
        "write the min, and the pin, as dotted numbers with at most a -mavericks.N or pN suffix"
    elif [ "$_ord" = 1 ]; then
      chk_fail requires-min "$_rat/min $_min is above .mavergreen/$_i's pin $_pin" \
        "the preinstall would refuse the very release the product was built and tested with" \
        "lower the min to the lowest $_dep release the product works with, at or below $_pin"
    fi
  done
done

_ings="$(mg_list ingredients)"
if [ -z "$_ings" ]; then
  for _id in ingredient-complete watch-matches from-parent; do
    chk_notrun "$_id" "there is no ingredient under .mavergreen/ingredients/"
  done
  exit "$chk_status"
fi
chk_ran ingredient-complete
chk_ran watch-matches
chk_ran from-parent
_tracked=""
for _n in $_ings; do
  _d="ingredients/$_n"
  _at=".mavergreen/$_d"
  if [ ! -d "$(mg_dir)/$_d" ]; then
    chk_fail ingredient-complete "$_at is not a directory" \
      "each ingredient is a directory of one value per file" \
      "make $_at a directory holding its VERSION (or PIN or from), role, description and why"
    continue
  fi
  for _r in role description why; do
    mg_has "$_d/$_r" || chk_fail ingredient-complete "$_at has no $_r" \
      "the ingredients table, the notes and provisioning read it from there" \
      "add $_at/$_r"
  done
  if mg_has "$_d/role"; then
    _roles="$(mg_lines "$_d/role")"
    [ -n "$_roles" ] || chk_fail ingredient-complete "$_at/role is empty" \
      "provisioning picks ingredients by role" \
      "write one or more of linked, shipped, build-only, test or reference, one per line"
    for _r in $_roles; do
      case "$_r" in
        linked|shipped|build-only|test|reference) ;;
        *) chk_fail ingredient-complete "$_at/role names \"$_r\", which is not a role" \
             "provisioning picks ingredients by role, and an unknown one is picked by nothing" \
             "use linked, shipped, build-only, test or reference, one per line" ;;
      esac
    done
  fi
  if mg_has "$_d/PIN" && mg_has "$_d/VERSION"; then
    chk_fail ingredient-complete "$_at has both PIN and VERSION" \
      "which one is the pin would be a guess" \
      "keep the one the build reads and delete the other"
  fi
  mg_has "$_d/from" && continue
  _t=""
  for _f in $(mg_list "$_d"); do
    mg_renovate "$_d/$_f" >/dev/null && _t="$_t line-2:$_f"
  done
  mg_has "$_d/untracked" && _t="$_t untracked"
  mg_has "$_d/tracked-by" && _t="$_t tracked-by"
  set -- $_t
  if [ "$#" -ne 1 ]; then
    if [ "$#" -eq 0 ]; then _how="none of them"; else _how="$*"; fi
    chk_fail ingredient-complete "$_at needs exactly one of a Renovate line 2, an untracked file or a tracked-by file, and has $_how" \
      "it says whether, and how, a new release of the ingredient reaches this repo" \
      "give the value file Renovate bumps its '# renovate:' line 2, or say why nothing can in untracked, or which built-in manager does in tracked-by"
  fi
done

for _n in $_ings; do
  chk_selected watch-matches || break
  mg_has "ingredients/$_n/watch" || continue
  if [ -z "$_tracked" ]; then
    _tracked="$w/tracked"
    chk_tracked_files > "$_tracked" || exit 2
  fi
  while IFS= read -r _g; do
    [ -n "$_g" ] || continue
    [ -n "$(mg_glob_hits "$_g" "$_tracked")" ] || chk_fail watch-matches ".mavergreen/ingredients/$_n/watch names \"$_g\", which matches no tracked file" \
      "a change under it is meant to repackage, and a glob that matches nothing never fires" \
      "correct the glob to match the tracked paths it means, or delete the line"
  done <<EOF
$(mg_lines "ingredients/$_n/watch")
EOF
done

for _n in $_ings; do
  _p="$(mg_value "ingredients/$_n/from" 2>/dev/null)" || continue
  _at=".mavergreen/ingredients/$_n"
  for _k in VERSION PIN; do
    if mg_has "ingredients/$_n/$_k"; then
      chk_fail from-parent "$_at has both from and $_k" \
        "its version is its parent's, and a pin of its own could disagree with it" \
        "delete $_at/$_k"
    fi
  done
  [ "$_p" = self ] && continue
  if [ -z "$_p" ] || [ ! -d "$(mg_dir)/ingredients/$_p" ]; then
    chk_fail from-parent "$_at/from names \"$_p\", which is not an ingredient here" \
      "a from ingredient comes from its parent's release, so the parent must be pinned in this repo" \
      "name an ingredient under .mavergreen/ingredients/ (or self, for this run's build), or add .mavergreen/ingredients/$_p/"
  elif ! mg_has "ingredients/$_p/product"; then
    chk_fail from-parent "$_at/from names $_p, which has no product" \
      "only a family product's release can publish this one beside it" \
      "add .mavergreen/ingredients/$_p/product naming its family short name, or point from at the ingredient whose release ships this one"
  fi
done

exit "$chk_status"
