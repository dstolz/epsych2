---
name: update-wiki
description: Bring the GitHub wiki (epsych2.wiki) up to date with recent repository changes — rewrite affected pages, regenerate GUI screenshots, check links, then commit and push. Use when asked to update/sync/refresh the wiki, document a new feature or GUI component in the wiki, regenerate wiki or component screenshots, or check the wiki for stale content.
---

# /update-wiki — sync the wiki to the repository

The wiki is a **separate repository**, cloned as a sibling of this one. It is a
curated guide; `documentation/` in the code repo is the exhaustive reference and
is **authoritative** wherever the two overlap.

| Thing | Where |
|---|---|
| Code repo | `c:\src\epsych2` |
| Wiki clone | `c:\src\epsych2.wiki` (override with `EPSYCH_WIKI`) |
| Wiki remote | `https://github.com/dstolz/epsych2.wiki.git` — published at `/wiki` |
| Page files | `<wiki>/Page-Name.md`, flat, no subfolders |
| Images | `<wiki>/images/`, component shots in `<wiki>/images/components/` |
| Navigation | `<wiki>/_Sidebar.md`, `<wiki>/Home.md`, `<wiki>/_Footer.md` |
| Sync marker | `<wiki>/.synced-commit` — the epsych2 SHA the wiki reflects |

Three scripts do the mechanical work; run them with `bash` (Git Bash is present,
Node is not):

| Script | Role |
|---|---|
| `.claude/skills/update-wiki/survey.sh` | Read-only. Commits since the last sync, changed files, which pages they touch, screenshot hints. |
| `.claude/skills/update-wiki/verify.sh` | Read-only. Broken `[[links]]`, missing images, orphaned pages, dead links into the code repo. |
| `.claude/skills/update-wiki/pagemap.tsv` | The repo-path → wiki-page mapping both the survey and you read. Keep it current when pages are added. |

## Invocation forms

| User types | Means |
|---|---|
| `/update-wiki` | Everything since `.synced-commit`; update every affected page. |
| `/update-wiki <area>` (e.g. `hw.NE1000`, `gui`) | Only the pages that area touches. |
| `/update-wiki screenshots` | Regenerate images only — no prose changes. |
| `/update-wiki check` | Run `verify.sh` and report; change nothing. |
| `/update-wiki since <sha>` | Use that commit as the baseline instead of the marker. |

## Step 1 — survey

```bash
bash .claude/skills/update-wiki/survey.sh          # add --full for the whole patch
bash .claude/skills/update-wiki/survey.sh --since e6e9767
```

Exit 3 means nothing changed since the baseline — say so and stop.

Read the output before touching a page:

- **`WIKI WORKING TREE`** — if it is dirty, an earlier session already did part of
  this. Read those edits (`git -C <wiki> diff`) and continue them rather than
  writing over them.
- **`REPO COMMITS SINCE BASELINE`** — read the subjects, then read the actual diff
  for anything user-visible. Commit subjects overstate and understate.
- **`WIKI PAGES TO REVIEW`** — a hint from `pagemap.tsv`, not the answer. Open each
  page and decide whether the change is something a *reader of that page* needs.
- **`UNCOMMITTED IN THE CODE REPO`** — the wiki is public and links to `master`.
  Documenting code that is not pushed yet produces dead links; either hold that
  part back or tell the user the wiki is ahead of the pushed code.

## Step 2 — decide what actually changes

Not every commit earns a wiki edit. The wiki documents **what a user or an
extender needs to know**, not the changelog. A refactor with no behavior change
usually earns nothing; a new GUI component, a new backend, a new menu item, a
changed default, or a renamed control always does.

Order of work, because the wiki summarizes the repo docs:

1. **`documentation/` first.** If code changed and its reference doc did not, the
   doc is the gap — fix it there, or tell the user it is missing. Never let the
   wiki be the only place a fact is written down.
2. **Then the wiki page**, in its own voice — a guide, with the reference link at
   the end of the section.
3. **`documentation/overviews/*.md` pages are mirrors**, 1:1 with a wiki page of
   the same name (`Architecture_Overview.md` → `Architecture-Overview`). When the
   repo copy changes, regenerate the mirror: copy the text, keep the
   `> 📄 *This page is a wiki mirror of …*` note under the H1, and rewrite links
   (cross-overview → wiki page names, `../` paths → GitHub blob/tree URLs,
   `obj/stimgen/…` → stimgen repo URLs).
4. **A new page** needs an entry in `_Sidebar.md` *and* a row in the matching
   Home.md table, or nobody will find it. `verify.sh` catches a miss.

## Step 3 — write

House style, taken from the existing pages — match them, do not invent:

