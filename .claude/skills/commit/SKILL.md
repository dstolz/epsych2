---
name: commit
description: Stage and commit changes in this repo with a concise, comprehensive message in the repo's house style. Use when asked to commit, stage and commit, check in changes, save work to git, commit the submodule (obj/stimgen), or split changes into several logical commits. Handles submodule commits and pointer bumps, and multi-commit splits.
---

# /commit — stage and commit EPsych changes

Paths below are relative to the repo root (`c:\src\epsych2`). Two scripts do the
work; run them with `bash` (Git Bash is present, Node is not).

| Script | Role |
|---|---|
| `.claude/skills/commit/survey.sh` | Read-only. Gathers branch, diff, untracked files, submodule pointer state, and grouping hints in one shot. |
| `.claude/skills/commit/docommit.sh` | Lints the message file, stages an explicit file list, commits with `-F`. |

## Invocation forms

| User types | Means |
|---|---|
| `/commit` | Commit everything in the parent repo, one commit. |
| `/commit obj/stimgen` (or `stimgen`) | Commit inside that submodule, then **ask** before bumping the pointer. |
| `/commit --split` / "split into logical commits" | Several commits grouped by intent. |
| `/commit on <branch>` | Check out that existing branch first, then commit. |

**Branch policy:** commit on the current branch — including `master` — unless the
user names an existing branch or asks for a new one. **Never push.** The user
runs `git push` themselves.

## Step 1 — survey

```bash
bash .claude/skills/commit/survey.sh
```

Exit 3 means the tree is clean; stop and say so. Add `--full` if the patch was
truncated — **do not** write a message from a truncated patch. For a submodule
target, pass it: `bash .claude/skills/commit/survey.sh obj/stimgen`. Use
`survey.sh all` to see the parent and every submodule at once.

Do not trust a `git status` snapshot from earlier in the conversation — it goes
stale. The survey is the source of truth.

## Step 2 — show new files, then group

The survey prints a `NEW (untracked...)` block. **Show that list to the user
before committing** — a stray scratch file is easy to miss. The survey flags
suspects (`*.log`, `*.mat`, `*.asv`, `*.bak`) under `WARNINGS`.

The `AREAS` block groups changed files by directory. That is a *hint*, not the
answer — group by **intent** after reading the patch. One commit unless the user
asked for a split or the changes are plainly unrelated.

## Step 3 — write the message

House style is **imperative subject, blank line, `- ` bullets**. Match
`git log` — e.g. commit `9792093`:

```text
Enhance status messaging and UI updates across RunExpt

- Added a status bar to provide real-time feedback on actions such as
  saving configurations, starting/stopping video recordings, and
  removing subjects.
- Implemented defensive checks for subject names to ensure meaningful
  status messages.
- Updated the UpdateGUIstate method to announce state changes only when
  they occur.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
```

Rules the linter enforces: subject ≤72 chars, no trailing period, line 2 blank.
Bullets wrap with two-space indent. Name the classes, methods, and files that
changed — `hw.Parameter`, `RunExpt.LaunchUtility`, `epsych.SelfTest` check A6 —
so `git log` stays greppable. A trivial change (typo, version bump) may be a
subject line alone. Use the `Co-Authored-By` trailer for the model that is
actually running.

Write it to a file — never `git commit -m`. Multi-line `-m` is a quoting trap
here (see Gotchas). Heredoc into your session scratchpad (`$SCRATCH` below is
whatever scratchpad path your system prompt gives you — set it once):

```bash
SCRATCH="<your session scratchpad dir>"
cat > "$SCRATCH/msg1.txt" <<'EOF'
Add toolbar to RunExpt

- Added nine tools mirroring the Config menu actions.
- Moved Live View and Record video off the bottom bar. Both keep their
  setup_ tags so UpdateGUIstate disables them while RUNNING.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
bash .claude/skills/commit/docommit.sh --check "$SCRATCH/msg1.txt"
```

`--check` lints and prints the message without committing.

## Step 4 — commit

```bash
# everything in the parent repo
bash .claude/skills/commit/docommit.sh . "$SCRATCH/msg1.txt"

# only named files (this is how you split)
bash .claude/skills/commit/docommit.sh . "$SCRATCH/msg1.txt" obj/+hw/@Software/Software.m

# commit the index exactly as it stands (see Splitting inside one file)
bash .claude/skills/commit/docommit.sh . "$SCRATCH/msg1.txt" --staged-only
```

With no pathspec it stages every non-ignored change. It refuses to commit on a
detached HEAD, with an empty message, or when the pathspecs match nothing, and
it prints what is still uncommitted afterwards.

