#!/usr/bin/env bash
# classes.sh [--index] [--list] [--filter <pattern>] [--since <rev|date>]
# Read-only. Answers "which classes have a wiki class-reference page, which are
# missing one, and which pages are behind the code?" and can emit the grouped
# index body for the Class-Reference page. Never writes anything.
#
#   bash .claude/skills/update-wiki/classes.sh                  # coverage report
#   bash .claude/skills/update-wiki/classes.sh --filter 'hw\.'  # one package
#   bash .claude/skills/update-wiki/classes.sh --index          # index markdown
#   bash .claude/skills/update-wiki/classes.sh --list           # TSV, one row per class
#
# Page naming is fixed: <qualified.Name>-Class-Reference.md, e.g.
# hw.Interface-Class-Reference.md, PRGMSTATE-Class-Reference.md.
#
# obj/stimgen/ is deliberately excluded — it is a separately released submodule
# whose own documentation is authoritative (see CLAUDE.md).
#
# Exit 0 = work to do, 3 = every class covered and nothing changed, 1 = fatal.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$SKILL_DIR" rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$REPO" ]] || { echo "FATAL: not inside a git repository"; exit 1; }
WIKI="${EPSYCH_WIKI:-$(dirname "$REPO")/epsych2.wiki}"
[[ -d "$WIKI/.git" ]] || { echo "FATAL: no wiki clone at $WIKI"; exit 1; }

BLOB="https://github.com/dstolz/epsych2/blob/master"
SUFFIX="-Class-Reference"

MODE=report
FILTER=""
SINCE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --index)  MODE=index; shift ;;
        --list)   MODE=list; shift ;;
        --filter) FILTER="${2:-}"; shift 2 ;;
        --since)  SINCE="${2:-}"; shift 2 ;;
        *)        echo "FATAL: unknown argument '$1'"; exit 1 ;;
    esac
done

cd "$REPO" || exit 1

rule() { printf '%s\n' "-------------------------------------------------------------------------"; }
hdr()  { echo; rule; echo "$1"; rule; }

# ------------------------------------------------------------- what changed --
# A class counts as "changed" when any file under it moved since the baseline.
# Same baseline rule as survey.sh: the .synced-commit marker unless overridden.
MARKER="$WIKI/.synced-commit"
BASE=""
if [[ -n "$SINCE" ]]; then
    BASE="$SINCE"
elif [[ -f "$MARKER" ]]; then
    BASE="$(tr -d ' \r\n\t' < "$MARKER")"
fi
CHANGED=""
BASE_LABEL="(no baseline — nothing reported as behind)"
if [[ -n "$BASE" ]] && git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null; then
    BASE="$(git rev-parse --short "${BASE}^{commit}")"
    BASE_LABEL="${BASE}..HEAD"
    CHANGED="$(git diff --name-only "${BASE}..HEAD"; git status --porcelain | sed 's/^...//; s/.* -> //')"
fi

# --------------------------------------------------------------- the groups --
# Package prefix -> index group. Order here IS the order on the index page;
# within a group the rows are sorted alphabetically. Keep this in sync with
# references/class-pages.md, which explains what belongs where.
# Sets GNUM/GLABEL/GPKG rather than echoing them: this runs once per class, and
# a command substitution per class costs a subshell Windows makes you feel.
group_for() {
    case "$1" in
        epsych.*)        GNUM=1;  GLABEL="Experiment framework";      GPKG="epsych" ;;
        hw.*)            GNUM=2;  GLABEL="Hardware abstraction";      GPKG="hw" ;;
        stimbridge.*)    GNUM=3;  GLABEL="stimgen seam";              GPKG="stimbridge" ;;
        gui.*)           GNUM=4;  GLABEL="GUI components";            GPKG="gui" ;;
        psychophysics.*) GNUM=5;  GLABEL="Psychophysics and analysis"; GPKG="psychophysics" ;;
        teensy.*)        GNUM=6;  GLABEL="Teensy trial programs";     GPKG="teensy" ;;
        eplog.*)         GNUM=7;  GLABEL="Logging";                   GPKG="eplog" ;;
        peripherals.*|util.*) GNUM=8; GLABEL="Peripherals and media"; GPKG="peripherals, util" ;;
        cl_*|ep_*)       GNUM=9;  GLABEL="Paradigms and runtime shells"; GPKG="paradigms/, runtime/" ;;
        *)               GNUM=10; GLABEL="Toolbox level";             GPKG="top level" ;;
    esac
}

