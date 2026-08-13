#!/usr/bin/env bash
# survey.sh -- gather everything needed to write a commit message, in one shot.
#
# Usage:
#   survey.sh                  # parent repo (default)
#   survey.sh obj/stimgen      # a submodule (bare name "stimgen" also works)
#   survey.sh all              # parent + every submodule
#   survey.sh <target> --full  # do not truncate the patch
#
# Read-only. Never stages, commits, or modifies anything.
# Exit 0 = there is something to commit. Exit 3 = clean tree, nothing to do.

set -uo pipefail

DIFF_CAP=1200          # patch lines printed before truncation (override: --full)
BIG_FILE_LINES=600     # single-file diffs larger than this get called out

target="${1:-}"
[[ "${target}" == --* ]] && { set -- "" "$target"; target=""; }
full=0
for a in "$@"; do [[ "$a" == "--full" ]] && full=1; done
[[ $full -eq 1 ]] && DIFF_CAP=1000000

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "FATAL: not inside a git repository." >&2; exit 1; }

# --- resolve target to one or more repo directories -------------------------
declare -a repos=()
if [[ -z "$target" ]]; then
    repos=("$root")
elif [[ "$target" == "all" ]]; then
    repos=("$root")
    while read -r p; do [[ -n "$p" ]] && repos+=("$root/$p"); done < <(
        git -C "$root" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
else
    # accept "obj/stimgen", "stimgen", or an absolute path
    match=""
    while read -r p; do
        [[ -z "$p" ]] && continue
        if [[ "$p" == "$target" || "$(basename "$p")" == "$target" || "$root/$p" == "$target" ]]; then
            match="$p"; break
        fi
    done < <(git -C "$root" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')
    if [[ -z "$match" ]]; then
        echo "FATAL: '$target' is not a submodule of this repo. Known submodules:" >&2
        git -C "$root" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print "  " $2}' >&2
        exit 1
    fi
    repos=("$root/$match")
fi

anything_to_commit=1   # 1 = nothing found yet

# --- helpers ----------------------------------------------------------------
rel_name() { [[ "$1" == "$root" ]] && echo "(parent repo)" || echo "${1#"$root"/}"; }

survey_one() {
    local d="$1" label; label="$(rel_name "$d")"
    echo "==============================================================================="
    echo "REPO: $label"
    echo "  dir      : $d"

    local branch upstream ahead behind
    branch="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    if [[ "$branch" == "HEAD" ]]; then
        echo "  branch   : *** DETACHED HEAD at $(git -C "$d" rev-parse --short HEAD) ***"
        echo "             A commit here is not on any branch. Check out a branch first."
    else
        echo "  branch   : $branch"
    fi
    upstream="$(git -C "$d" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
    if [[ -n "$upstream" ]]; then
        ahead="$(git -C "$d" rev-list --count "$upstream"..HEAD 2>/dev/null)"
        behind="$(git -C "$d" rev-list --count HEAD.."$upstream" 2>/dev/null)"
        echo "  upstream : $upstream (ahead $ahead, behind $behind)"
    else
        echo "  upstream : none configured"
    fi
    echo "  HEAD     : $(git -C "$d" log -1 --format='%h %s' 2>/dev/null)"
    echo

    # --- file lists -----------------------------------------------------
    local staged unstaged untracked
    staged="$(git -C "$d" diff --cached --name-status 2>/dev/null)"
    unstaged="$(git -C "$d" diff --name-status 2>/dev/null)"
    untracked="$(git -C "$d" ls-files --others --exclude-standard 2>/dev/null)"

    if [[ -n "$staged" ]]; then
        echo "ALREADY STAGED (someone ran git add before this survey -- do not assume it is yours):"
        echo "$staged" | sed 's/^/  /'
        echo
        anything_to_commit=0
    fi
    if [[ -n "$unstaged" ]]; then
        echo "MODIFIED (tracked, unstaged):"
        echo "$unstaged" | sed 's/^/  /'
        echo
        anything_to_commit=0
    fi
    if [[ -n "$untracked" ]]; then
        echo "NEW (untracked, not gitignored) -- SHOW THIS LIST TO THE USER BEFORE COMMITTING:"
        echo "$untracked" | sed 's/^/  + /'
        echo
        anything_to_commit=0
    fi
    if [[ -z "$staged$unstaged$untracked" ]]; then
        echo "WORKING TREE CLEAN -- nothing to commit in this repo."
        echo
    fi

    # --- submodule pointer state (parent only) --------------------------
    if [[ "$d" == "$root" ]]; then
        local subs; subs="$(git -C "$d" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')"
        if [[ -n "$subs" ]]; then
            echo "SUBMODULES:"
            while read -r p; do
                [[ -z "$p" ]] && continue
                local pinned cur dirty sdesc unpushed
                pinned="$(git -C "$d" ls-tree HEAD "$p" 2>/dev/null | awk '{print substr($3,1,7)}')"
                cur="$(git -C "$d/$p" rev-parse --short HEAD 2>/dev/null)"
                if [[ -z "$cur" ]]; then
                    echo "  $p: NOT INITIALIZED (run: git submodule update --init --recursive)"
                    continue
                fi
                dirty=""
                [[ -n "$(git -C "$d/$p" status --porcelain 2>/dev/null)" ]] && dirty=" [DIRTY: uncommitted changes inside]"
                if [[ "$pinned" == "$cur" ]]; then
                    sdesc="pinned $pinned == current $cur"
                else
                    sdesc="pinned $pinned -> current $cur  *** POINTER MOVED ***"
                fi
                unpushed=""
                if git -C "$d/$p" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
                    local n; n="$(git -C "$d/$p" rev-list --count '@{u}'..HEAD 2>/dev/null)"
                    [[ "${n:-0}" -gt 0 ]] && unpushed=" [$n commit(s) not pushed to its remote]"
                fi
                echo "  $p: $sdesc$dirty$unpushed"
            done <<< "$subs"
            echo
            echo "  Reminder: a moved pointer is committed in THIS repo as its own deliberate commit."
            echo "  Commit inside the submodule first, then bump the pointer -- do not ask."
            echo
        fi
    fi

    # --- grouping hint for splitting into multiple commits ---------------
    local changed
    changed="$( { git -C "$d" diff --name-only; git -C "$d" diff --cached --name-only;
                  git -C "$d" ls-files --others --exclude-standard; } 2>/dev/null | sort -u)"
    if [[ -n "$changed" ]]; then
        echo "AREAS (grouping hint for --split; these are directories, NOT logical units --"
        echo "       group by intent after reading the diff):"
        # keys sorted inside awk: piping to sort would interleave the per-area
        # file lists with their headers
        echo "$changed" | awk -F/ '{
            if ($1 == "obj" && NF > 2)      a = $1 "/" $2
            else if (NF > 1)                a = $1
            else                            a = "(top level)"
            if (!(a in n)) keys[++k] = a
            n[a]++; f[a] = f[a] "      " $0 "\n"
        } END {
            for (i = 1; i <= k; i++) for (j = i+1; j <= k; j++)
                if (keys[j] < keys[i]) { t = keys[i]; keys[i] = keys[j]; keys[j] = t }
            for (i = 1; i <= k; i++)
                printf "  %-28s %d file(s)\n%s", keys[i], n[keys[i]], f[keys[i]]
        }'
        echo
    fi

    # --- diffstat + oversize warnings ------------------------------------
    local stat; stat="$(git -C "$d" diff HEAD --stat 2>/dev/null)"
    if [[ -n "$stat" ]]; then
        echo "DIFFSTAT (tracked changes vs HEAD):"
        echo "$stat" | sed 's/^/  /'
        echo
    fi

    local warned=0
    while read -r f; do
        [[ -z "$f" ]] && continue
        if git -C "$d" diff HEAD --numstat -- "$f" 2>/dev/null | grep -q '^-'; then
            [[ $warned -eq 0 ]] && { echo "WARNINGS:"; warned=1; }
            echo "  BINARY: $f -- describe it in prose; the patch below will not show it."
        else
            local n; n="$(git -C "$d" diff HEAD --numstat -- "$f" 2>/dev/null | awk '{print $1+$2}')"
            if [[ "${n:-0}" -gt $BIG_FILE_LINES ]]; then
                [[ $warned -eq 0 ]] && { echo "WARNINGS:"; warned=1; }
                echo "  LARGE:  $f ($n lines changed) -- read it in full before summarizing:"
                echo "            git -C '$d' diff HEAD -- '$f'"
            fi
        fi
    done < <(git -C "$d" diff HEAD --name-only 2>/dev/null)
    # untracked files that look like they were never meant to be committed
    while read -r f; do
        [[ -z "$f" ]] && continue
        case "$f" in
            *.asv|*.mat|*.log|.error_logs/*|*/.error_logs/*|*~|*.bak|*.orig)
                [[ $warned -eq 0 ]] && { echo "WARNINGS:"; warned=1; }
                echo "  SUSPECT NEW FILE: $f -- scratch/output file? confirm before adding." ;;
        esac
    done <<< "$untracked"
    [[ $warned -eq 1 ]] && echo

    # --- the patch --------------------------------------------------------
    echo "-------------------------- PATCH (tracked, vs HEAD) ---------------------------"
    local patch total
    patch="$(git -C "$d" diff HEAD 2>/dev/null)"
    if [[ -z "$patch" ]]; then
        echo "  (no tracked changes)"
    else
        total="$(printf '%s\n' "$patch" | wc -l)"
        printf '%s\n' "$patch" | head -n "$DIFF_CAP"
        if [[ "$total" -gt "$DIFF_CAP" ]]; then
            echo
            echo "  ... TRUNCATED at $DIFF_CAP of $total lines."
            echo "  You have NOT seen the whole change. Do not summarize from this alone. Either:"
            echo "    bash .claude/skills/commit/survey.sh ${target:-} --full"
            echo "    git -C '$d' diff HEAD -- <path>     # one file at a time"
        fi
    fi
    echo

    if [[ -n "$untracked" ]]; then
        echo "----------------------- NEW FILE CONTENTS (untracked) -------------------------"
        while read -r f; do
            [[ -z "$f" ]] && continue
            echo "--- $f ---"
            if [[ -d "$d/$f" ]]; then
                echo "  (directory -- contents:)"
                find "$d/$f" -type f 2>/dev/null | sed "s|^$d/|    |"
            elif grep -qI . "$d/$f" 2>/dev/null; then
                head -n 60 "$d/$f" | sed 's/^/  /'
                local lc; lc="$(wc -l < "$d/$f" 2>/dev/null | tr -d ' ')"
                [[ "${lc:-0}" -gt 60 ]] && echo "  ... ($lc lines total; read the file for the rest)"
            else
                echo "  (binary, $(wc -c < "$d/$f" 2>/dev/null | tr -d ' ') bytes)"
            fi
            echo
        done <<< "$untracked"
    fi
}

for r in "${repos[@]}"; do survey_one "$r"; done

echo "==============================================================================="
if [[ $anything_to_commit -ne 0 ]]; then
    echo "NOTHING TO COMMIT."
    exit 3
fi
echo "Next: write the message to a file, then commit with docommit.sh (never git commit -m)."
exit 0
