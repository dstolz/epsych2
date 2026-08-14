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

**Box IDs in that dialog:** all 16 boxes are always listed and box 1 is always the default. Boxes the open session already holds are labelled `(in use)` rather than removed — the dialog used to hide them, which made box 1 disappear the moment a second subject was added. Picking one anyway is the operator's call; the row is then reported as skipped at commit ("box 1 is already taken") instead of being silently prevented.

---

## Layout

| Region | Widget | Why |
|---|---|---|
| Projects (left) | `uilistbox` | Projects are a flat, single-selection set; a listbox gives arrow-key and type-ahead navigation for free. A tree would show a two-project subject twice with ambiguous checkbox state. |
| Subjects (right) | `uitable` | Each row needs its own box assignment *before* it is committed. A checkbox tree has no columns; a listbox would force a second modal — exactly the step this collapses. |

`‹All Subjects›` is pinned at the top of the project list. It is not a project: it shows every subject regardless of membership, and it is both the empty state for a fresh roster and the way to find a subject whose project you have forgotten.

Below the project list, a read-only summary shows the selected project's notes, default protocol, and data path — so you can see what will be applied without opening the edit dialog.

### Columns

| Column | Editable | Notes |
|---|---|---|
| ✓ | yes | The multi-select |
| Subject | no | |
| Box | **yes** | Blank means "assign the lowest free one". Values outside 1–16 are rejected and the old value restored. |
| Protocol | no | See below |
| Species, Sex, Weight, Last Run | no | So two similarly-named animals are distinguishable |
| Status | no | Active / Retired |

**Why Protocol is read-only in the grid:** `uitable`'s `ColumnFormat` is per-column, not per-row, so a dropdown there would share one item list across every row and could not offer each subject its own remembered protocol. Instead, right-click gives **Set Protocol for This Row...** and **Set Protocol for Checked Rows...**, which covers both the common case (one protocol for the whole project) and the exception.

---

## Add Checked to Session

The button collects what you ticked and typed; every decision belongs to [`epsych.SubjectRoster.assignToSession`](../epsych/epsych_SubjectRoster.md). Boxes and protocols are resolved, then **everything is validated before `CONFIG` is touched** — a protocol that fails to load halfway through must never leave a half-populated session.

- Refused outright while a session is running, or with no session window open (the button is disabled and says why).
- A missing protocol, or needing more than 16 boxes, **aborts the whole batch** and changes nothing.
- A subject already in the session, or with no protocol resolvable at all, is skipped and reported; the rest still go in.
- The window stays open and the committed rows untick, so adding six animals across two projects does not mean reopening it.

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
- the *Show retired* toggle;
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

Asserts the window lifecycle and single-instance rule, the empty-roster-and-no-session path, filtering (a regex-looking string, and live search driven one keystroke at a time through the real `ValueChangingFcn`), the retired toggle, ticking plus a typed box reaching `CONFIG`, the session window being raised by a clean commit, the remembered project surviving a close, and `revealSubject` handling both a retired subject and an unknown name.

See also: [`epsych.SubjectRoster`](../epsych/epsych_SubjectRoster.md), [`gui.BoxGUI`](gui_BoxGUI.md), [RunExpt GUI Overview](../overviews/RunExpt_GUI_Overview.md)
