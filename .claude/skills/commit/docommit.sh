#!/usr/bin/env bash
# docommit.sh -- stage an explicit file list and commit from a message file.
#
# Usage:
#   docommit.sh <repo-dir> <msg-file> [pathspec ...]
#   docommit.sh --check <msg-file>              # lint the message, commit nothing
#
#   <repo-dir>   "."  for the parent repo, or "obj/stimgen" for a submodule
#   <msg-file>   commit message; -F avoids every quoting trap on Windows
#   [pathspec]   files to stage. OMITTED = every non-ignored change in that repo.
#                Always pass them explicitly when splitting into several commits.
#
# Refuses to commit on a detached HEAD, with an empty message, or with a
# subject line that breaks the repo's format.

set -uo pipefail

MAX_SUBJECT=72

lint_message() {
    local f="$1" errs=0 subject second len
    [[ -f "$f" ]] || { echo "FATAL: message file not found: $f" >&2; return 1; }
    # strip comment lines the way git would
    if ! grep -qv '^#' "$f" 2>/dev/null || [[ -z "$(grep -v '^#' "$f" | tr -d '[:space:]')" ]]; then
        echo "FATAL: message file is empty." >&2; return 1
    fi
    subject="$(grep -v '^#' "$f" | sed '/^[[:space:]]*$/d' | head -1)"
    second="$(grep -v '^#' "$f" | sed -n '2p')"
    len=${#subject}

    if [[ $len -gt $MAX_SUBJECT ]]; then
        echo "  WARN: subject is $len chars (>$MAX_SUBJECT). Tighten it:" >&2
        echo "        $subject" >&2
        errs=1
    fi
    case "$subject" in
        *.) echo "  WARN: subject ends with a period; drop it." >&2; errs=1 ;;
    esac
    if [[ -n "$second" && -n "$(echo "$second" | tr -d '[:space:]')" ]]; then
        echo "  FATAL: line 2 must be blank (subject, blank line, then body)." >&2
        return 1
    fi
    # bullet-list style: body lines that are not bullets/continuations are suspect.
    # Git trailers (Co-Authored-By:, Signed-off-by:, ...) are exempt.
    local body nbody
    body="$(grep -v '^#' "$f" | sed -n '3,$p' | sed '/^[[:space:]]*$/d' \
            | grep -v '^[A-Za-z][A-Za-z-]*: ')"
    nbody="$(printf '%s' "$body" | grep -c . )"
    if [[ "${nbody:-0}" -gt 0 ]]; then
        local nonbullet
        nonbullet="$(printf '%s\n' "$body" | grep -c '^[^ -]' )"
        if [[ "${nonbullet:-0}" -gt 0 ]]; then
            echo "  NOTE: $nonbullet body line(s) are neither '- ' bullets nor indented" >&2
            echo "        continuations. This repo's style is a bullet list." >&2
        fi
    fi
    grep -q '^Co-Authored-By: ' "$f" || \
        echo "  NOTE: no Co-Authored-By trailer. Add one for the model that wrote this." >&2
    return $errs
}

if [[ "${1:-}" == "--check" ]]; then
    [[ -n "${2:-}" ]] || { echo "usage: docommit.sh --check <msg-file>" >&2; exit 1; }
    echo "Linting $2 ..."
    if lint_message "$2"; then echo "  OK"; else exit 1; fi
    echo "--- message as git will record it ---"
    grep -v '^#' "$2" | sed 's/^/  | /'
    exit 0
fi

