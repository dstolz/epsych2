# Class reference pages

Every class in this repository gets one wiki page: a **class card** — the diagram,
the contract, the members, and the defaults that are not obvious from the member
list. [[hw.Interface-Class-Reference]] is the worked example; copy its shape.

A class page is not a third copy of the docs. Three layers, in order of authority:

| Layer | Answers | Lives in |
|---|---|---|
| `documentation/<pkg>/<pkg>_<Class>.md` | Why it works this way, at length | Code repo — **authoritative** |
| Class page (this file) | What the members are, how they relate, what the defaults mean | Wiki, one per class |
| Guide page (Hardware-Abstraction-Layer, …) | How to get a job done | Wiki, one per topic |

When a class page and a repo doc disagree, the repo doc wins and the page is
wrong. When a class has no repo doc, the class page may be the only prose there
is — say what the code does, and do not invent rationale.

## Which classes get a page

All of them, from `bash .claude/skills/update-wiki/classes.sh` — 107 today, across
`obj/`, `helpers/`, `runtime/`, and `paradigms/`.

**`obj/stimgen/` is excluded.** It is a separately released submodule pinned to a
commit; its class inventory belongs to its own repository and its own
documentation. The index links out to it and stops there (see CLAUDE.md).

## Naming and navigation

- File name: `<qualified.Name>-Class-Reference.md` — `hw.Interface-Class-Reference.md`,
  `epsych.Runtime-Class-Reference.md`, `PRGMSTATE-Class-Reference.md`. The script
  assumes exactly this; a page named anything else reads as missing.
- Title: `` # `hw.Interface` Class Reference ``, optionally preceded by the topic
  icon the matching guide page uses (`images/icons/hardware.svg`).
- **Class pages do not go in `_Sidebar.md`.** A hundred entries would bury the
  guides. Only [[Class-Reference]] is in the sidebar and in the Home table; the
  index is how a reader reaches a class page.
  The exception already made: `hw.Interface` is linked directly from the sidebar
  because the hardware guide leans on it. Add a direct link only when a guide
  page sends readers to that class constantly.
- Link a class page from the guide page that covers its area, and from the
  related class pages — a page nothing links to is a page nobody reads.

## Page skeleton

Sections in this order; drop the ones a class has nothing for rather than
padding them.

```markdown
# `pkg.Class` Class Reference

One sentence saying what the class is, then the source link:
[obj/+pkg/@Class/Class.m](https://github.com/dstolz/epsych2/blob/master/obj/%2Bpkg/%40Class/Class.m).

Where this page sits: the class card. For the workflow, see [[Guide-Page]];
for the long-form rationale, the repo doc linked at the bottom.

## Table of contents          <- only when the page has 5+ sections

## Class diagram              <- required; see below
## Inheritance                <- superclass/mixins and what each one buys
## What a subclass must define <- abstract classes only
## Properties                 <- table: name, type/attributes, role
## Methods                    <- table or subsections, grouped by purpose
## Events                     <- classes that declare or fire them
## Defaults that are decisions <- the non-obvious ones, with the why
## Usage                      <- runnable MATLAB, copied from a real caller
## See also                   <- guide pages, related class pages, repo docs
```

Rules for the prose:

- Declarative, mechanism-first, in the repo's voice. State the consequence:
  "`RunOffline` keeps the interface in the array — removing it would take its
  parameters out of `dispatchNextTrial`", not "this flag is used for offline mode".
- Document **public, protected, and static** members. Private members appear only
  when a public behavior cannot be explained without them.
- Give a default when there is one, and say what it means. `canRunOffline` →
  `false` → "this backend declines" is the whole point of the hook.
- Every claim comes from the source you just read. Do not carry a member forward
  from an older version of the page because it was there last time.

## The class diagram

