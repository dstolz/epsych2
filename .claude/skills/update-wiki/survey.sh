#!/usr/bin/env bash
# survey.sh [--full] [--since <rev|date>]
# Read-only. Answers "what changed in epsych2 since the wiki was last synced,
# and which wiki pages does that touch?" in one shot. Never writes anything.
#
#   bash .claude/skills/update-wiki/survey.sh
#   bash .claude/skills/update-wiki/survey.sh --since e6e9767
#   EPSYCH_WIKI=/c/src/epsych2.wiki bash .claude/skills/update-wiki/survey.sh
#
# Exit 0 = work to do, 3 = nothing changed since the baseline, 1 = fatal.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$SKILL_DIR" rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$REPO" ]] || { echo "FATAL: not inside a git repository"; exit 1; }
WIKI="${EPSYCH_WIKI:-$(dirname "$REPO")/epsych2.wiki}"
PAGEMAP="$SKILL_DIR/pagemap.tsv"

FULL=0
SINCE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)  FULL=1; shift ;;
        --since) SINCE="${2:-}"; shift 2 ;;
        *)       echo "FATAL: unknown argument '$1'"; exit 1 ;;
    esac
done

if [[ ! -d "$WIKI/.git" ]]; then
    echo "FATAL: no wiki clone at $WIKI"
    echo "  git clone https://github.com/dstolz/epsych2.wiki.git \"$WIKI\""
    echo "  (or set EPSYCH_WIKI to where it lives)"
    exit 1
fi

rule() { printf '%s\n' "-------------------------------------------------------------------------"; }
hdr()  { echo; rule; echo "$1"; rule; }

# ---------------------------------------------------------------- baseline ---
MARKER="$WIKI/.synced-commit"
BASE=""
BASE_SRC=""
if [[ -n "$SINCE" ]]; then
    BASE="$SINCE"; BASE_SRC="--since argument"
elif [[ -f "$MARKER" ]]; then
    BASE="$(tr -d ' \r\n\t' < "$MARKER")"; BASE_SRC=".synced-commit marker"
fi

RANGE=""
SINCE_DATE=""
if [[ -n "$BASE" ]] && git -C "$REPO" rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
    BASE="$(git -C "$REPO" rev-parse --short "${BASE}^{commit}")"
    RANGE="${BASE}..HEAD"
else
    if [[ -n "$BASE" ]]; then
        echo "WARNING: baseline '$BASE' ($BASE_SRC) is not a commit in this repo; falling back to the wiki's last commit date."
    fi
    SINCE_DATE="$(git -C "$WIKI" log -1 --format=%cI 2>/dev/null)"
    BASE_SRC="wiki's last commit date ($SINCE_DATE)"
    [[ -n "$SINCE_DATE" ]] || { echo "FATAL: wiki repo has no commits and no baseline was given"; exit 1; }
fi

log_args=(--no-merges)
if [[ -n "$RANGE" ]]; then log_args+=("$RANGE"); else log_args+=(--since="$SINCE_DATE"); fi

hdr "BASELINE"
echo "repo:      $REPO   (branch $(git -C "$REPO" rev-parse --abbrev-ref HEAD), HEAD $(git -C "$REPO" rev-parse --short HEAD))"
echo "wiki:      $WIKI   (branch $(git -C "$WIKI" rev-parse --abbrev-ref HEAD))"
echo "baseline:  ${RANGE:-since $SINCE_DATE}   from $BASE_SRC"

# ------------------------------------------------------------- wiki status ---
hdr "WIKI WORKING TREE"
WIKI_DIRTY="$(git -C "$WIKI" status --porcelain)"
if [[ -z "$WIKI_DIRTY" ]]; then
    echo "clean"
else
    echo "$WIKI_DIRTY"
    echo
    echo ">>> The wiki already has uncommitted edits. Read them before writing more —"
    echo ">>> an earlier session may have done part of this update."
fi
AHEAD="$(git -C "$WIKI" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')"
echo
echo "unpushed commits: $AHEAD   (publishing = git push; ask the user first)"

# ---------------------------------------------------------------- commits ----
hdr "REPO COMMITS SINCE BASELINE"
COMMITS="$(git -C "$REPO" log "${log_args[@]}" --format='%h  %ad  %s' --date=short)"
if [[ -z "$COMMITS" ]]; then
    echo "(none)"
else
    echo "$COMMITS"
fi

# ------------------------------------------------------------ changed files --
if [[ -n "$RANGE" ]]; then
    FILES="$(git -C "$REPO" diff --name-only "$RANGE")"
else
    FILES="$(git -C "$REPO" log "${log_args[@]}" --name-only --format='' | sed '/^$/d' | sort -u)"
fi
UNCOMMITTED="$(git -C "$REPO" status --porcelain)"

hdr "CHANGED FILES"
if [[ -z "$FILES" ]]; then
    echo "(none)"
else
    echo "$FILES" | sort
fi

