#!/usr/bin/env bash
# Lint a formatted reference and file it under the right year in the Publications
# wiki page. The formatting is yours; this script only checks and places it.
#
#   insert.sh entry.txt              lint, then insert
#   insert.sh --dry-run entry.txt    lint only, change nothing
#   insert.sh --force entry.txt      insert past a same-title refusal
#   insert.sh --lint                 lint the whole page, insert nothing
#
# The entry file holds ONE line -- the finished markdown list item, UTF-8, no
# trailing newline issues. Write it with the Write tool, not a shell heredoc:
# the tool layer eats backslashes and mangles en dashes on the way through.
#
# Exit: 0 done · 1 usage · 2 rejected (format) · 4 duplicate DOI
#
# NOTE: MSYS grep -F ABORTS when its output is suppressed (-q or >/dev/null),
# so every substring test here uses awk index(). Do not "simplify" them.

set -uo pipefail

WIKI="${EPSYCH_WIKI:-/c/src/epsych2.wiki}"
PAGE="$WIKI/Publications.md"

DRY=0
LINTONLY=0
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1; shift ;;
        --force)   FORCE=1; shift ;;
        --lint)    LINTONLY=1; shift ;;
        -h|--help) echo "usage: insert.sh [--dry-run] [--force] <entry-file> | insert.sh --lint"; exit 0 ;;
        *) break ;;
    esac
done
if [ "$LINTONLY" = 0 ] && [ $# -eq 0 ]; then
    echo "usage: insert.sh [--dry-run] [--force] <entry-file> | insert.sh --lint" >&2
    exit 1
fi

[ -f "$PAGE" ] || { echo "ERROR: $PAGE not found (set EPSYCH_WIKI)" >&2; exit 2; }

lint_page() {
    echo "PAGE CHECK: $PAGE"
    awk '
        /<!-- publications:begin -->/ { inb = 1; next }
        /<!-- publications:end -->/   { inb = 0; next }
        !inb { next }
        /^### / {
            y = $2 + 0
            if (y < 1900 || y > 2200) { printf "  BAD HEADING: %s\n", $0; bad++ }
            if (prev && y >= prev)    { printf "  OUT OF ORDER: ### %s follows ### %s\n", y, prev; bad++ }
            prev = y; cur = y; next
        }
        /^- / {
            n++
            if (match($0, /\(([12][0-9]{3})\)\./)) {
                ey = substr($0, RSTART + 1, 4) + 0
                if (ey != cur) { printf "  WRONG YEAR BLOCK (%s under ### %s): %.70s\n", ey, cur, $0; bad++ }
            } else { printf "  NO YEAR: %.70s\n", $0; bad++ }
            if (!index($0, "https://"))  { printf "  NO LINK: %.70s\n", $0; bad++ }
            if ($0 ~ / $/)               { printf "  TRAILING SPACE: %.70s\n", $0; bad++ }
            d = $NF; sub(/^https:\/\/doi\.org\//, "", d)
            if (seen[tolower(d)]++)      { printf "  DUPLICATE: %s\n", d; bad++ }
        }
        END { printf "  %d entries, %d problems\n", n, bad + 0; exit (bad > 0) }
    ' "$PAGE"
}

if [ "$LINTONLY" = 1 ]; then
    lint_page
    exit $?
fi

ENTRYFILE="${1:-}"
[ -f "$ENTRYFILE" ] || { echo "ERROR: entry file '$ENTRYFILE' not found" >&2; exit 1; }

# --- the entry must be exactly one list line --------------------------------
LINES="$(awk 'NF { n++ } END { print n + 0 }' "$ENTRYFILE")"
[ "$LINES" = "1" ] || { echo "ERROR: entry file holds $LINES non-empty lines; it must hold exactly 1" >&2; exit 2; }
ENTRY="$(awk 'NF { print; exit }' "$ENTRYFILE")"

# --- lint the entry ---------------------------------------------------------
FATAL=0
say()  { printf '  %s\n' "$1"; }
fail() { say "REJECT: $1"; FATAL=1; }
warn() { say "WARN:   $1"; }

echo "ENTRY"
echo "-----"
echo "$ENTRY"
echo
echo "LINT"
echo "----"

case "$ENTRY" in "- "*) ;; *) fail "does not start with '- '" ;; esac

YEAR="$(awk '{ if (match($0, /\(([12][0-9]{3})\)\. /)) print substr($0, RSTART + 1, 4) }' <<<"$ENTRY")"
[ -n "$YEAR" ] || fail "no '(YEAR). ' -- the year in parentheses, then a period and a space"

# The DOI is the last whitespace-delimited token, and nothing may follow it. A
# trailing period is the common submission error, and it is not cosmetic: it
# defeats the duplicate check and breaks the link on GitHub.
LAST="$(awk '{ print $NF }' <<<"$ENTRY")"
DOI=""
case "$LAST" in
    *[.,\;\)]) fail "the link ends in punctuation ('${LAST: -1}') -- it must be the last character on the line" ;;
    https://doi.org/10.*) DOI="${LAST#https://doi.org/}" ;;
    https://*)
        DOI="$LAST"
        warn "not a doi.org link -- acceptable only for a record that has no DOI (thesis, report); everything with a DOI uses one" ;;
    *) fail "must END with a bare https://doi.org/... link -- no trailing period, no markdown link, no PubMed URL" ;;
