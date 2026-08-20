# `gui.SubjectManager`

The window an operator uses to pick the animals running today. Choose a project, tick the subjects, press **Add Checked to Session** — each one gets a free box and the protocol it last ran, and together they become the session's whole subject list, so a four-box session takes two clicks instead of four dialogs and four file browsers.

```matlab
epsych.RunExpt          % then the Subjects toolbar button, or Ctrl+B
gui.SubjectManager      % or standalone, from the command line
```

> **Status: under development.** Run `tmp/smoke_test_subject_manager.m` after any change.

---

## What it replaces

The old **Add Subject** toolbar button opened a modal dialog for one animal, then forced a file browser for its protocol — every session, for every animal, with nothing remembered in between. That button now opens this window; the one-at-a-time dialog is still here as **New Subject...**, and `epsych.RunExpt.AddSubject` remains as the programmatic API.

A lab that points `FUNCS.AddSubjectFcn` at its own dialog keeps working: **New Subject...** and **Edit Subject...** both route through the same dispatch (`epsych.RunExpt.dispatchAddSubjectFcn_`), so there is still exactly one place that knows how to open a subject dialog.

**Box IDs in that dialog:** all 16 boxes are always listed and box 1 is always the default, unmarked either way — the dialog used to hide occupied boxes, which made box 1 disappear the moment a second subject was added. Picking an occupied box anyway is the operator's call; if two rows in the same batch want it, the second is reported as skipped at commit ("box 1 is already taken") instead of being silently prevented. A box held by a subject the commit is about to remove is not occupied at all, so the animal replacing it can keep the same box.

---

## Layout