- **Two paths.** Every page belongs to *🧪 Using EPsych* (operators, GUI-first) or
  *🔧 Developing EPsych* (MATLAB against the framework), plus the *📄 Reference
  Overviews* mirrors. Write for that audience only; link across for the other.
- **Wiki links are `[[Display|Page-Name]]`** — display first. Links into the code
  are absolute `https://github.com/dstolz/epsych2/blob/master/…` URLs (a wiki page
  cannot use a relative path into the code repo). `+` in a package path is `%2B`.
- Prose is declarative and explains *why*, in the repo's voice: state the
  mechanism and the consequence, name the class and the method. No marketing, no
  "simply", no feature lists without a reason to care.
- Code blocks are runnable MATLAB, copied from a real example or smoke test.
- 🚧 marks under-development integrations (Teensy, Bpod, Intan RHX). Add the
  marker for a new backend that is not rig-proven, in the sidebar too.
- **Never duplicate stimgen's class inventory** — it is a separately released
  submodule. Link to its repo and its own documentation.
- Every screenshot gets an *italic caption below it* saying what the shot shows.
  When you change a shot, re-read the caption: it usually describes the specific
  state in the image ("two subjects on boxes 1 and 2", "the green field has been
  edited but not committed") and goes stale silently.

## Step 4 — screenshots

If `survey.sh` printed `SCREENSHOT HINTS`, the published images may be stale.
Read `references/screenshots.md` before running anything — it has the
image → generator table, the exact `matlab -batch` commands, and the rules for
adding a new shot. Two things that bite first:

- Screenshots need `matlab -batch`, **not** the MATLAB MCP server (`exportapp`
  capture is the one job the persistent nodesktop session cannot do).
- The generators snapshot and restore every `getpref` group they touch and build
  figures `Visible='off'`. Keep it that way; a shot must never disturb a live rig.

## Step 5 — verify

```bash
bash .claude/skills/update-wiki/verify.sh
```

Exit 2 lists the problems. A broken `[[link]]` renders on GitHub as plain text
with no error, so this check is the only one there is. Fix everything it reports
that you caused; report pre-existing failures to the user rather than silently
fixing unrelated pages.

Then re-read the pages you changed end to end. Section anchors in a page's own
table of contents break when you retitle a heading, and nothing checks those.

## Step 6 — commit and push the wiki

The wiki repo is not this repo — commit **in the wiki clone**, and the `/commit`
skill does not apply to it. Every run that changes a page ends committed **and
pushed**: the user has standing authorization for this, so do not ask.

```bash
REPO=/c/src/epsych2
WIKI=/c/src/epsych2.wiki
SCRATCH="<your session scratchpad dir>"

git -C "$REPO" rev-parse HEAD > "$WIKI/.synced-commit"    # move the marker
git -C "$WIKI" add -A
git -C "$WIKI" commit -F "$SCRATCH/wikimsg.txt"           # -F, never a multi-line -m
git -C "$WIKI" pull --rebase                              # a browser edit lands here too
git -C "$WIKI" push
```

Pushing publishes the pages to the public wiki immediately. Report what was
committed and pushed. If the push fails (rebase conflict, no network, denied
credentials), say so plainly with the error and leave the commit in place — the
work is not lost, only unpublished.

Message style matches the wiki's log — imperative subject, blank line, `- `
bullets naming the pages touched:

```text
Document the NE1000 pump and the SyringePump panel

- Video-and-Peripherals: new "Reward delivery" section covering the pump
  backend, the operator panel, and the no-hardware fallback.
- Behavior-GUI-Components: gui.SyringePump entry with a captured shot.
- Regenerated images/components/SyringePump.png.
```

If code-repo files also changed (a `documentation/*.md` you fixed, a generator you
edited, an image under `documentation/*/images/`), those are a **separate commit
in this repo** — use the `/commit` skill for them.

## Gotchas

- **The marker may be missing or stale.** With no `.synced-commit`, `survey.sh`
  falls back to the wiki's last commit *date*, which is coarse — commits made
  before that date but documented after it are invisible. Write the marker at the
  end of every run so the next one is exact.
- **The wiki clone can be behind the remote.** `git -C "$WIKI" pull` first; the
  user may have edited a page in the browser, which commits directly to that repo.
- **Images are binary and both copies drift.** Some shots live in the wiki *and*
  in `documentation/*/images/`; `generate_wiki_screenshots.m` writes both. If you
  update one by hand, update the other.
- **A wiki page is not a changelog.** Do not add "as of commit X" notes or a
  version history section; the commit log is the history.
- **Branded assets are copied, not linked.** `graphics/` in the code repo is the
  source for the banner, diagrams, logo, and section icons; the wiki carries its
  own copy in `images/`. Update the code repo first, then copy over.
- **Don't renumber or retitle a heading casually.** Other pages link to
  `#section-anchor`, and `verify.sh` does not check anchors.