esac

STARS="$(grep -oE '\*' <<<"$ENTRY" | wc -l | tr -d ' ')"
[ "$STARS" = "2" ] || warn "found $STARS asterisks -- the journal is the only italicized span (*J Neurosci*)"

# House-style traps, each seen in a real submission.
awk '{ if ($0 ~ /[A-Z]\.[A-Z]\./ || $0 ~ /[A-Z]\.,/) exit 0; exit 1 }' <<<"$ENTRY" \
    && warn "author initials carry periods -- house style is 'Caras ML', not 'Caras M.L.'"
awk '{ exit !index($0, " & ") }' <<<"$ENTRY" \
    && warn "'&' between authors -- house style separates every author with a comma"
awk '{ exit !($0 ~ /\* [0-9]+(\([0-9A-Za-z]+\))?:[0-9]+-[0-9]/) }' <<<"$ENTRY" \
    && warn "page range uses an ASCII hyphen -- house style is an en dash (3354-3366 -> 3354–3366)"
awk '{ exit !($0 ~ /  / ) }' <<<"$ENTRY" \
    && warn "double space"
awk '{ exit !($0 ~ /et\. al|et al\./) }' <<<"$ENTRY" \
    && warn "'et al.' -- house style writes 'et al.' only after a comma, and only for very long author lists"

# --- duplicates -------------------------------------------------------------
if [ -n "$DOI" ]; then
    if awk -v d="$(tr 'A-Z' 'a-z' <<<"$DOI")" '{ if (index(tolower($0), d)) { print "  DUPLICATE OF: " $0; f = 1 } } END { exit !f }' "$PAGE"; then
        echo
        echo "That DOI is already on the page. Nothing inserted."
        exit 4
    fi
fi
# Same title, different DOI is nearly always a preprint whose published version
# is being added (or the reverse). The list carries ONE entry per paper: replace
# the older one by hand rather than listing both. --force overrides.
TITLE="$(awk '{ if (match($0, /\)\. /)) { s = substr($0, RSTART + 3); print substr(s, 1, 45) } }' <<<"$ENTRY")"
if [ -n "$TITLE" ] && awk -v t="$(tr 'A-Z' 'a-z' <<<"$TITLE")" '{ if (index(tolower($0), t)) { print "  SAME TITLE ALREADY LISTED: " $0; f = 1 } } END { exit !f }' "$PAGE"; then
    if [ "$FORCE" = 1 ]; then
        warn "same title already listed -- inserting anyway (--force)"
    else
        fail "same title already listed under a different DOI. If this is the published"
        say  "        version of a listed preprint, edit that entry in place instead of adding"
        say  "        a second one. Pass --force if both really belong on the page."
    fi
fi

[ "$FATAL" = "0" ] || { echo; echo "Rejected -- fix the entry and run again."; exit 2; }
say "format OK"

if [ "$DRY" = 1 ]; then
    echo
    echo "--dry-run: nothing written. Would file it under ### $YEAR."
    exit 0
fi

# --- insert -----------------------------------------------------------------
TMP="$PAGE.new"
awk -v year="$YEAR" -v ef="$ENTRYFILE" '
    BEGIN { while ((getline line < ef) > 0) if (line ~ /[^ \t]/) { entry = line; break } }
    /<!-- publications:begin -->/ { inb = 1; print; next }
    /<!-- publications:end -->/ {
        if (!done) { print "### " year; print ""; print entry; print ""; done = 1 }
        inb = 0; print; next
    }
    inb && /^### [0-9]/ {
        y = $2 + 0
        if (!done && y == year) { print; print ""; print entry; print ""; done = 1; eat = 1; next }
        if (!done && y <  year) { print "### " year; print ""; print entry; print ""; done = 1 }
        print; next
    }
    { if (eat && $0 == "") { eat = 0; next } print }
' "$PAGE" > "$TMP" || { rm -f "$TMP"; echo "ERROR: insertion failed" >&2; exit 2; }

BEFORE="$(awk '/<!-- publications:begin -->/ { p = 1 } /<!-- publications:end -->/ { p = 0 } p && /^- / { n++ } END { print n + 0 }' "$PAGE")"
AFTER="$(awk  '/<!-- publications:begin -->/ { p = 1 } /<!-- publications:end -->/ { p = 0 } p && /^- / { n++ } END { print n + 0 }' "$TMP")"
if [ "$AFTER" != "$((BEFORE + 1))" ]; then
    rm -f "$TMP"
    echo "ERROR: entry count went $BEFORE -> $AFTER, expected $((BEFORE + 1)). Page unchanged." >&2
    exit 2
fi
mv "$TMP" "$PAGE"

echo
echo "INSERTED under ### $YEAR  ($BEFORE -> $AFTER entries)"
echo
awk -v y="### $YEAR" '
    $0 == y { p = 1 }
    p && /<!-- publications:end -->/ { exit }
    p { print; if (/^- /) { n++; if (n == 2) exit } }
' "$PAGE"
echo
lint_page
