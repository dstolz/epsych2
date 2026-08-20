#!/usr/bin/env bash
# Resolve a reference (DOI, URL, PMID, or free text) to compact metadata for the
# Publications wiki page, and report whether it is already listed.
#
#   lookup.sh 10.1523/JNEUROSCI.0691-24.2024
#   lookup.sh https://pubmed.ncbi.nlm.nih.gov/28847934/
#   lookup.sh Caras Sanes 2017 top-down modulation of sensory cortex
#
# Exit: 0 resolved · 2 network/lookup failure · 3 no DOI (candidates printed)
#       4 already in the list
#
# NOTE: this machine's MSYS grep ABORTS (SIGABRT) on `grep -F` whose output is
# suppressed -- `grep -qiF x file` and `grep -iF x file >/dev/null` both die.
# Substring tests here go through awk index() instead. Do not "simplify" them.

set -uo pipefail

UA='epsych2-publications (mailto:daniel.stolzberg@gmail.com)'
WIKI="${EPSYCH_WIKI:-/c/src/epsych2.wiki}"
PAGE="$WIKI/Publications.md"
CURL=(curl -Ls -m 30 -H "User-Agent: $UA")

QUERY="$*"
[ -n "$QUERY" ] || { echo "usage: lookup.sh <doi | url | pmid | free-text reference>" >&2; exit 1; }
[ -f "$PAGE" ] || { echo "ERROR: $PAGE not found (set EPSYCH_WIKI)" >&2; exit 2; }

# --- find a DOI -------------------------------------------------------------
# Trailing punctuation is stripped: a DOI pasted out of prose often ends in . or )
extract_doi() {
    grep -oE '10\.[0-9]{4,9}/[^[:space:]"<>]+' <<<"$1" | head -1 | sed -E 's/[.,;)]+$//'
}

DOI="$(extract_doi "$QUERY")"
SOURCE="argument"

# PubMed: a PMID URL or "PMID: nnnnn" resolves to a DOI through esummary.
if [ -z "$DOI" ]; then
    PMID="$(grep -oE 'pubmed\.ncbi\.nlm\.nih\.gov/[0-9]{4,9}|PMID:?[[:space:]]*[0-9]{4,9}' <<<"$QUERY" | grep -oE '[0-9]{4,9}' | head -1)"
    if [ -n "${PMID:-}" ]; then
        DOI="$(extract_doi "$("${CURL[@]}" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=$PMID&retmode=json")")"
        SOURCE="PubMed $PMID"
    fi
fi

# A publisher/preprint URL with no DOI in the path: best effort on the page itself.
if [ -z "$DOI" ] && grep -qE '^https?://' <<<"$QUERY"; then
    HTML="$("${CURL[@]}" "$(awk '{print $1}' <<<"$QUERY")" | grep -iE 'citation_doi|dc.identifier|doi.org' | head -20)"
    DOI="$(extract_doi "$HTML")"
    [ -n "$DOI" ] && SOURCE="scraped from the page -- confirm it is the right paper"
fi

# --- free text: search, print candidates, stop ------------------------------
if [ -z "$DOI" ]; then
    echo "NO DOI IN THE INPUT -- Crossref candidates for:"
    echo "  $QUERY"
    echo
    ENC="$(sed -e 's/[^A-Za-z0-9 .-]/ /g' -e 's/  */+/g' -e 's/^+//' -e 's/+$//' <<<"$QUERY")"
    "${CURL[@]}" "https://api.crossref.org/works?rows=4&select=DOI,title,short-container-title,volume,issue,page,article-number,published,type&query.bibliographic=$ENC" \
        | awk '{ sub(/^.*"items":\[/, ""); sub(/\],"items-per-page.*$/, ""); gsub(/\},\{/, "\n\n"); gsub(/\\\//, "/"); print }'
    echo
    echo
    echo "Pick the right one, then re-run:  lookup.sh <its DOI>"
    echo "Crossref ranks loosely -- a wrong year or journal means it is NOT the paper."
    exit 3
fi

echo "DOI: $DOI   (from: $SOURCE)"
echo

# --- already listed? --------------------------------------------------------
if awk -v d="$(tr 'A-Z' 'a-z' <<<"$DOI")" '{ if (index(tolower($0), d)) { print; f=1 } } END { exit !f }' "$PAGE"; then
    echo
    echo "ALREADY IN THE LIST (above) -- nothing to add."
    exit 4
fi

# --- metadata ---------------------------------------------------------------
BIB="$("${CURL[@]}" -H 'Accept: application/x-bibtex' "https://doi.org/$DOI")"
if [ -z "$BIB" ] || grep -qE '^[[:space:]]*<' <<<"$BIB"; then
    echo "ERROR: doi.org returned no BibTeX for $DOI." >&2
    echo "       Either the DOI is wrong, or it is registered somewhere that does not" >&2
    echo "       serve BibTeX. Fall back to the publisher page and format by hand." >&2
    exit 2
fi

echo "BIBTEX  (title case here is the PUBLISHER'S -- the list uses sentence case)"
echo "--------------------------------------------------------------------------"
awk '{ gsub(/\}, /, "},\n  "); print }' <<<"$BIB"
echo
echo "CROSSREF FIELDS  (article-number lives here only -- BibTeX drops it)"
echo "-------------------------------------------------------------------"
"${CURL[@]}" "https://api.crossref.org/works?rows=1&select=DOI,type,short-container-title,container-title,volume,issue,page,article-number,published,posted,publisher&filter=doi:$DOI" \
    | awk '{ sub(/^.*"items":\[/, ""); sub(/\],"items-per-page.*$/, ""); gsub(/,"/, ",\n \""); gsub(/\\\//, "/"); print }'
echo
echo "JOURNAL ABBREVIATIONS ALREADY IN USE  (reuse one before inventing one)"
echo "----------------------------------------------------------------------"
awk '/<!-- publications:begin -->/ { p = 1 } /<!-- publications:end -->/ { p = 0 } p && /^- /' "$PAGE" \
    | grep -oE '\*[^*]+\*' | sort | uniq -c | sort -rn \
    | awk '{ n = $1; $1 = ""; sub(/^ /, ""); printf "  %-26s %sx\n", $0, n }'
