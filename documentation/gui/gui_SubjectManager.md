# `gui.SubjectManager`

The window an operator uses to pick the animals running today. Choose a project, tick the subjects, press **Add Checked to Session** — each one gets a free box and the protocol it last ran, so a four-box session takes two clicks instead of four dialogs and four file browsers.

```matlab
epsych.RunExpt          % then the Subjects toolbar button, or Ctrl+B
gui.SubjectManager      % or standalone, from the command line
```

> **Status: under development.** Run `tmp/smoke_test_subject_manager.m` after any change.

---

## What it replaces

The old **Add Subject** toolbar button opened a modal dialog for one animal, then forced a file browser for its protocol — every session, for every animal, with nothing remembered in between. That button now opens this window; the one-at-a-time dialog is still here as **New Subject...**, and `epsych.RunExpt.AddSubject` remains as the programmatic API.

A lab that points `FUNCS.AddSubjectFcn` at its own dialog keeps working: **New Subject...** and **Edit Subject...** both route through the same dispatch (`epsych.RunExpt.dispatchAddSubjectFcn_`), so there is still exactly one place that knows how to open a subject dialog.

**Box IDs in that dialog:** all 16 boxes are always listed and box 1 is always the default, unmarked either way — the dialog used to hide occupied boxes, which made box 1 disappear the moment a second subject was added. Picking an occupied box anyway is the operator's call; the row is then reported as skipped at commit ("box 1 is already taken") instead of being silently prevented.

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

So on a rig that has never been pointed at one, this window opens *unbound*: the header reads `Roster: (no file chosen)`, the table is replaced by an explanation of the choice, and every action is switched off **except New Project, New Subject, and Import** — clicking one of those is how the operator is asked, and their tooltips say so before the click.

The prompt (`ensureRoster_`) has exactly two exits: name a file, or close the window. Cancelling the file browser asks again. Nothing offers to proceed without a roster, because that would mean filling in an animal or a project with nowhere to save it — and the first file chosen here adopts the roster an older build accumulated under `prefdir`, by copy, so an existing rig does not appear to have lost its animals.

