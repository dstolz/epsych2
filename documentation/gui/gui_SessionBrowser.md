# `gui.SessionBrowser`

Every saved session of one subject in a sortable table, with a button that
reopens the selected one in its behavior GUI. It answers "what has this animal
run, and what did Tuesday look like?" without a file browser.

Opened from **Subjects & Projects**: right-click a subject, **View Data
Files...**. Or directly:

```matlab
gui.SessionBrowser("M001")                                   % the rig's data path only
gui.SessionBrowser("M001", Roster = epsych.SubjectRoster)    % plus every project's
```

> Exercised headlessly by `tmp/smoke_test_session_browser.m`, which builds a
> temporary data tree holding every file shape below and drives the window,
> the running-session gate against a real `epsych.RunExpt`, the Subjects &
> Projects menu item, and the hand-off to `epsych.ReviewSession`. Run it after
> any change here or in `epsych.SessionFiles`.

---

## Only between sessions

The browser is refused while `epsych.RunExpt` is **RUNNING** or finishing
(**POSTRUN**), and an open one follows the session: when a run starts, Review,
Rescan and the recovery checkbox grey out and a banner says why; when it stops,
they come back.

The reason is the trial loop. Describing a subject's files loads each one on
the MATLAB thread, and the loop is a timer on that same thread — a scan during
a session holds up trial dispatch for as long as it takes. RunExpt's own
**Review Saved Session...** (Ctrl+K) stays available during a run on purpose:
that is one file, chosen deliberately, not a folder read end to end.

The gate is enforced in three places, each for a reason:

| Where | Why |
|---|---|
| Subjects & Projects' menu item | Greyed with "(not while a session runs)" when the menu **opens** — the manager is never told when a session starts, so a state read at its last refresh could be minutes stale. |
| The constructor | Throws `gui:SessionBrowser:SessionRunning`, so a script cannot open one mid-run either. |
| `review` and `rescan` themselves | A stale button or a script fails closed rather than trusting `Enable`. |

An open window hears about state changes because `epsych.RunExpt.STATE` is
`SetObservable`. `gui.SessionBrowser.sessionIsRunning(rx)` is the one test all
three use; passed `[]` it asks whichever session window is open, so a caller
bound to no session cannot mistake "not told" for "stopped".

---

## The table

| Column | What it shows |
|---|---|
| Date | Session start, with the weekday |
| Start | Time of day it started |
| Duration | Start to the last completed trial |
| Trials | Completed trials recorded |
| Box | Box it ran in (blank for files saved before 2026-08, which do not say) |
| Paradigm | The protocol's trial function |
| Video | A recording made alongside it was found |
| Source | `Saved`, or `Recovery` for a crash-recovery copy; `(preview)` for a Preview run |
| Review | What opening it gives: **Full** (the paradigm's GUI with its controls), **Data only** (no protocol in the file — the data displays without controls), **No trials**, or **Unreadable** |
| File | File name |

Newest first. Click any header to sort by it. Date and Trials are typed
columns; Start, Duration and Box are **fixed-width text** — a typed column shows
an unknown value as `NaN`, which every legacy file would put in its Box cell,
and fixed width keeps a text sort the numeric one (`" 2"` before `"10"`).

Rows that cannot be reviewed are **greyed, not hidden** — an empty or damaged
file is still part of the animal's history. Recovery rows are *italic*.

The pane under the table holds what the table has no room for: the full path,
start and end, box, paradigm, protocol version, the EPsych version it ran
under, the video's path, what a review will show, and the operator's session
notes.

Every row index the class takes or reports (`Sessions`, `review(row)`,
`Selection`) is the **data** row, never the sorted display row, so sorting can
never make an action land on the wrong file.

---

## Reviewing

**Review Session**, Enter, a double-click, or the right-click menu hands the
file to `epsych.ReviewSession` — the same door RunExpt's Review Saved
Session... opens, so a session reviewed from here looks exactly as it does
there. The browser stays open, so several sessions can be compared side by
side.

The right-click menu also has **Copy File Path** (for `load` in an analysis
script) and **Show in Folder**. Right-clicking a row selects it first, so the
menu acts on the row under the pointer.

---

## Where it looks

`epsych.SessionFiles.locations` gathers every data path the subject could
have been saved under, since nothing in a session records which one it used:
the rig's `RunExpt/DataPath` preference, the session window's current data
path, and the `DefaultDataPath` of every project the subject belongs to and of
every one of its memberships. Under each it looks in `<root>/<Name>/` for the
subject's current name **and every former one** (`NameHistory`).

The status line names the folders searched; its tooltip lists them all, plus
any root that **could not be reached** (an unmounted share, a moved folder),
which turns the line amber. Otherwise a missing share would look exactly like
a subject with no sessions.

**Include crash-recovery files** adds the `RUNTIME_DATA_<Name>_Box_NN_*.mat`
copies every session writes as it runs. Off by default, since a session that
saved normally has one of those too and they would double the list — but they
are the only record of a Preview run, a crash, or a save that was declined.
Remembered per rig.

A session saved somewhere none of these point at can still be opened with
Review Saved Session... in the session window; the empty state says so.

---

## Keyboard

| Key | Action |
|---|---|
| Enter | Review the selected session |
| F5 | Rescan |
| Esc | Close |

---

## What is remembered

Window position (`epsych2_gui_SessionBrowser`) and the recovery checkbox
(`ep_RunExpt_Subjects/SessionBrowserRecovery`). One window per subject:
asking again for the same animal replaces it, which also picks up a roster
edited since.

---

## See also

- [`epsych.SessionFiles`](../epsych/epsych_SessionFiles.md) — the headless scan behind this window
- [`epsych.ReviewSession`](../epsych/epsych_ReviewSession.md) — what Review opens
- [`gui.SubjectManager`](gui_SubjectManager.md) — where the window is opened from