# ------------------------------------------------------------ the inventory --
# One record per class: qname \t path \t sortkey \t group \t grouplabel \t summary
inventory() {
    local f pkg base qname dirpath summary part
    while IFS= read -r f; do
        # Package from the +dir components of the path, class from the file name.
        # Pure bash on purpose: one subprocess per class here is 107 per run.
        pkg=""
        IFS='/' read -ra _parts <<< "$f"
        for part in "${_parts[@]}"; do
            [[ "$part" == +* ]] && pkg="${pkg:+$pkg.}${part#+}"
        done
        base="${f##*/}"; base="${base%.m}"
        if [[ -n "$pkg" ]]; then qname="$pkg.$base"; else qname="$base"; fi
        [[ -n "$FILTER" ]] && ! [[ "$qname" =~ $FILTER ]] && continue

        # An @Class folder owns its method files; a loose .m owns only itself.
        if [[ "$f" == *"/@$base/"* ]]; then dirpath="${f%/*}"; else dirpath="$f"; fi

        # Summary = the first line of prose in the class header comment. The
        # house convention opens that block with one or more usage/signature
        # lines ("obj = hw.Bpod(port, Name=Value)"), so those are skipped, as is
        # a bare repeat of the class name; what is left is the sentence a reader
        # wants. Blank lines between classdef and the block are not the end of it.
        summary="$(awk -v cn="$base" '
            /^[[:space:]]*classdef/ { seen = 1; next }
            seen && /^[[:space:]]*%/ {
                inblock = 1
                line = $0
                sub(/^[[:space:]]*%+[[:space:]]?/, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                if (line == "") next
                if (line ~ /^[A-Za-z0-9_.,\[\] ]+=[^=]/) next            # usage: x = Class(...)
                if (line ~ ("^([A-Za-z0-9_]+\\.)*" cn "\\(")) next       # usage: Class(...)
                if (line ~ ("^([A-Za-z0-9_]+\\.)*" cn "$")) next         # the name alone
                # Drop a leading repeat of the class name ("epsych.BitMask
                # Enumerated bit indices...", "BEHAVIORGUI Base class..."), which
                # is a label, not part of the sentence. A BARE name is only a
                # label when it shouts (MATLAB house style) or the sentence
                # continues with a capital: "Runtime state container" must keep
                # its first word, and "Software-backed" is one word, not two.
                sub(("^([A-Za-z0-9_]+\\.)+" cn "[[:space:]]*[-:]?[[:space:]]+"), "", line)
                sub(("^" cn "[[:space:]]*[-:][[:space:]]+"), "", line)
                head = line; sub(/[[:space:]].*$/, "", head)
                rest = line; sub(/^[^[:space:]]+[[:space:]]+/, "", rest)
                if (rest != "" && toupper(head) == toupper(cn) && (head == toupper(cn) || rest ~ /^[A-Z]/))
                    line = rest
                if (line == "") next
                gsub(/\|/, "-", line)                                   # a | would split the table cell
                print substr(line, 1, 140); exit
            }
            seen && inblock && !/^[[:space:]]*%/ { exit }
        ' "$f")"
        [[ -n "$summary" ]] || summary="(no class comment)"

        group_for "$qname"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$qname" "$f" "$dirpath" "$GNUM" "$GLABEL" "$GPKG" "$summary"
    done < <(grep -rl '^[[:space:]]*classdef' --include=*.m obj helpers runtime paradigms 2>/dev/null \
             | grep -v '^obj/stimgen' | sort)
}

changed_p() {   # changed_p <dirpath>  -> "yes" when the baseline range touched it
    [[ -z "$CHANGED" ]] && { echo no; return; }
    if [[ "$CHANGED" == *"$1"* ]]; then echo yes; else echo no; fi
}

url_for() {     # url_for <path> -> GitHub blob URL with + and @ escaped
    local p="${1//+/%2B}"
    echo "$BLOB/${p//@/%40}"
}

INV="$(inventory | sort -f -t$'\t' -k1,1)"
[[ -n "$INV" ]] || { echo "FATAL: no classdef files found (filter '$FILTER'?)"; exit 1; }

# ------------------------------------------------------------------- output --
case "$MODE" in
list)
    printf 'class\tsource\tgroup\tpage\tpage_exists\tchanged_since_baseline\n'
    while IFS=$'\t' read -r qname f dirpath gnum glabel gpkg summary; do
        page="${qname}${SUFFIX}"
        [[ -f "$WIKI/$page.md" ]] && ex=yes || ex=no
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$qname" "$f" "$glabel" "$page" "$ex" "$(changed_p "$dirpath")"
    done <<< "$INV"
    ;;