One ```` ```mermaid ```` block, `classDiagram`, right under the intro. It is the
reason these pages exist: a reader should see the shape before the tables.

What to draw, by kind of class:

| Kind | Draw |
|---|---|
| Abstract base | The base with its abstract and concrete members, its collaborators, plus a **second** diagram of the subclass hierarchy |
| Concrete backend / subclass | The class, its superclass (members elided), and what it owns or talks to |
| GUI component | The component, its mixins (`gui.PopOut`, `matlab.mixin.SetGet`), and its data source (`hw.Parameter`, `psychophysics.Psych`) |
| Value / data class | The class and its owner, with multiplicity — a value class alone on a canvas says nothing |
| Enumeration | `<<enumeration>>` with the members; relate it to the class whose property it types |

Syntax that actually matters — these are the things that break a render:

- **No dots in class names.** `class hw.Interface` does not parse. Drop the
  package prefix (`Interface`, `Module`, `Parameter`) and put one line under the
  diagram: "Everything below is in the `hw` package; the diagram drops the prefix."
  When a diagram spans packages, keep the prefix off and disambiguate in the
  relationship label.
- **One classifier per member.** `*` = abstract, `$` = static. `+getCreationSpec()$*`
  is not valid; pick the one that matters and say the rest in the table.
- Visibility prefixes: `+` public, `#` protected, `-` private, `~` package.
- Annotations: `<<abstract>>`, `<<enumeration>>`, `<<interface>>` — one per class,
  first line of the body.
- `note for ClassName "..."` carries what the diagram cannot: MATLAB mixins,
  a handle-vs-value distinction, a "one per session" constraint.
- `direction LR` for wide/shallow, `direction TB` for deep hierarchies.

Relationship vocabulary — use these consistently across pages:

| Arrow | Means | Example |
|---|---|---|
| `A <\|-- B` | B inherits A | `Interface <\|-- TDT_RPcox` |
| `A "1" o-- "0..*" B` | A owns B, with multiplicity | `Module "1" o-- "0..*" Parameter` |
| `A --> B : label` | A holds a reference to B | `Parameter --> Module : back-reference` |
| `A ..> B : label` | A produces/returns B | `Interface ..> InterfaceSpec : getCreationSpec returns` |

Keep a diagram under about 40 member lines. Past that, elide the members of the
supporting classes (`class Module { }` with a body of nothing is fine) and let
the tables carry the detail — a diagram nobody can read is worse than no diagram.

## The index page

[[Class-Reference]] is generated, not hand-maintained:

```bash
bash .claude/skills/update-wiki/classes.sh --index
```

Paste the output between the markers in `Class-Reference.md`:

```markdown
<!-- BEGIN CLASS INDEX -->
...generated tables...
<!-- END CLASS INDEX -->
```

Everything outside the markers — the intro, the stimgen note, the See also — is
hand-written and survives regeneration. Regenerate whenever a class page is
added, a class is added or renamed, or a class comment changes.

A class **with** a page is linked `[[pkg.Class|pkg.Class-Class-Reference]]`; one
**without** shows its name in code plus a `[source]` link. That is deliberate:
the index is complete from the first day and never contains a broken wiki link,
and writing a page is what flips the row.

Groups and their order are defined in `group_for()` in `classes.sh`; rows inside a
group are alphabetical. Within-group order and group titles are the script's, so
do not hand-edit the tables — the next regeneration would throw the edit away.
A new package needs a `group_for()` case, or its classes fall into "Toolbox level".

The one-line description comes from the class's own header comment — the first
line of prose after any usage lines. **A bad description in the index is a bad
class comment**: fix `%` in the source, do not hand-edit the table.

## Maintaining pages

`classes.sh` reports three states against the `.synced-commit` baseline:

- **Missing a page** — the class exists, the page does not. Write it.
- **Page behind the code** — something under the class changed since the
  baseline. Re-read the class and refresh the page: members added, removed, or
  renamed change the **diagram** as well as the tables, and that is the part
  people forget.
- **Orphaned page** — the page exists, the class does not. The class was renamed,
  deleted, or moved into the submodule. Rename the page and fix inbound links, or
  delete it; then regenerate the index.

"Behind the code" is measured against `.synced-commit`, not against the page. A
page written *during* a sync still lists as behind until the marker moves at the
end of the run — check the page before rewriting it, and move on if it already
matches the source.

Refreshing is a re-read, not a diff-patch. Open the class file, walk its property
and method blocks, and correct the page against what is there. The failure mode
this avoids: a page that lists a method deleted three commits ago, which reads as
authoritative because everything around it is right.

Batch by package. Classes in one package share vocabulary and cross-reference
each other, and reviewing them together is what keeps twenty pages consistent.

## Before committing

- `bash .claude/skills/update-wiki/classes.sh` — coverage moved the way you meant.
- `bash .claude/skills/update-wiki/verify.sh` — no broken `[[links]]`, no dead
  source URLs. Class pages link to `master`; a class that exists only on a feature
  branch has no page yet.
- Re-read one diagram end to end. Mermaid failures are silent on GitHub: a syntax
  error renders as a grey box, and nothing in the lint catches it.