[[ $# -ge 2 ]] || { echo "usage: docommit.sh <repo-dir> <msg-file> [pathspec ...]" >&2; exit 1; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "FATAL: not inside a git repository." >&2; exit 1; }
reldir="$1"; msgfile="$2"; shift 2

if [[ "$reldir" == "." || "$reldir" == "$root" ]]; then d="$root"; else d="$root/$reldir"; fi
[[ -d "$d" ]] || { echo "FATAL: no such directory: $d" >&2; exit 1; }
git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "FATAL: $d is not a git repository." >&2; exit 1; }

branch="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [[ "$branch" == "HEAD" ]]; then
    echo "FATAL: detached HEAD in $d. A commit here would not be on any branch." >&2
    echo "       Check out a branch first, then re-run." >&2
    exit 1
fi

echo "Linting message ..."
lint_message "$msgfile" || exit 1

# --- stage ------------------------------------------------------------------
# Guard: staging with no pathspec would sweep in anything else already staged
# by an earlier step in a split. Report what was already there first.
pre_staged="$(git -C "$d" diff --cached --name-only 2>/dev/null)"
if [[ -n "$pre_staged" ]]; then
    echo "NOTE: these were already staged before this call and WILL be included:"
    echo "$pre_staged" | sed 's/^/  /'
fi

staged_only=0
for a in "$@"; do [[ "$a" == "--staged-only" ]] && staged_only=1; done
if [[ $staged_only -eq 1 ]]; then
    set --   # drop the flag; nothing else is a pathspec in this mode
    if [[ -z "$pre_staged" ]]; then
        echo "FATAL: --staged-only but the index is empty. Nothing committed." >&2
        exit 1
    fi
    echo "Staging: nothing -- committing the index exactly as it stands"
    echo "         (partial/hunk-level staging is preserved)"
elif [[ $# -eq 0 ]]; then
    echo "Staging: ALL non-ignored changes in $reldir"
    git -C "$d" add -A || { echo "FATAL: git add failed." >&2; exit 1; }
else
    echo "Staging $# pathspec(s):"
    for p in "$@"; do
        echo "  $p"
        git -C "$d" add -- "$p" || { echo "FATAL: git add failed for: $p" >&2; exit 1; }
    done
fi

# Guard: a moved submodule pointer is a deliberate, separate commit. `git add -A`
# would sweep it in silently, so unstage any pointer the caller did not name.
if [[ "$d" == "$root" ]]; then
    while read -r sp; do
        [[ -z "$sp" ]] && continue
        git -C "$d" diff --cached --name-only 2>/dev/null | grep -qx "$sp" || continue
        named=0
        for p in "$@"; do [[ "$p" == "$sp" || "$p" == "$sp/" ]] && named=1; done
        if [[ $named -eq 0 ]]; then
            git -C "$d" restore --staged -- "$sp" 2>/dev/null \
                || git -C "$d" reset -q HEAD -- "$sp" 2>/dev/null
            echo "HELD BACK: submodule pointer '$sp' was about to be committed implicitly."
            echo "           Bumping it is its own deliberate commit -- ask the user first."
            echo "           To bump it on purpose, name it explicitly as a pathspec."
            echo
        fi
    done < <(git -C "$d" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
fi

staged="$(git -C "$d" diff --cached --name-status 2>/dev/null)"
if [[ -z "$staged" ]]; then
    echo "FATAL: nothing staged -- pathspecs matched no changes. Nothing committed." >&2
    exit 1
fi
echo
echo "Staged for this commit:"
echo "$staged" | sed 's/^/  /'
echo

# --- commit -----------------------------------------------------------------
if ! git -C "$d" commit -F "$msgfile" --cleanup=strip; then
    echo "FATAL: git commit failed. Staged changes are left intact." >&2
    exit 1
fi

echo
echo "Committed in ${reldir}:"
git -C "$d" log -1 --format='  %h  %s' | sed 's/^/  /'
echo

# --- what is left -----------------------------------------------------------
remaining="$( { git -C "$d" diff --name-only; git -C "$d" diff --cached --name-only;
                git -C "$d" ls-files --others --exclude-standard; } 2>/dev/null | sort -u)"
if [[ -n "$remaining" ]]; then
    echo "STILL UNCOMMITTED in $reldir (expected mid-split; otherwise investigate):"
    echo "$remaining" | sed 's/^/  /'
else
    echo "$reldir is now clean."
fi

# --- submodule pointer nudge ------------------------------------------------
if [[ "$d" != "$root" ]]; then
    p="${d#"$root"/}"
    pinned="$(git -C "$root" ls-tree HEAD "$p" 2>/dev/null | awk '{print substr($3,1,7)}')"
    cur="$(git -C "$d" rev-parse --short HEAD 2>/dev/null)"
    if [[ "$pinned" != "$cur" ]]; then
        echo
        echo "POINTER: $p is pinned at $pinned in the parent but now at $cur."
        echo "         Bump it now -- do not ask. It is its own commit:"
        echo "           bash .claude/skills/commit/docommit.sh . <msgfile> $p"
    fi
fi
exit 0