index)
    # Markdown body for Class-Reference.md, between its BEGIN/END markers.
    # A class with a page is linked; one without shows its source instead, so
    # the index is complete from day one and never contains a broken [[link]].
    # The set of pages that exist, passed in once: a test -f per class would be
    # another 107 processes for an answer one listing already has.
    HAVE=""
    shopt -s nullglob
    for p in "$WIKI"/*"$SUFFIX".md; do b="$(basename "$p" .md)"; HAVE="$HAVE|$b|"; done
    shopt -u nullglob

    echo "$INV" | sort -t$'\t' -k4,4n -k1,1f | awk -F'\t' -v have="$HAVE" -v suffix="$SUFFIX" -v blob="$BLOB" '
    function url(p) { gsub(/\+/, "%2B", p); gsub(/@/, "%40", p); return blob "/" p }
    {
        if ($4 != g) {
            if (g != "") print ""
            g = $4
            printf "### %s — `%s`\n\n", $5, $6
            print "| Class | What it is |"
            print "|---|---|"
        }
        page = $1 suffix
        if (index(have, "|" page "|") > 0)
            printf "| [[%s\\|%s]] | %s |\n", $1, page, $7
        else
            printf "| `%s` — [source](%s) | %s |\n", $1, url($2), $7
    }'
    ;;

report)
    hdr "CLASS PAGE COVERAGE"
    echo "repo:      $REPO   (HEAD $(git rev-parse --short HEAD))"
    echo "wiki:      $WIKI"
    echo "baseline:  $BASE_LABEL"
    [[ -n "$FILTER" ]] && echo "filter:    $FILTER"
    echo "excluded:  obj/stimgen/ (submodule — its own docs are authoritative)"

    missing=""; behind=""; covered=0; total=0
    while IFS=$'\t' read -r qname f dirpath gnum glabel gpkg summary; do
        total=$((total+1))
        page="${qname}${SUFFIX}"
        if [[ -f "$WIKI/$page.md" ]]; then
            covered=$((covered+1))
            [[ "$(changed_p "$dirpath")" == yes ]] && behind="$behind$(printf '%-42s %s\n' "$qname" "$f")"$'\n'
        else
            missing="$missing$(printf '%-42s %-12s %s\n' "$qname" "$glabel" "$f")"$'\n'
        fi
    done <<< "$INV"

    hdr "MISSING A PAGE  ($(echo -n "$missing" | grep -c . || true) of $total)"
    if [[ -z "$missing" ]]; then echo "(none — every class has a page)"; else
        echo "$missing" | sed '/^$/d'
        echo
        echo ">>> Write these from the template in references/class-pages.md."
        echo ">>> Batch by package: a group reviewed together stays consistent."
    fi

    hdr "PAGE BEHIND THE CODE  (source changed since the baseline)"
    if [[ -z "$behind" ]]; then echo "(none)"; else
        echo "$behind" | sed '/^$/d'
        echo
        echo ">>> Re-read each class and refresh its page — diagram included."
        echo ">>> A member added, removed, or renamed changes the diagram, not only the tables."
    fi

    # A page whose class is gone: renamed, deleted, or moved into the submodule.
    hdr "ORPHANED PAGES  (page exists, class does not)"
    orph=0
    known="$(echo "$INV" | cut -f1)"
    shopt -s nullglob
    for p in "$WIKI"/*"$SUFFIX".md; do
        b="$(basename "$p" .md)"; q="${b%$SUFFIX}"
        if ! echo "$known" | grep -qxF "$q"; then
            [[ -n "$FILTER" ]] && ! echo "$q" | grep -qE "$FILTER" && continue
            echo "  $b  -> no class named $q"
            orph=$((orph+1))
        fi
    done
    shopt -u nullglob
    [[ $orph -eq 0 ]] && echo "(none)"

    hdr "INDEX PAGE"
    if [[ -f "$WIKI/Class-Reference.md" ]]; then
        echo "Class-Reference.md exists. Regenerate its table block with:"
    else
        echo "Class-Reference.md is MISSING. Create it (see references/class-pages.md), then:"
    fi
    echo "  bash \"$SKILL_DIR/classes.sh\" --index"
    echo "and paste between the <!-- BEGIN CLASS INDEX --> / <!-- END CLASS INDEX --> markers."

    echo
    rule
    echo "coverage: $covered/$total classes have a page"
    rule
    [[ -z "$missing" && -z "$behind" && $orph -eq 0 ]] && exit 3
    ;;
esac

exit 0
