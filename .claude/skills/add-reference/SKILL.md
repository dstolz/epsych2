---
name: add-reference
description: Add a publication to the EPsych wiki's Publications list from a DOI, a URL, a PMID, or a pasted reference. Use when asked to add a reference/citation/paper/preprint to the publications page, record a paper that used EPsych, or check whether one is already listed. Resolves the metadata against Crossref, formats the entry in house style, files it under the right year, and pushes the wiki.
---

# /add-reference — add a paper to the Publications list

The list lives in the **wiki repository**, not this one:

| Thing | Where |
|---|---|
| Page | `c:\src\epsych2.wiki\Publications.md` (override the clone with `EPSYCH_WIKI`) |
| Machine-edited region | between `<!-- publications:begin -->` and `<!-- publications:end -->` |
| Published at | https://github.com/dstolz/epsych2/wiki/Publications |

Two scripts; run them with `bash` (Git Bash is present, Node and Python are not).

| Script | Role |
|---|---|
| `.claude/skills/add-reference/lookup.sh` | Read-only. DOI / URL / PMID / free text → BibTeX + Crossref fields, plus a duplicate check and the abbreviations already in use. |
| `.claude/skills/add-reference/insert.sh` | Lints one finished entry, refuses duplicates, files it under the right year, re-lints the page. |

The scripts do **lookup and placement**. The *formatting* is yours — that is the
part that needs judgment, and Step 3 is where the rules are.

## Invocation forms

The user types `/add-reference` followed by whatever they have. All of these work:

| They give you | Do |
|---|---|
| A DOI, or any link containing one | `lookup.sh <it>` |
| A PubMed / journal / bioRxiv URL | `lookup.sh <it>` — it resolves the PMID or scrapes the page for a DOI |
| A full pasted reference | `lookup.sh <the whole thing>` — a DOI inside it is used; otherwise it searches |
| Author + year + title fragment | `lookup.sh <the words>` — Crossref search, then confirm which hit |
| Nothing (just `/add-reference`) | Ask what to add. Do not guess. |

Quote nothing and escape nothing: pass the text through as arguments.

## Step 1 — look it up

```bash
bash .claude/skills/add-reference/lookup.sh 10.1523/JNEUROSCI.0691-24.2024
```

| Exit | Means | Do |
|---|---|---|
| 0 | Resolved | Go to Step 2 |
| 3 | No DOI — candidates printed | **Pick, do not assume.** Re-run with the chosen DOI |
| 4 | Already listed | Say so, show the existing line, stop |
| 2 | Network or registration failure | Say what failed; offer to format from what the user gave |

On exit 3, read the candidates' `type` field before choosing. Crossref indexes
eLife's decision letters and author responses as separate records with nearly the
same title — `"type":"peer-review"` is a **different paper's** DOI. You want
`journal-article`, or `posted-content` for a preprint. If two candidates are
plausible, ask the user rather than picking.

**Do not paste the whole BibTeX into your reply.** It is working material.

## Step 2 — is it really an EPsych paper?

The page's claim is that the experiments *were run with EPsych*. You usually
cannot tell that from metadata, and the user usually can. Add what they hand you;
ask only when they seem to be surveying the field rather than reporting their own
lab's output.

One editorial rule the scripts enforce: **one entry per paper.** A preprint that
has since been published replaces its preprint entry — edit that line in place,
do not add a second. `insert.sh` refuses a same-title insert for exactly this
reason, and `--force` is for the rare case where both really belong.

## Step 3 — write the entry

One markdown list item, in this shape:

```text
- Surname II, Surname II (YEAR). Title in sentence case. *Journal Abbrev* VOL(ISSUE):PAGES. https://doi.org/10.xxxx/yyyy
```

Every rule below exists because the BibTeX gives you the wrong form of it.

**Authors.** `Surname II` — initials run together, no periods, no `&`; a comma
between every author. Keep hyphens the source keeps: `Li J-X`, `Macedo-Lima M`,
`Al-youzbaki M`. Multi-word surnames stay whole (`Diez Castro M`). Crossref gives
the full list, so `Surname II, et al.` is a deliberate choice for an unwieldy
author list (the page has one), never a shortcut you take because the list is long
to type.