## Splitting into several commits

Run `docommit.sh` once per group, each with explicit pathspecs, most-foundational
first. Verified sequence:

```bash
bash .claude/skills/commit/docommit.sh . "$SCRATCH/msg1.txt" obj/+hw/@Software/Software.m
bash .claude/skills/commit/docommit.sh . "$SCRATCH/msg2.txt"   # the remainder
```

The trailing `STILL UNCOMMITTED` list after each commit tells you what is left.

### Splitting inside one file

`git add -p` is interactive and unavailable. Stage individual hunks by filtering
the patch and applying it to the index — this works here despite CRLF:

```bash
git diff -- documentation/overviews/Architecture_Overview.md > "$SCRATCH/full.patch"
awk '/^diff --git|^index |^--- |^\+\+\+ /{print; next} /^@@/{n++} n==1{print}' \
    "$SCRATCH/full.patch" > "$SCRATCH/hunk1.patch"
git apply --cached "$SCRATCH/hunk1.patch"
bash .claude/skills/commit/docommit.sh . "$SCRATCH/msgh1.txt" --staged-only
```

`--staged-only` is required: any `git add` on that file would re-stage the whole
file and destroy the partial staging. Commit the rest normally afterwards.

## Submodules (`obj/stimgen`)

`obj/stimgen` is a separate repo pinned to an exact commit. Per CLAUDE.md, moving
the pointer is its own deliberate commit.

```bash
# 1. commit inside the submodule
bash .claude/skills/commit/docommit.sh obj/stimgen "$SCRATCH/msg_sub.txt"
```

`docommit.sh` then prints the new SHA and a `POINTER:` line. **Ask the user
before bumping.** If they agree:

```bash
# 2. bump the pointer in the parent, as its own commit
bash .claude/skills/commit/docommit.sh . "$SCRATCH/msg_bump.txt" obj/stimgen
```

Verified output of that second commit:

```text
Staged for this commit:
  M	obj/stimgen
[master 7e51a8b] Bump obj/stimgen to 2ff22f2 for the Tone scratch marker
 1 file changed, 1 insertion(+), 1 deletion(-)
```

## Gotchas

- **A submodule is usually on a detached HEAD.** `git submodule update` checks
  out the pinned SHA, not a branch, so a commit made there belongs to no branch
  and is lost on the next update. `docommit.sh` refuses outright; `survey.sh`
  prints `*** DETACHED HEAD ***`. Fix with `git -C obj/stimgen checkout main`
  before committing. This bit during development of this skill.

- **`git add -A` in the parent silently bumps a moved submodule pointer.**
  `docommit.sh` detects this, unstages the pointer, and prints `HELD BACK:`.
  To bump on purpose, name `obj/stimgen` as an explicit pathspec.

- **Never `git commit -m` with a multi-line body.** PowerShell here-strings are
  banned in the Bash tool and backtick continuation breaks; `-F <file>` is the
  only reliable path on this machine. `docommit.sh` always uses `-F`.

- **`core.autocrlf=true` with no `.gitattributes`.** Every `git add` prints
  `warning: LF will be replaced by CRLF`. Harmless — not an error. It does mean
  a tool that rewrites a whole file can produce a whole-file diff; check the
  diffstat against what you actually changed before writing bullets.

- **`.gitignore` is thin** — `*.asv`, `tmp/*.log`, `tmp/*.txt` and a couple of
  example paths only. A `.log` or `.mat` outside `tmp/` shows up as a normal new
  file. `tmp/*.m` smoke tests *are* tracked and belong in commits.

- **Piping the survey masks its exit code.** `survey.sh | tail` reports `tail`'s
  status, not the script's. Redirect instead if you need the code.

- **`git status` from earlier in the conversation is stale.** During this
  session the opening snapshot showed 1 changed file; the tree actually had 6.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FATAL: detached HEAD in .../obj/stimgen` | `git -C obj/stimgen checkout main`, re-run. |
| `FATAL: nothing staged -- pathspecs matched no changes` | Pathspec typo, or the file is gitignored. Re-run `survey.sh`. |
| `FATAL: line 2 must be blank` | Message needs a blank line after the subject. |
| `HELD BACK: submodule pointer ...` | Working as intended. Ask, then name `obj/stimgen` explicitly. |
| `FATAL: '<x>' is not a submodule` | It lists the valid ones. Only `obj/stimgen` exists. |
| `FATAL: --staged-only but the index is empty` | The `git apply --cached` failed. Check the patch. |
| `fatal: transport 'file' not allowed` | Only when cloning this repo locally to test. Add `-c protocol.file.allow=always`. |