if [[ -n "$UNCOMMITTED" ]]; then
    hdr "UNCOMMITTED IN THE CODE REPO"
    echo "$UNCOMMITTED"
    echo
    echo ">>> These are NOT in the baseline range. Documenting unpushed code is fine,"
    echo ">>> but say so — the wiki is public and the code may not be on GitHub yet."
    FILES="$FILES"$'\n'"$(echo "$UNCOMMITTED" | sed 's/^...//' | sed 's/.* -> //')"
fi

if [[ -z "$(echo "$FILES" | sed '/^$/d')" ]]; then
    hdr "NOTHING TO DO"
    echo "No repo changes since the baseline."
    exit 3
fi

# ------------------------------------------------------------ page mapping ---
hdr "WIKI PAGES TO REVIEW  (hint, from pagemap.tsv — verify by reading the page)"
if [[ -f "$PAGEMAP" ]]; then
    echo "$FILES" | sed '/^$/d' | sort -u | awk -v map="$PAGEMAP" '
    BEGIN {
        FS = "\t"
        while ((getline line < map) > 0) {
            if (line ~ /^#/ || line == "") continue
            n = split(line, f, "\t")
            if (n < 2) continue
            prefix[++np] = f[1]; pages[np] = f[2]; docs[np] = (n >= 3 ? f[3] : "")
        }
        FS = "\n"
    }
    {
        for (i = 1; i <= np; i++)
            if (index($0, prefix[i]) == 1) { hit[i] = 1; ex[i] = ex[i] $0 " " }
    }
    END {
        any = 0
        for (i = 1; i <= np; i++) if (hit[i]) {
            any = 1
            printf "\n%s\n  wiki: %s\n  docs: %s\n", prefix[i], pages[i], docs[i]
            printf "  from: %s\n", substr(ex[i], 1, 160)
        }
        if (!any) print "(no pagemap row matched — decide by reading the diff)"
    }'
else
    echo "(pagemap.tsv missing)"
fi

# ------------------------------------------------------- screenshot hints ----
hdr "SCREENSHOT HINTS"
gui_hits="$(echo "$FILES" | grep -E '^(obj/\+gui/|obj/\+epsych/@(RunExpt|ProtocolDesigner|SelfTest)|obj/\+teensy/@TrialDesigner|obj/\+psychophysics/@Staircase|runtime/guis/)' | sort -u)"
if [[ -z "$gui_hits" ]]; then
    echo "No GUI-facing files changed; existing screenshots are probably still accurate."
else
    echo "GUI code changed — the published shots may be stale:"
    echo "$gui_hits" | sed 's/^/  /'
    echo
    echo "Regenerate with (see references/screenshots.md for the exact commands):"
    echo "  tmp/generate_wiki_screenshots.m        full-window shots  -> wiki images/"
    echo "  tmp/generate_component_screenshots.m   per-component shots -> wiki images/components/"
    echo "  tmp/generate_protocol_designer_screenshots.m  -> documentation/design/images/"
fi

# ----------------------------------------------------------------- warnings --
hdr "WARNINGS"
warned=0
newdocs="$(echo "$FILES" | grep -E '^documentation/.*\.md$' | sort -u)"
if [[ -n "$newdocs" ]]; then
    echo "* Repo docs changed — these are AUTHORITATIVE; the wiki summarizes them:"
    echo "$newdocs" | sed 's/^/    /'
    warned=1
fi
if echo "$FILES" | grep -q '^documentation/overviews/'; then
    echo "* documentation/overviews/ changed — regenerate the 1:1 wiki mirror page(s)."
    warned=1
fi
if echo "$FILES" | grep -q '^obj/stimgen'; then
    echo "* The stimgen submodule pointer moved — stimgen's own docs are authoritative;"
    echo "  link to them, do not copy the class inventory into this wiki."
    warned=1
fi
newclass="$(git -C "$REPO" diff --diff-filter=A --name-only ${RANGE:-} 2>/dev/null | grep -E '^obj/\+[a-z]+/@[A-Za-z0-9_]+/' | sed -E 's#(^obj/\+[a-z]+/@[A-Za-z0-9_]+)/.*#\1#' | sort -u)"
if [[ -n "$newclass" ]]; then
    echo "* New class folder(s) — a new page or a new section may be needed, plus a"
    echo "  _Sidebar.md and Home.md entry if it is a page:"
    echo "$newclass" | sed 's/^/    /'
    warned=1
fi
[[ $warned -eq 0 ]] && echo "(none)"

# ------------------------------------------------------------------- patch ---
if [[ $FULL -eq 1 ]]; then
    hdr "FULL PATCH"
    if [[ -n "$RANGE" ]]; then
        git -C "$REPO" diff "$RANGE"
    else
        git -C "$REPO" log "${log_args[@]}" -p
    fi
fi

echo
rule
echo "Next: read references/page-map.md, then edit pages in $WIKI"
echo "Then: bash \"$SKILL_DIR/verify.sh\""
rule