**Title.** Sentence case — BibTeX hands you the publisher's title case and it must
be downcased. Keep proper nouns, species and strain names (*Mongolian gerbils*),
acronyms, and gene or protein symbols. Keep the source's own subtitle punctuation,
colon or em dash.

**Journal.** Abbreviated, italicized, no period. `lookup.sh` prints the
abbreviations already on the page — **reuse one before inventing one**. Crossref's
`short-container-title` is a starting point, not the answer: it gives
`Proc. Natl. Acad. Sci. U.S.A.` where the page says `PNAS`. For a genuinely new
journal, use the NLM/Index Medicus abbreviation with the periods dropped
(*Journal of Neurophysiology* → `J Neurophysiol`).

**Volume, issue, pages.**

- Page ranges take an **en dash**, not a hyphen: `2344–2353`. Crossref returns a hyphen.
- Keep an elocation suffix: `3354–3366.e6`.
- An **article number replaces the page range**: `13:2872`, `7:e33891`, `122(14):e2412453122`. BibTeX **drops** article numbers — take them from the `CROSSREF FIELDS` block.
- Include `(ISSUE)` for issue-paginated journals: PNAS, J Neurosci, Cereb Cortex, Curr Biol, Hear Res.
- **Drop a nominal issue** for continuous-publication journals — eLife, the Nature family, Frontiers, PLOS, Hindawi (`Neural Plast`). Crossref reports `"issue":"1"` for Nat Commun; the page says `13:2872`. When in doubt, match the shape of another entry from the same journal.

**Preprints.** `*bioRxiv*.` in place of volume and pages, then the DOI. Same for
`*medRxiv*`, `*arXiv*`.

**The DOI.** A bare `https://doi.org/…` link, last thing on the line, no trailing
period. Use the **publisher's casing**, not Crossref's: Crossref lowercases, and
the page carries `10.7554/eLife.33891` and `10.1523/JNEUROSCI.0691-24.2024`. Take
the casing from the user's link, or from the publisher page, or match a sibling
entry from the same journal.

Write the finished line to a scratch file **with the Write tool** — not a shell
heredoc. The Bash tool layer strips backslashes and can mangle the en dash on the
way through, and a corrupted dash renders as a visible mojibake box on GitHub.

## Step 4 — insert

```bash
bash .claude/skills/add-reference/insert.sh "$SCRATCH/entry.txt"
```

It lints, refuses on a fatal problem or a duplicate, files the entry at the top of
its year (creating the year heading if the year is new), and re-lints the whole
page. Add `--dry-run` to check without writing.

| Exit | Means |
|---|---|
| 0 | Inserted, page lints clean |
| 2 | Rejected — fix the entry, run again |
| 4 | That DOI is already on the page |

`REJECT` lines are refusals. `WARN` lines still insert — read them, and fix the
entry unless you can say why the warning is wrong. `insert.sh --lint` on its own
checks the whole page: year ordering, entries under the wrong year heading,
duplicate DOIs, missing links.

## Step 5 — commit and push the wiki

The wiki is a separate repository and the `/commit` skill does not apply to it.
The user has standing authorization for wiki pushes — do not ask.

```bash
WIKI=/c/src/epsych2.wiki
git -C "$WIKI" add Publications.md
git -C "$WIKI" commit -m "Add <first author> et al. <year> to the publications list"
git -C "$WIKI" push
```

Two things that matter here:

- **Stage `Publications.md` only.** Another session may have the wiki checkout dirty; `git add -A` would sweep its half-finished work into your commit.
- **Do not touch `.synced-commit`.** It records which epsych2 commit the wiki's *documentation* reflects, and a publication is not a code change. Moving it would make `/update-wiki` skip real work.

Then tell the user the finished line and the page URL.

## When there is no DOI

A thesis, a technical report, or an in-press paper with nothing registered yet: format
it the same way, put whatever stable URL exists last on the line, and let `insert.sh`
warn about the non-DOI link. If there is no URL at all, the entry cannot be placed by
the script — edit `Publications.md` by hand, keep the year ordering, and run
`insert.sh --lint` afterward.
