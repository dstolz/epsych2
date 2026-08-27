#!/usr/bin/env bash
# fetch.sh — read-only. Pull GitHub issues for this repo and print a compact digest.
#
# Auth comes from Git Credential Manager (the same token `git push` uses); there is
# no `gh` CLI on this workstation. The token never leaves this script's shell.
#
# Usage:
#   fetch.sh                    open issues (default)
#   fetch.sh closed | all       state filter
#   fetch.sh 17 | #17           one issue, full body + comments
#   fetch.sh label:bug          filter by label (repeatable)
#   fetch.sh mine               issues created by the authenticated user
#   fetch.sh --full             do not truncate bodies
#   fetch.sh --no-comments      skip the comment fetch (faster)
#   fetch.sh --limit N          cap the number of issues (default 50)
#
# Exit: 0 ok | 2 auth/network failure | 3 no issues matched

set -uo pipefail

REPO="${EPSYCH_ISSUES_REPO:-dstolz/epsych2}"
API="https://api.github.com"

STATE="open"
LABELS=""
CREATOR=""
ONE=""
BODY_LIMIT=4000
WANT_COMMENTS=1
LIMIT=50

while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
        open|closed|all)     STATE="$arg" ;;
        --full)              BODY_LIMIT=0 ;;
        --no-comments)       WANT_COMMENTS=0 ;;
        --limit)             shift; LIMIT="${1:-50}" ;;
        mine)                CREATOR="@me" ;;
        label:*)             lbl="${arg#label:}"
                             if [ -z "$LABELS" ]; then LABELS="$lbl"; else LABELS="$LABELS,$lbl"; fi ;;
        \#[0-9]*)            ONE="${arg#\#}" ;;
        [0-9]*)              ONE="$arg" ;;
        -h|--help)           sed -n '2,20p' "$0"; exit 0 ;;
        *)                   echo "fetch.sh: ignoring unrecognized argument '$arg'" >&2 ;;
    esac
    shift
done

WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/epsych-issues-$$")"
mkdir -p "$WORK"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | grep '^password=' | cut -d= -f2-)"
if [ -z "$TOKEN" ]; then
    echo "ERROR: no GitHub token from git credential fill." >&2
    echo "Public issues may still be readable; retrying unauthenticated." >&2
fi

# api_get <url> <outfile> ; echoes the HTTP status
api_get() {
    local url="$1" out="$2" code
    if [ -n "$TOKEN" ]; then
        code="$(curl -s -w '%{http_code}' -o "$out" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" "$url")"
    else
        code="$(curl -s -w '%{http_code}' -o "$out" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" "$url")"
    fi
    echo "$code"
}

ISSUES="$WORK/issues.json"

if [ -n "$ONE" ]; then
    URL="$API/repos/$REPO/issues/$ONE"
    HEADER="ISSUE #$ONE - $REPO"
    BODY_LIMIT=0
else
    URL="$API/repos/$REPO/issues?state=$STATE&per_page=$LIMIT&sort=updated&direction=desc"
    if [ -n "$LABELS" ]; then URL="$URL&labels=$LABELS"; fi
    if [ -n "$CREATOR" ]; then URL="$URL&creator=$CREATOR"; fi
    HEADER="ISSUES - $REPO (state=$STATE"
    if [ -n "$LABELS" ]; then HEADER="$HEADER, labels=$LABELS"; fi
    if [ -n "$CREATOR" ]; then HEADER="$HEADER, creator=$CREATOR"; fi
    HEADER="$HEADER)"
fi

CODE="$(api_get "$URL" "$ISSUES")"
if [ "$CODE" != "200" ]; then
    echo "ERROR: GitHub returned HTTP $CODE for $URL" >&2
    head -c 400 "$ISSUES" >&2
    echo >&2
    exit 2
fi

WIN_WORK="$(cygpath -w "$WORK" 2>/dev/null || echo "$WORK")"
WIN_ISSUES="$(cygpath -w "$ISSUES" 2>/dev/null || echo "$ISSUES")"
PS_SCRIPT="$(cygpath -w "$(dirname "$0")/digest.ps1" 2>/dev/null || echo "$(dirname "$0")/digest.ps1")"

# Planning pass: which issues have comments worth fetching?
if [ "$WANT_COMMENTS" -eq 1 ]; then
    powershell -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" \
        -IssuesJson "$WIN_ISSUES" -ListTargets 2>/dev/null | while read -r num count; do
        if [ -n "${num:-}" ]; then
            api_get "$API/repos/$REPO/issues/$num/comments?per_page=100" \
                "$WORK/comments-$num.json" >/dev/null
        fi
    done
fi

COMMENTS_ARG=""
if [ "$WANT_COMMENTS" -eq 1 ]; then COMMENTS_ARG="$WIN_WORK"; fi

powershell -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" \
    -IssuesJson "$WIN_ISSUES" \
    -CommentsDir "$COMMENTS_ARG" \
    -BodyLimit "$BODY_LIMIT" \
    -Header "$HEADER"
PS_EXIT=$?

if [ $PS_EXIT -eq 3 ]; then
    echo "No issues matched." >&2
    exit 3
fi
exit $PS_EXIT