| Region | Widget | Why |
|---|---|---|
| Toolbar (top) | `uitoolbar` | The same actions as the menus, one click away. See [Toolbar](#toolbar) below. |
| Projects (left) | `uilistbox` | Projects are a flat, single-selection set; a listbox gives arrow-key and type-ahead navigation for free. A tree would show a two-project subject twice with ambiguous checkbox state. |
| Subjects (right) | `uitable` | Each row needs its own box assignment *before* it is committed. A checkbox tree has no columns; a listbox would force a second modal — exactly the step this collapses. |

Under the toolbar, a single line shows the **full path** of the roster file in effect, with a **Change...** button beside it. Two rigs can be pointed at different rosters and everything below acts on this one, so where the records live is a question the window answers without being asked — a bare `subjects.esub` answers none of it, and a path hidden in a tooltip is not an answer either. The button is deliberately redundant with the toolbar tool and `File > Roster File...`: those are where the action belongs, this is where someone looks when the path on the left is not the one they expected.

The line turns amber and appends a reason when something is wrong:

| Marker | Meaning |
|---|---|
| `(read-only)` | The file cannot be written — unparseable, or written by a newer build. |
| `(folder not found)` | The **path is stale**: the folder it names is gone. A share that moved, a drive not mounted, a folder deleted. |

That second one matters more than it looks. A stale path is otherwise indistinguishable from a fresh empty roster — same empty table, same silence — which is how a rig can appear to have lost every animal when nothing has been lost at all. Worse, `saveAtomic_` *creates* a missing folder, so without this the next project would re-create that dead folder and save into it. The empty state explains the situation, and `ensureRoster_` refuses to write until the path is fixed. Naming a file inside a folder that **does** exist stays silent: that is the normal way to start a roster.

### The first time: choosing where the roster lives

EPsych keeps **no default location** for subjects and projects — see [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md#where-the-file-lives--there-is-no-default) for why the old `prefdir` fallback was a bad place for a lab's only copy.

So on a rig that has never been pointed at one, this window opens *unbound*: the header reads `Roster: (no file chosen)`, the table is replaced by an explanation of the choice, and every action is switched off **except New Project and New Subject** — clicking one of those is how the operator is asked, and their tooltips say so before the click.

The prompt (`ensureRoster_`) has exactly two exits: name a file, or close the window. Cancelling the file browser asks again. Nothing offers to proceed without a roster, because that would mean filling in an animal or a project with nowhere to save it.

The same prompt fires for a **stale** path (folder gone), for the reason given under [Layout](#layout): otherwise the record is saved into a resurrected dead folder.

Browsing never prompts. A roster is only demanded by an action that writes.

### Toolbar

Sixteen tools in five groups, left to right, in the order the work happens:

| Group | Tools |
|---|---|
| Roster | Refresh · Roster File... · Export CSV... |
| Project | New · Copy · Edit · Delete |
| Subject | New · Edit · Delete from Roster |
| Membership | Add to Project · Remove from Project · Retire/Restore |
| Session | Set Protocol for Checked... · **Add Checked to Session** |

This replaced the row of text buttons that used to run across the top. Every tool is also a menu item and, for the common ones, a button beside the widget it acts on — all three surfaces are switched together in `updateEnableStates_`, so they can never disagree about whether an action is available.

Two icons carry meaning worth spelling out, since a toolbar has no labels to lean on. *Remove from Project* is a red arrow leaving a folder while *Delete from Roster* is a red cross on a subject — the reversible action and the irreversible one must not look alike. And *Retire* wears two faces: it shows an arrow going down into a box, and swaps to a green arrow coming back out (with the tooltip to match) the moment every checked row is already retired, because an icon-only control cannot talk its way out of offering to retire a retired animal.

Icons are drawn as 16×16 pixel art by [`gui.toolbarIcon`](../../obj/+gui/toolbarIcon.m) rather than shipped as image files, so the toolbox carries no binary assets and a glyph is edited where it is named. `epsych.RunExpt` draws its toolbar from the same function. Note that `uibutton`/`uiimage` `Icon` accepts only four built-in names (`success`, `error`, `warning`, `info`), so any other glyph has to be drawn or supplied as a file.

`‹All Projects›` is pinned at the top of the project list. It is not a project: it shows every subject regardless of membership, and it is both the empty state for a fresh roster and the way to find a subject whose project you have forgotten.

Below the project list, an info card shows the selected project read-only: its name, notes, and then one row per setting — investigator, IACUC protocol, default protocol, data path, behavior GUI, and a `Template` row collecting the rest of the session defaults — so you can see what the template stamps without opening the edit dialog. The behavior GUI is named even when the project inherits it (`Behavior GUI: (built-in default)`), since a field that goes silent when unset reads as a field that does not exist. The other fields appear only when set: they carry no default worth announcing. An archived project says so in a `Status` row.

It is a label-and-value grid rather than one wrapped paragraph. In a column this narrow a paragraph wraps the values into each other, and the values are what an operator scans for — so the labels are short and fixed-width on the left, and what a short label leaves out goes in its tooltip (`Protocol` carries the full path of the `.eprot`, `IACUC` says the number is recorded and never enforced). The whole card, links included, is rebuilt on every selection by `updateProjectSummary_`; the plain-text lines it renders are also kept on `H.projectSummaryText`, which is the only form a test can read back once the same text is spread over two dozen labels. The left column is 330 px wide to pay for it, and a window remembered at the old, narrower size is floored at the default so the action bar cannot end up clipped.

### Links

The card's last row lists the project's [links](../epsych/epsych_SubjectRoster.md#links-and-why-the-scheme-is-checked) as clickable `uihyperlink`s — the lab notebook, the shared sheet, the analysis folder — with the full address as each one's tooltip. They sit in the card with the fields they belong to rather than floating below it. When a project has none, the row collapses to nothing rather than leaving a gap.

They are the only clickable-through thing in this window, so two details matter:

- The hyperlink's own `URL` is deliberately **left empty**, and the click is routed through `epsych.SubjectRoster.openLink`. A `uihyperlink` with a `URL` navigates by itself, before anything has re-checked an address that came out of a file someone else can write.
- A `file:` address naming a folder opens in the platform's file manager, not a browser, which would show an unhelpful directory listing or nothing at all.

A refused address is reported in a `uialert` and logged; it never throws out of the callback.

### Archived projects

**Show archived projects**, under the project list, is the project-level counterpart of *Show retired* for subjects. An archived project keeps its subjects, its memberships, and their protocol memory — only this list hides it, and it is still marked `(archived)` in the item text when shown, because a `uilistbox` has no per-item styling.

The project **currently selected is never hidden**, even with the toggle off. Archiving from the edit dialog would otherwise make the project you were just looking at disappear, which reads as having deleted it.

### Copying a project

**Copy...**, beside New and Edit (also `Project > Copy Project...` and the two-folders tool), starts a new project from one that already works. It is the answer to a study's second phase, a replication, or a sister experiment: a whole template set exactly right on one project, and no reason to retype any of it. Copied members are stamped from the **new** project's template, never from their source memberships, so the next phase starts on agreed settings rather than inheriting per-subject divergence.

Two questions, asked in this order:

1. **What about the subjects?** — `Copy with Subjects` or `Settings Only`. Asked first because it is the one thing the edit dialog cannot show, and skipped entirely for a project with no active members. Copied subjects **stay in the source as well** — membership is many-to-many, so a subject is simply in both — and each keeps the protocol it is on. Retired members are left behind; the prompt says how many when there are any.
2. **The copy itself**, in the ordinary project dialog under the title **Copy Project**, seeded with every inherited value and a name that does not collide (`Tone Detection (copy)`, then `(copy 2)`). Nothing is written until OK, so this is where the copy is renamed and pointed at the next phase's protocol.

The copy does **not** inherit `Archived`: it is made to start work, and one that opened hidden would look like nothing had happened. Tick Archived in the dialog to clone an archived project as archived.

`epsych.SubjectRoster.copyProject` is the engine, and it takes two more options the window does not offer — `IncludeRetired` and `CopyProtocolMemory` — for scripted copies. See [Copying a project](../epsych/epsych_SubjectRoster.md#copying-a-project).

### The project dialog

**New Project...** / **Copy...** / **Edit Project...** share one dialog, with two tabs.

**Project** holds the identity: name, notes, its bookkeeping (**Investigator**, **IACUC Protocol**), its **Links**, and an **Archived** checkbox.

**Session Defaults (template)** holds what is stamped onto a subject's **membership** when it joins the project: **Default Protocol**, **Data Save Path**, **Saving Function**, **Behavior GUI**, **Timer Period**, the four **Timer ... Fcn** callbacks (the trial loop itself — a custom loop travels with the study), **Video Recording Path**, **Intan Recording Path**, and **Intan Settings File**. Editing the template does **not** change existing members — that is what *Re-apply Project Template to Checked* on the Project menu is for. Most of these were RunExpt's **Customize** dialog until they moved here — see [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md#the-membership-carries-the-session-settings-the-project-is-its-template) for how each one reaches the session, and [the RunExpt overview](../overviews/RunExpt_GUI_Overview.md#6-customization) for what stayed behind as a machine setting.

### The membership dialog

**Session Settings...** (Subject menu, and the row context menu's *Session Settings for This Row...*) opens the same field grid — minus the Default Protocol row, since a membership's protocol goes through the protocol-memory workflow — on **one subject's membership** in the selected project. This is how one animal deliberately diverges from the template: a longer timer period for a slow subject, a different saving function for a pilot. It refuses blanks exactly as the template dialog does, so the all-inherit state can never be created here.

#### Nothing in those dialogs opens blank

Every session default arrives already filled in: from **the value last used in these dialogs**, else the built-in default (`ep_SaveDataFcn`, `ep_GenericGUI`, the `ep_TimerFcn_*` callbacks, 0.01 s; the paths from `RunExpt/DataPath`, `ep_RunExpt_Video`, `ep_RunExpt_Intan`). The recents are stored per field under `ep_RunExpt_Subjects` as `Recent<Field>`, capped at 12, most-recent-first, and written only when OK is accepted — a cancelled or refused dialog must not seed the next project with a typo. They are *user* preferences, not roster contents, so two rigs sharing one roster still propose their own drives.

OK refuses a blank Data Save Path, Saving Function, any of the four Timer Fcns, Video Recording Path, or Intan Recording Path. A blank one would silently inherit whatever the previous study left on the rig, which is the ambiguity moving these here was meant to remove. Two fields may stay empty on purpose: **Default Protocol**, because a study is usually created before its protocol exists, and **Intan Settings File**, because there is no default file to propose and the `.eprot` usually carries its own.

The Intan paths are refused if they contain spaces, which RHX commands cannot express; the saving function and the four timer callbacks are tinted pale red if they do not resolve or do not carry the expected signature (`SaveFcn(RUNTIME)`; `Start` takes `(RUNTIME, CONFIG)` and returns `RUNTIME`, the other three take and return `RUNTIME`).

Links are an editable two-column table — a table rather than a growing stack of edit fields, because the count is unbounded and both columns are free text — with **Add**, **Remove**, and **Open** beside it. *Open* is there so an address can be checked before it is saved rather than after.

Addresses are validated **in the dialog**, not only on commit, so a refusal arrives while the operator can still see and fix what they typed; the normalized form (an added `https://`, a path turned into a `file:///` URL) is written back into the table on OK, so what is saved is what is shown. A blank label is filled in from the host. A row with an address and no label is fine; a row with a label and no address is an error, while a wholly blank row is just the one **Add** created and is dropped.

| Behavior GUI choice | Meaning |
|---|---|
| `(built-in default)` | Leave the session's `FUNCS.BehaviorGUI` alone (`ep_GenericGUI`) — the inherit state |
| `(none)` | Run with no behavior GUI |
| a function or class name | Launch it at run start, `feval(name, RUNTIME)` |

The dropdown is editable, and its list is drawn from **the behavior GUIs other projects in this roster already use**, the recently-used ones, and `ep_GenericGUI` — not from the session's `RecentBehaviorGUI` preference. The roster is the shared thing, so a rig that has never run a paradigm still proposes its GUI, and the dialog works with no session open. A typed name that does not resolve on the path is tinted pale red but still accepted: a lab may add its GUI to the path later.

`(built-in default)` is reachable but is not what a new project opens on — like every other session default, the field is seeded with a real value.

**This is where the behavior GUI is configured.** It was **Customize → Behavior GUI Function**; the GUI belongs to a paradigm rather than to a rig, and a rig alternating between two studies had to be re-pointed by hand between sessions. Customize now leaves a grey line in that field's place saying where it went. See [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md#the-behavior-gui-in-three-states) for how the three states reach `FUNCS.BehaviorGUI`.

### Columns

| Column | Editable | Notes |
|---|---|---|
| ✓ | yes | The multi-select |
| Subject | no | |
| Box | **yes** | Blank means "assign the lowest free one". Values outside 1–16 are rejected and the old value restored. |
| Protocol | no | See below |
| Version | no | The protocol version this subject is on — see [Protocol versions](#protocol-versions) |
| Settings | no | `template` when the membership still matches the project's Session Defaults, `edited` when it has diverged (via *Session Settings...*), blank in the All Projects view. What makes the commit-time mismatch refusal predictable before the click. |
| Species, Sex, Weight, Last Run | no | So two similarly-named animals are distinguishable |
| Status | no | Active / Retired |

**Why Protocol is read-only in the grid:** `uitable`'s `ColumnFormat` is per-column, not per-row, so a dropdown there would share one item list across every row and could not offer each subject its own remembered protocol. Instead, right-click gives **Set Protocol for This Row...** and **Set Protocol for Checked Rows...**, which covers both the common case (one protocol for the whole project) and the exception.

---

## Protocol versions

A protocol gets edited between sessions and nobody notices — the `.eprot` is overwritten in place, and the animals that were on last week's version go on running without anything saying so. The **Version** column and the **Protocol** menu are the answer.

### Reading the column

It shows the version the subject is **on**, not the newest one available, so a row reads as a statement about that animal rather than about the file:

| Cell | Meaning |
|---|---|
| `v7.260814` | The recorded version. Plain when it matches the file. |
| `v7.260814` in **bold orange** | The file has been saved since — this subject is behind |
| `v4.260801 (held)` in **bold blue** | Behind the file because a revert put it there. Its sessions load that version out of the file's archive |
| `not recorded`, greyed | Never committed to a session, so there is nothing to compare |
| `(missing)`, bold orange | The `.eprot` is gone |
| greyed, whatever it says | A retired member — outside the version workflow entirely |

When anything is behind, a banner opens above the table naming the count, with **Update All to Latest** beside it; the table's tooltip names the subjects and both versions. The banner collapses to nothing the moment there is nothing to say — a stale-protocol warning is exactly what an operator will not think to go looking for, so it announces itself rather than waiting to be checked.

Held subjects are the deliberate exception, drawn in blue rather than the warning orange and never the reason the banner opens: nothing is wrong with a subject somebody chose to keep on an earlier version, and sending the operator to *Update All* to fix what they themselves asked for would be worse than saying nothing. They are named in the tooltip and in **Check Protocol Versions**, and counted in the banner only when it is already open for something else. Updating a held subject is what ends the hold — the confirmation says so before you agree, since for that animal an update is not bookkeeping but a change to what it runs.

### Retired members are outside all of this

A retired subject is **never** counted, coloured, or updated by anything on this page. Its recorded protocol is the record of what it actually ran; moving it onto a version saved afterwards would rewrite that, for a session that is never going to happen. So a retired member behind the file does not open the banner, does not appear in the tooltip or in **Check Protocol Versions**, and is skipped by every update — including *Update All in Project*. Its Version cell is greyed like the rest of its row rather than drawn in orange, because a warning with no action behind it is just noise.

The menu items follow: with only retired rows ticked, **Update Checked** and **Switch to Project Default** are unavailable, and **Revert Protocol Version...** is unavailable on a retired row. Asking anyway — through the right-click menu, which stays live because it acts on the row under the pointer — says why and changes nothing. Where an update did go ahead with retired rows ticked alongside active ones, the confirmation and the status line both say how many were skipped, so a count that does not match the ticks is explained before it is noticed.

Restore the subject to the project (tick *Show retired*, press **Restore**) and it rejoins every one of these surfaces immediately.

### The Protocol menu

| Item | Scope |
|---|---|
| **Check Protocol Versions** | Every active subject shown: counts by state, then the subjects that are behind, with both versions. Retired rows are counted out, and the report says how many |
| **Open in Protocol Designer** | The selected row's protocol — including an uncommitted **Set Protocol...** override, so the two columns and the designer always agree on which file |
| **Update Checked to Latest Version** | The ticked rows, retired ones skipped |
| **Update All in Project to Latest Version** | Every **active** member, **including any hidden by the filter** — "all" that quietly meant "all visible" would leave stragglers behind exactly when you believed otherwise. Retired members are not stragglers; they are done |
| **Switch Checked to Project Default Protocol** | Moves them onto the project's file as well as its version |
| **Revert Protocol Version...** | The selected row |

The same actions for a single row are on the right-click menu. Updating confirms first, and names versions rather than counting rows: *"tone.eprot: v4 → v7 (6 subjects)"* is a question an operator can answer; *"update 6 subjects?"* is not. Identical moves collapse to one line, so a project on one protocol is one sentence.

Updating changes no protocol *content*, and none is needed — a session loads the `.eprot` at commit time, so the newest saved version runs either way. What it records is the version each subject is now expected to be on, which is what clears the warning and makes the *next* unexpected edit visible.

### Reverting

**Revert Protocol Version...** lists what the roster recorded for that subject and marks each entry with where its version can still be found:

| Marker | Meaning |
|---|---|
| *(none)* | The named file still holds that version — re-pointing is enough |
| `[in file's version archive]` | The file was saved over, but every save archives the version it replaces inside the `.eprot` — the content can come back |
| `[file now holds v5 — not archived]` | The file was last saved by an EPsych release without version archiving; only the pointer and recorded version come back, and the subject runs whatever the file holds |
| `[file missing]` | The `.eprot` is gone |

Selecting an entry states, under the list, exactly what going back to it does — whether the subject ends up on the protocol as it was, and whether anything is written to the `.eprot` — in orange for the two cases that cannot come back in full (`not archived`, `file missing`). It is one window: the consequence is read where the choice is made, not raised as a second dialog afterwards, which a modal `uifigure` could leave stranded behind an undismissable window.

An archived entry carries the one choice there is, as the checkbox under the list — and it is **not** a choice between exact and approximate. Either way the subject ends up on that version exactly; what the checkbox decides is whether the *file* moves too:

- **Unticked** (the default) holds this subject alone on the version. The `.eprot` is untouched and keeps serving every other animal on it what it holds now; this subject's sessions load the held version out of the file's archive until an update releases it.
- **Ticked**, the `.eprot` itself is rewritten back through [`epsych.Protocol.restoreVersion`](../epsych/epsych_Protocol.md#4-version-history), which changes the file for *every* subject on it. The content a restore replaces is archived in turn, so it is itself undoable.

Unticked used to be the cosmetic option — the record changed, but the session loaded the file anyway and then wrote the file's version back over the revert. Now that it delivers the version it names, it is the default: rewriting a shared file is the bigger action, and should be the one you have to ask for.

**Show Changes...** answers the question the consequence text cannot: not what reverting does to the roster, but what the subject would *run* differently afterwards. It opens the comparison window ([`gui.compareProtocolVersions`](../epsych/epsych_Protocol.md#comparing-two-versions)) on what the subject is on now against the selected entry — across two files when the protocol was revised by saving it under a new name — listing every parameter, option, and interface setting that differs, with a filter and a Copy Report button. It writes nothing, and is off for a `[file missing]` or `[... not archived]` entry, whose content cannot be produced to compare.

Revert is itself undoable too — the protocol being left goes onto the history in place of the one restored.

All of the above is [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md#protocol-versions); this window only renders it.

---

## Add Checked to Session

The button collects what you ticked and typed; every decision belongs to [`epsych.SubjectRoster.assignToSession`](../epsych/epsych_SubjectRoster.md). Boxes and protocols are resolved and each membership's session settings are applied to the session, but **everything is validated before `CONFIG` is touched** — a protocol that fails to load halfway through must never leave a half-populated session.

**The checked subjects become the session's whole subject list.** Whoever is in the session window's table is removed as they land — what you tick here is the answer to "who is running today", and an animal left over from the last session would sit in a box dispatching trials. Re-ticking a subject that is already in the session is therefore normal, not a duplicate: it keeps its place, and its box if you left the Box cell alone. The names removed are listed in the commit report, and the session status line counts them.

- Refused outright while a session is running, or with no session window open (the button is disabled and says why).
- A missing protocol, or needing more than 16 boxes, **aborts the whole batch** and changes nothing — including the subjects already in the session, which are cleared only once the commit is certain.
- Checked subjects whose memberships **disagree on a session-level setting** abort the whole batch too — one session cannot run two saving functions. The refusal names the field and who carries what; the fixes it names are *Session Settings...* and *Re-apply Project Template*, and the **Settings** column shows the divergence before the click.
- A subject with no protocol resolvable at all is skipped and reported; the rest still go in. If *nothing* is usable, the session keeps the list it had.
- On success the window closes and the session window is raised — the next stop is the session, not this table. It stays open on a partial commit (so the skipped-subject report is visible) or when the batch is refused or aborted, so the operator can fix the problem without reopening it.

---

## Retiring versus removing versus deleting

Three different things, deliberately:

| Action | Effect | Reversible |
|---|---|---|
| **Retire** | Hidden from this project's picker; keeps its protocol memory | One click (tick *Show retired*, press **Restore**) |
| **Remove from Project** | Drops the membership and that project's protocol memory. Subject and its other projects untouched | Re-add, but the memory is gone |
| **Delete from Roster** | Removes the record entirely. Saved experiment data is not affected | No |

Delete is menu-only, confirmed, lists every project the subject will vanish from, defaults to **Cancel**, and is refused outright while the subject is in the live session. The <kbd>Delete</kbd> key is bound to *Remove from Project* — the reversible one — never to roster deletion.

Deleting a **project** never deletes its subjects.

---

## Keyboard

| Key | Action |
|---|---|
| <kbd>Ctrl</kbd>+<kbd>F</kbd> | Focus the filter |
| <kbd>Ctrl</kbd>+<kbd>N</kbd> | New subject |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>N</kbd> | New project |
| <kbd>F5</kbd> | Refresh (re-read the roster) |
| <kbd>Delete</kbd> | Remove from project (confirmed) |
| <kbd>Esc</kbd> | Close |
| <kbd>Space</kbd> | Toggle the focused row's checkbox |

The filter is a live search: the list narrows on every keystroke, before you press Enter. It matches Name, Species, and Notes with a case-insensitive `contains` anywhere in the text — not a prefix, so `123` finds `SUBJ-ID-1231`, `SUBJ-ID-1232`, and `SUBJ-ID-12314b` — and **never a regex**, so typing `M(1` narrows the list instead of raising an error.

Two things make the live path work. The in-flight keystrokes are held in `LiveFilter_` rather than written back into the edit field: assigning `Value` from inside `ValueChangingFcn` re-renders the field mid-edit and drops characters, so a filter typed as `123` would search only `1`. And typing calls `refresh(Reload = false)` — re-filtering is a view change over records already in memory, and a roster on a network drive would otherwise be re-read once per character.

---

## What is remembered

Stored under `ep_RunExpt_Subjects` and `epsych2_gui_SubjectManager`:

- the selected project, **keyed by roster path** so re-pointing the roster file cannot restore a project belonging to a different one;
- the *Show retired* and *Show archived projects* toggles;
- the window position.

Only *operator* selections are remembered. Setting the project programmatically — including `revealSubject` — deliberately does not persist, so a script driving this window cannot clobber what the operator chose.

The browse dialogs remember where they were last pointed, under `ep_RunExpt_Setup`:

- `PDir` — the last protocol directory, shared with the session window's own protocol pickers, so a lab that keeps its protocols in one place browses there from either window. Written by both **Set Protocol...** and the project dialog's **Default Protocol** browse.
- `DDir` — the last directory picked for a project's **Default Data Path**. Falls back to the session default (`RunExpt`/`DataPath`) the first time, since projects are usually created in batches under one data root.

Either browse still starts from the path already in the field when that path exists; the remembered directory is only the fallback.

---

## Empty states

Never a modal; always a centred explanation where the table would be — no roster yet (naming where it will be created), no projects, an empty project, a filter that matched nothing, or a roster that could not be read. Opening against a completely empty roster with no session is a supported, tested path.

---

## Two-way navigation

The session window's subject list gains **Show in Subject Manager**, which opens this window with that animal selected (switching project and revealing it even if retired). The reverse direction is the Add Checked to Session button, which raises the session window once the rows land in it — after the skip report is dismissed, when there was one — and then closes this one, since a full commit is the end of the visit. **Edit Subject Details...** in the same context menu edits a session subject in place and mirrors the change into the roster.

---

## Options

| Argument | Default | Meaning |
|---|---|---|
| `runExpt` | the live session, or `[]` | Session to commit into. `[]` is fine: the roster stays fully browsable. |

## Methods

`refresh` re-reads the roster and repopulates everything — every callback ends there, so the window can never show a half-updated view. `refresh(Reload = false)` skips the disk read and only repaints; the filter is its one caller. `addToSession` commits the checked rows. `revealSubject(name)` selects a subject, switching project and clearing the filter to make it visible.

---

## Testing

```
matlab -batch "cd('tmp'); smoke_test_subject_manager"
```

Asserts the window lifecycle and single-instance rule, the empty-roster-and-no-session path, filtering (a regex-looking string, and live search driven one keystroke at a time through the real `ValueChangingFcn`), the retired toggle, all three box-GUI states in the project summary, ticking plus a typed box reaching `CONFIG`, the session window being raised and this one closed by a clean commit, the remembered project surviving a close, `revealSubject` handling both a retired subject and an unknown name, and a retired member being left out of the banner, of every update, and of revert.

The toolbar is asserted as a whole rather than tool by tool: every tool must carry a 16×16 icon and a tooltip — a toolbar has no labels, so a tool with neither is unusable — its Enable must follow the ticks alongside the button and menu item, and the Retire tool must swap both icon *and* tooltip when the checked rows are already retired.

Protocol versions are asserted end to end against a real `epsych.Protocol.save`: the Version column carries the recorded version, the banner opens when the file is saved behind the window's back and closes once `updateProtocol` has run, and the column then shows the new version. The update and revert *commands* are engine-tested in `smoke_test_subject_roster` instead — both open a confirmation the operator has to answer, so what is checked here is that the window notices and stops saying so.

Project options are asserted the same way: the summary names the investigator and IACUC number, both links render as `uihyperlink`s carrying no `URL`, a linkless project collapses the panel to zero height, and an archived project hides, stays reachable by ID, and survives the toggle going off while it is selected. The dialog itself is driven for real — the Edit button is pressed and the modal window inspected and cancelled from a timer, since `projectDialog_` blocks in `uiwait`. That timer repeats rather than firing once (the figure is findable by name while its controls are still being laid out, so the probe waits for Cancel to exist), and its `StopFcn` deletes whatever is left standing, so a probe that simply missed the window fails the test instead of hanging it.

Copy is asserted on both halves. Its three surfaces switch off in the All Projects view like Edit and Delete, since there is nothing to copy there; the copy appears in the project list with the source's members and leaves the source untouched. The dialog half is driven through the same probe, from a project with **no** members so the subjects question — an in-figure `uiconfirm` the probe cannot reach — is not raised: it must open titled `Copy Project` rather than `Edit Project`, on a name that does not collide, and cancelling must leave nothing behind.

See also: [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md), [`gui.BehaviorGUI`](gui_BehaviorGUI.md), [RunExpt GUI Overview](../overviews/RunExpt_GUI_Overview.md)
