#!/usr/bin/env bash
# verify.sh
# Read-only lint of the wiki clone: broken [[page]] links, missing images,
# unreferenced images, orphaned pages, and links into the code repo that point
# at files which no longer exist. GitHub renders a broken wiki link as plain
# text with no warning, so this is the only check there is.
#
#   bash .claude/skills/update-wiki/verify.sh
#
# Exit 0 = clean, 2 = problems found, 1 = fatal.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$SKILL_DIR" rev-parse --show-toplevel 2>/dev/null)"
WIKI="${EPSYCH_WIKI:-$(dirname "$REPO")/epsych2.wiki}"
[[ -d "$WIKI/.git" ]] || { echo "FATAL: no wiki clone at $WIKI"; exit 1; }

cd "$WIKI" || exit 1
problems=0
echo "Linting $WIKI"

# --------------------------------------------------- [[wiki links]] resolve --
echo
echo "[[wiki links]]"
n=0
while IFS= read -r hit; do
    file="${hit%%:*}"
    target="${hit#*:}"
    target="${target#\[\[}"; target="${target%\]\]}"
    target="${target##*|}"                       # [[Display|Page-Name]] -> Page-Name
    target="${target%%#*}"                       # drop any #anchor
    target="$(echo "$target" | sed 's/^ *//; s/ *$//')"
    [[ -z "$target" ]] && continue
    [[ -f "${target// /-}.md" ]] && continue     # GitHub treats space and - alike
    echo "  $file -> [[$target]] : no such page"
    n=$((n+1))
done < <(grep -oHE '\[\[[^]]+\]\]' *.md)
[[ $n -eq 0 ]] && echo "  ok"
problems=$((problems+n))

# ------------------------------------------------------- images resolve ------
echo
echo "image references"
n=0
while IFS= read -r hit; do
    file="${hit%%:*}"; img="${hit#*:}"
    [[ -f "$img" ]] && continue
    echo "  $file -> $img : missing"
    n=$((n+1))
done < <( { grep -oHE '\]\(images/[^)]+\)' *.md | sed -E 's/:\]\(/:/; s/\)$//'
           grep -oHE 'src="images/[^"]+"' *.md | sed -E 's/:src="/:/; s/"$//'; } | sort -u )
[[ $n -eq 0 ]] && echo "  ok"
problems=$((problems+n))

# --------------------------------------------------- unreferenced images -----
echo
echo "unused images (not an error; a rewritten section leaves these behind)"
n=0
while IFS= read -r img; do
    grep -qF "$img" *.md && continue
    echo "  $img"
    n=$((n+1))
done < <(find images -type f \( -name '*.png' -o -name '*.svg' -o -name '*.jpg' \) | sed 's#\\#/#g' | sort)
[[ $n -eq 0 ]] && echo "  none"

# ------------------------------------------------------- orphaned pages ------
echo
echo "pages not linked from _Sidebar.md or Home.md"
n=0
for f in *.md; do
    case "$f" in _Sidebar.md|_Footer.md|Home.md) continue ;; esac
    page="${f%.md}"
    grep -qF "$page" _Sidebar.md Home.md && continue
    echo "  $page"
    n=$((n+1))
done
[[ $n -eq 0 ]] && echo "  ok"
problems=$((problems+n))

# ------------------------------------- links into the code repo still exist --
echo
echo "links into the code repo (blob/tree URLs)"
n=0
while IFS= read -r hit; do
    file="${hit%%:*}"; url="${hit#*:}"
    path="$(echo "$url" | sed -E 's#.*/(blob|tree)/master/##; s/[)#].*//')"
    path="$(printf '%b' "${path//%/\\x}")"       # %2B -> +
    [[ -z "$path" ]] && continue
    [[ -e "$REPO/$path" ]] && continue
    echo "  $file -> $path : not in the repo"
    n=$((n+1))
done < <(grep -ohHE 'https://github\.com/dstolz/epsych2/(blob|tree)/master/[^) "]+' *.md | sort -u)
[[ $n -eq 0 ]] && echo "  ok"
problems=$((problems+n))

echo
if [[ $problems -eq 0 ]]; then
    echo "PASS - no broken links, missing images, or orphaned pages"
    exit 0
fi
echo "$problems problem(s) found"
exit 2