The same prompt fires for a **stale** path (folder gone), for the reason given under [Layout](#layout): otherwise the record is saved into a resurrected dead folder.

Browsing never prompts. A roster is only demanded by an action that writes.

### Toolbar

Fifteen tools in five groups, left to right, in the order the work happens:

| Group | Tools |
|---|---|
| Roster | Refresh · Roster File... · Import from Config... · Export CSV... |
| Project | New · Edit · Delete |
| Subject | New · Edit · Delete from Roster |
| Membership | Add to Project · Remove from Project · Retire/Restore |
| Session | Set Protocol for Checked... · **Add Checked to Session** |

This replaced the row of text buttons that used to run across the top. Every tool is also a menu item and, for the common ones, a button beside the widget it acts on — all three surfaces are switched together in `updateEnableStates_`, so they can never disagree about whether an action is available.

Two icons carry meaning worth spelling out, since a toolbar has no labels to lean on. *Remove from Project* is a red arrow leaving a folder while *Delete from Roster* is a red cross on a subject — the reversible action and the irreversible one must not look alike. And *Retire* wears two faces: it shows an arrow going down into a box, and swaps to a green arrow coming back out (with the tooltip to match) the moment every checked row is already retired, because an icon-only control cannot talk its way out of offering to retire a retired animal.

Icons are drawn as 16×16 pixel art by [`gui.toolbarIcon`](../../obj/+gui/toolbarIcon.m) rather than shipped as image files, so the toolbox carries no binary assets and a glyph is edited where it is named. `epsych.RunExpt` draws its toolbar from the same function. Note that `uibutton`/`uiimage` `Icon` accepts only four built-in names (`success`, `error`, `warning`, `info`), so any other glyph has to be drawn or supplied as a file.

`‹All Projects›` is pinned at the top of the project list. It is not a project: it shows every subject regardless of membership, and it is both the empty state for a fresh roster and the way to find a subject whose project you have forgotten.

Below the project list, a read-only summary shows the selected project's notes, investigator, IACUC protocol, default protocol, data path, and behavior GUI — so you can see what will be applied without opening the edit dialog. The behavior GUI is named even when the project inherits it (`Behavior GUI: (session default)`), since a field that goes silent when unset reads as a field that does not exist. The other fields appear only when set: they carry no default worth announcing.

### Links

Under the summary, the project's [links](../epsych/epsych_SubjectRoster.md#links-and-why-the-scheme-is-checked) are listed as clickable `uihyperlink`s — the lab notebook, the shared sheet, the analysis folder — with the full address as each one's tooltip. When a project has none, the rows collapse to nothing rather than leaving a gap.

They are the only clickable-through thing in this window, so two details matter:

- The hyperlink's own `URL` is deliberately **left empty**, and the click is routed through `epsych.SubjectRoster.openLink`. A `uihyperlink` with a `URL` navigates by itself, before anything has re-checked an address that came out of a file someone else can write.
- A `file:` address naming a folder opens in the platform's file manager, not a browser, which would show an unhelpful directory listing or nothing at all.

A refused address is reported in a `uialert` and logged; it never throws out of the callback.

### Archived projects

**Show archived projects**, under the project list, is the project-level counterpart of *Show retired* for subjects. An archived project keeps its subjects, its memberships, and their protocol memory — only this list hides it, and it is still marked `(archived)` in the item text when shown, because a `uilistbox` has no per-item styling.

The project **currently selected is never hidden**, even with the toggle off. Archiving from the edit dialog would otherwise make the project you were just looking at disappear, which reads as having deleted it.

### The project dialog

**New Project...** / **Edit Project...** has two tabs.

**Project** holds the identity: name, notes, its bookkeeping (**Investigator**, **IACUC Protocol**), its **Links**, and an **Archived** checkbox.

**Session Defaults** holds what the project applies to a session when its subjects are added: **Default Protocol**, **Data Save Path**, **Saving Function**, **Behavior GUI**, **Timer Period**, **Video Recording Path**, **Intan Recording Path**, and **Intan Settings File**. Most of these were RunExpt's **Customize** dialog until they moved here — see [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md#a-project-owns-the-session-settings) for how each one reaches the session, and [the RunExpt overview](../overviews/RunExpt_GUI_Overview.md#7-customization) for what stayed behind as a machine setting.

#### Nothing on that tab opens blank

Every session default arrives already filled in: from **the value last used in this dialog**, else from this machine's own preference (`ep_RunExpt_FUNCS`, `ep_RunExpt_Video`, `ep_RunExpt_Intan`, `RunExpt/DataPath`). The recents are stored per field under `ep_RunExpt_Subjects` as `Recent<Field>`, capped at 12, most-recent-first, and written only when OK is accepted — a cancelled or refused dialog must not seed the next project with a typo. They are *user* preferences, not roster contents, so two rigs sharing one roster still propose their own drives.

OK refuses a blank Data Save Path, Saving Function, Video Recording Path, or Intan Recording Path. A blank one would silently inherit whatever the previous study left on the rig, which is the ambiguity moving these here was meant to remove. Two fields may stay empty on purpose: **Default Protocol**, because a study is usually created before its protocol exists, and **Intan Settings File**, because there is no default file to propose and the `.eprot` usually carries its own.

The Intan paths are refused if they contain spaces, which RHX commands cannot express; the saving function is tinted pale red if it does not resolve or does not take `(RUNTIME)` and return nothing.

Links are an editable two-column table — a table rather than a growing stack of edit fields, because the count is unbounded and both columns are free text — with **Add**, **Remove**, and **Open** beside it. *Open* is there so an address can be checked before it is saved rather than after.

Addresses are validated **in the dialog**, not only on commit, so a refusal arrives while the operator can still see and fix what they typed; the normalized form (an added `https://`, a path turned into a `file:///` URL) is written back into the table on OK, so what is saved is what is shown. A blank label is filled in from the host. A row with an address and no label is fine; a row with a label and no address is an error, while a wholly blank row is just the one **Add** created and is dropped.

| Behavior GUI choice | Meaning |
|---|---|
| `(session default)` | Leave the session's `FUNCS.BehaviorGUI` alone — the default for a new project |
| `(none)` | Run this project with no behavior GUI |
| a function or class name | Launch it at run start, `feval(name, RUNTIME)` |

The dropdown is editable, and its list is drawn from **the behavior GUIs other projects in this roster already use**, the recently-used ones, and `ep_GenericGUI` — not from the session's `RecentBehaviorGUI` preference. The roster is the shared thing, so a rig that has never run a paradigm still proposes its GUI, and the dialog works with no session open. A typed name that does not resolve on the path is tinted pale red but still accepted: a lab may add its GUI to the path later.

`(session default)` is reachable but is not what a new project opens on — like every other session default, the field is seeded with a real value.

**This is where the behavior GUI is configured.** It was **Customize → Behavior GUI Function**; the GUI belongs to a paradigm rather than to a rig, and a rig alternating between two studies had to be re-pointed by hand between sessions. Customize now leaves a grey line in that field's place saying where it went. See [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md#the-behavior-gui-in-three-states) for how the three states reach `FUNCS.BehaviorGUI`.

### Columns

| Column | Editable | Notes |
|---|---|---|
| ✓ | yes | The multi-select |
| Subject | no | |
| Box | **yes** | Blank means "assign the lowest free one". Values outside 1–16 are rejected and the old value restored. |
| Protocol | no | See below |
| Version | no | The protocol version this subject is on — see [Protocol versions](#protocol-versions) |
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
| `not recorded`, greyed | Never committed to a session, so there is nothing to compare |
| `(missing)`, bold orange | The `.eprot` is gone |

When anything is behind, a banner opens above the table naming the count, with **Update All to Latest** beside it; the table's tooltip names the subjects and both versions. The banner collapses to nothing the moment there is nothing to say — a stale-protocol warning is exactly what an operator will not think to go looking for, so it announces itself rather than waiting to be checked.

### The Protocol menu

| Item | Scope |
|---|---|
| **Check Protocol Versions** | Everything shown: counts by state, then the subjects that are behind, with both versions |
| **Open in Protocol Designer** | The selected row's protocol — including an uncommitted **Set Protocol...** override, so the two columns and the designer always agree on which file |
| **Update Checked to Latest Version** | The ticked rows |
| **Update All in Project to Latest Version** | Every member, **including retired ones and any hidden by the filter** — "all" that quietly meant "all visible" would leave stragglers behind exactly when you believed otherwise |
| **Switch Checked to Project Default Protocol** | Moves them onto the project's file as well as its version |
| **Revert Protocol Version...** | The selected row |

The same actions for a single row are on the right-click menu. Updating confirms first, and names versions rather than counting rows: *"tone.eprot: v4 → v7 (6 subjects)"* is a question an operator can answer; *"update 6 subjects?"* is not. Identical moves collapse to one line, so a project on one protocol is one sentence.

Updating changes no protocol *content*, and none is needed — a session loads the `.eprot` at commit time, so the newest saved version runs either way. What it records is the version each subject is now expected to be on, which is what clears the warning and makes the *next* unexpected edit visible.

### Reverting, and what it cannot do

**Revert Protocol Version...** lists what the roster recorded for that subject and marks each entry with whether going back is exact. It is exact when the entry names a different `.eprot` that still holds its recorded version. It is **not** exact when the file has since been saved over: `epsych.Protocol.save` overwrites in place and keeps no archive, so a v4 that became v5 exists nowhere on disk. Those entries are marked `[file now holds v5]`, and reverting to one restores the pointer and the recorded version while saying plainly that the content did not come back.

Revert is itself undoable — the protocol being left goes onto the history in place of the one restored. To make going back exact, revise protocols as **separate files** (`Save As` per revision) rather than saving over one.

All of the above is [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md#protocol-versions); this window only renders it.

---

## Add Checked to Session

The button collects what you ticked and typed; every decision belongs to [`epsych.SubjectRoster.assignToSession`](../epsych/epsych_SubjectRoster.md). Boxes and protocols are resolved and the project's behavior GUI is applied to the session, but **everything is validated before `CONFIG` is touched** — a protocol that fails to load halfway through must never leave a half-populated session.

- Refused outright while a session is running, or with no session window open (the button is disabled and says why).
- A missing protocol, or needing more than 16 boxes, **aborts the whole batch** and changes nothing.
- A subject already in the session, or with no protocol resolvable at all, is skipped and reported; the rest still go in.
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

The session window's subject list gains **Show in Subject Manager**, which opens this window with that animal selected (switching project and revealing it even if retired). The reverse direction is the Add Checked to Session button, which raises the session window once the rows land in it — after the skip report is dismissed, when there was one — and leaves this window open behind it, since adding is rarely the end of the visit. **Edit Subject Details...** in the same context menu edits a session subject in place and mirrors the change into the roster.

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

Asserts the window lifecycle and single-instance rule, the empty-roster-and-no-session path, filtering (a regex-looking string, and live search driven one keystroke at a time through the real `ValueChangingFcn`), the retired toggle, all three box-GUI states in the project summary, ticking plus a typed box reaching `CONFIG`, the session window being raised by a clean commit, the remembered project surviving a close, and `revealSubject` handling both a retired subject and an unknown name.

The toolbar is asserted as a whole rather than tool by tool: every tool must carry a 16×16 icon and a tooltip — a toolbar has no labels, so a tool with neither is unusable — its Enable must follow the ticks alongside the button and menu item, and the Retire tool must swap both icon *and* tooltip when the checked rows are already retired.

Protocol versions are asserted end to end against a real `epsych.Protocol.save`: the Version column carries the recorded version, the banner opens when the file is saved behind the window's back and closes once `updateProtocol` has run, and the column then shows the new version. The update and revert *commands* are engine-tested in `smoke_test_subject_roster` instead — both open a confirmation the operator has to answer, so what is checked here is that the window notices and stops saying so.

Project options are asserted the same way: the summary names the investigator and IACUC number, both links render as `uihyperlink`s carrying no `URL`, a linkless project collapses the panel to zero height, and an archived project hides, stays reachable by ID, and survives the toggle going off while it is selected. The dialog itself is driven for real — the Edit button is pressed and the modal window inspected and cancelled from a timer, since `projectDialog_` blocks in `uiwait`. That timer repeats rather than firing once (the figure is findable by name while its controls are still being laid out, so the probe waits for Cancel to exist), and its `StopFcn` deletes whatever is left standing, so a probe that simply missed the window fails the test instead of hanging it.

See also: [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md), [`gui.BehaviorGUI`](gui_BehaviorGUI.md), [RunExpt GUI Overview](../overviews/RunExpt_GUI_Overview.md)
