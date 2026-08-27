---
name: issues
description: Triage open GitHub issues on dstolz/epsych2 — fetch them, evaluate each against the actual code, and present a concise summary and action plan, then let the user pick one or several to work on. Use when asked to look at issues, check the issue tracker, triage/review issues, see what's open on GitHub, or work on a specific issue number.
---

# /issues — triage the GitHub issue tracker

Read the tracker, judge each issue **against the code as it stands today**, present a
short summary and action plan per issue, then let the user choose what to tackle.

| Thing | Where |
|---|---|
| Tracker | https://github.com/dstolz/epsych2/issues |
| Fetcher | `.claude/skills/issues/fetch.sh` (read-only) |
| Renderer | `.claude/skills/issues/digest.ps1` (called by the fetcher) |

There is no `gh` CLI on this workstation. Auth comes from Git Credential Manager via
`git credential fill`; the token stays inside `fetch.sh`. Run scripts with `bash`.

**This skill never writes to GitHub.** It does not comment, label, assign, or close.
If the user wants any of that, do it only on an explicit instruction, and say what you
are about to post before posting it.

## Invocation forms

| User types | Do |
|---|---|
| `/issues` | `bash .claude/skills/issues/fetch.sh` — open issues |
| `/issues 17` | `fetch.sh 17` — that one issue, full body and comments, then evaluate it alone |
| `/issues closed` / `all` | `fetch.sh closed` / `fetch.sh all` |
| `/issues label:bug` | `fetch.sh label:bug` |
| `/issues mine` | `fetch.sh mine` |
| `/issues bugs only`, "the pump one", etc. | Fetch open issues, then filter by judgment |

Useful flags: `--full` (untruncated bodies), `--no-comments` (faster), `--limit N`.

| Exit | Means | Do |
|---|---|---|
| 0 | Issues printed | Go to Step 2 |
| 3 | Nothing matched | Say so plainly and stop. Do not invent issues |
| 2 | Auth or network failure | Report what failed; do not fall back to guessing |

The `/issues` endpoint returns pull requests too — `digest.ps1` drops them. If the user
asks about a PR, that is outside this skill.

## Step 1 — fetch

```bash
bash .claude/skills/issues/fetch.sh
```

Do not paste the raw digest into your reply. It is working material.

## Step 2 — the cursory evaluation

This is the part that matters, and it is **not** a restatement of the issue body.
For each issue, spend a couple of tool calls finding out what is actually true.

**Check whether it already exists — first, always.** This repo has a great deal of
built machinery that a feature request may already be asking for, in whole or in part.
`CLAUDE.md` is the fastest index; it describes most classes in detail. Grep the code
before concluding anything is missing. The most useful outcome this skill produces is
"most of this is already there, here is the gap" — that turns a week into an afternoon.

**Locate it.** The issue forms have an *Area* dropdown; map it to the tree:

| Area | Start looking in |
|---|---|
| Session window / running experiments | `obj/+epsych/@RunExpt/`, `obj/+epsych/@Runtime/`, `runtime/timerfcns/` |
| Protocol design | `obj/+epsych/@Protocol/`, `obj/+epsych/@ProtocolDesigner/` |
| Hardware backend | `obj/+hw/@Interface/`, the concrete backend, `TDTfun/` |
| Trial selection or closed-loop control | `obj/+epsych/@TrialSelector/`, `obj/+epsych/@BlockSequence/`, `paradigms/` |
| Online analysis and plots | `obj/+psychophysics/`, `obj/+gui/@OnlinePlot/`, `gui.components.*Plot` |
| Behavior GUI components | `obj/+gui/@BehaviorGUI/`, `obj/+gui/+components/`, `obj/+gui/@KeyBindings/` |
| Data saving and file formats | `runtime/savefcns/`, `obj/+epsych/@TrialJournal/`, `@SessionSnapshot/` |
| Documentation | `documentation/`, and the wiki (see `/update-wiki`) |

**Then judge, briefly:**

- **Scope** — which files change, and roughly how many.
- **Effort** — small (an afternoon) / medium (a day or two) / large (multi-day, or needs
  design). Say which, and why.
- **Risk** — does it touch the runtime trial loop, hardware dispatch, or a saved file
  format? Those carry real consequence; a display component does not.
- **Blockers** — needs hardware on the bench, a design decision from the user, or a
  `stimgen` submodule change (separate repo, separate commit).
- **Verification** — how it would be checked. Most of this repo is verified by a
  `tmp/smoke_test_*.m` script and the MATLAB MCP server, not a unit-test suite.

Check `git log` for recent work in the area — a peer session may have already touched it.

## Step 3 — present

Per issue, a compact block. Keep the whole reply scannable; this is triage, not a design
document. Aim for roughly this shape:

```text
#17 · Key modifiers for Behavior GUI parameter buttons        enhancement · today
What it asks for: <one sentence, in your words, not the body's>
Where it stands:  <what already exists in the code that bears on it>
Plan:             <2-4 concrete steps naming real files>
Effort / risk:    Medium · low risk (display layer only)
```

Rules that keep this useful:

- **Name real files**, checked to exist. A plan that names a plausible-sounding path
  nobody verified is worse than no plan.
- If an issue is already done, say so and point at the code. Do not write a plan for it.
- If an issue is under-specified, say what you would need to know — do not pad the plan
  with a guess and present it as settled.
- Order by what you would do first, not by issue number. Say why the first is first.
- Bugs affecting a running experiment outrank enhancements.

Then a one-line overall recommendation.

## Step 4 — let the user choose

End by asking which to tackle. With four or fewer candidates use `AskUserQuestion` with
`multiSelect: true`, one option per issue, the label being `#N <short title>` and the
description carrying the effort estimate. With more than four, list them and ask in text.

Always leave "none of these / something else" reachable — the answer to a triage pass is
sometimes "none of that, do this instead".

## Step 5 — hand off

Once the user has chosen:

- **One issue** — go and do it. For anything past a small, obvious change, plan it first
  (`EnterPlanMode`) rather than editing straight away.
- **Several** — confirm the order, then work them one at a time, finishing each before
  starting the next. Do not interleave.
- Branch policy is the repo's: work on the current branch unless the user says otherwise,
  and **never push**. Commit with `/commit`, which knows the house message style.
- Reference the issue in the commit body (`Refs #17`) so the tracker links up. Do not
  write `Fixes #17` unless the user has said the issue is fully closed by that commit —
  that phrasing auto-closes the issue on push.
