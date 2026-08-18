# `epsych.SubjectRoster`

The persistent, shareable record of which animals exist, which study each one belongs to, and what it last ran. It is the headless engine behind [`gui.SubjectManager`](../gui/gui_SubjectManager.md): every query, every mutation, and the batch commit into `epsych.RunExpt.CONFIG` live here, so all of it is usable from a script and testable with no figure open.

```matlab
R = epsych.SubjectRoster;                       % the configured roster
p = R.addProject('Tone Detection', DefaultProtocol='D:\protocols\tone.eprot', ...
                                   BehaviorGUI='cl_ToneDetect_BehaviorGUI');
s = R.addSubject(struct('Name','M001','Sex','Male','Species','Gerbil'));
R.assign(s, p);

ids = {R.subjectsInProject(p).SubjectID};
R.assignToSession(runExpt, ids, ProjectID=p);   % boxes, protocols, behavior GUI applied
```

> **Status: under development.** Run `tmp/smoke_test_subject_roster.m` after any change.

> **There is no default file location.** `epsych.SubjectRoster` with no argument opens whatever this workstation has been pointed at, and opens **unbound** — empty and refusing to write — until an operator names one. See [Where the file lives](#where-the-file-lives--there-is-no-default).

---

## Why a join table

Membership is many-to-many — one animal can be in several studies — **and** it carries its own attributes: an animal finished in one study may still be running in another, with a different protocol in each. Nesting subjects under projects would duplicate any two-project subject and leave no authoritative copy, so the model is three flat arrays plus a join table.

| Array | Holds |
|---|---|
| `Subjects` | `SubjectID`, `Name`, `Sex`, `Species`, `Weight`, `Notes`, `NameHistory`, `Retired`, `Created`, `Modified` |
| `Projects` | `ProjectID`, `Name`, `Notes`, `Investigator`, `IACUCProtocol`, `DefaultProtocol`, `DefaultDataPath`, `SavingFcn`, `TimerStartFcn`, `TimerRunTimeFcn`, `TimerStopFcn`, `TimerErrorFcn`, `TimerPeriod`, `VideoRootDir`, `IntanRootDir`, `IntanSettingsFile`, `BehaviorGUI`, `Links`, `Archived`, `Created`, `Modified` |
| `Memberships` | `SubjectID`, `ProjectID`, `Active`, `LastProtocol`, `LastProtocolVersion`, `LastBoxID`, `ProtocolHistory`, the session settings stamped from the project's template (`DefaultDataPath`, `SavingFcn`, `BehaviorGUI`, `TimerPeriod`, `TimerStartFcn`, `TimerRunTimeFcn`, `TimerStopFcn`, `TimerErrorFcn`, `VideoRootDir`, `IntanRootDir`, `IntanSettingsFile` — see `SESSION_FIELDS`), `Added`, `Modified` |

`Active` is the per-project archive flag. `setActive(s, p, false)` retires a subject from **that project only**; it stays active everywhere else and keeps its protocol memory, which is what makes retiring reversible in one click and `deleteSubject` a last resort.

### There is no `BoxID` on a roster record

A box belongs to a session, not to an animal. Roster records have no `BoxID` field at all; an `epsych.Subject` is *materialized* at the moment of assignment:

```matlab
S = R.toSubject(subjectId, BoxID=4);   % an epsych.DefaultSubject
```

This is why `epsych.Subject` needs no subclassing and its `isValid()` contract (`BoxID >= 1`) is never violated by a roster record. `fromSubject` is the reverse, and drops the box.

### The membership carries the session settings; the project is its template

What a paradigm decides rides the **subject's membership**, not a per-rig preference: *selecting a subject selects all config required to run it*. These settings used to be RunExpt's **Customize** dialog, which meant every rig running two paradigms had to be re-pointed by hand between sessions, and a rig set up for one study silently ran the other with the wrong saving function, timer period, or recording root. What is left in Customize is what genuinely describes the machine: the log path and viewer, the roster file, the add-subject dialog, and the rig's default data path.

The project's Session Defaults are a **template**: `assign` stamps them verbatim onto the membership when a subject joins, and later project edits do **not** reach existing members. `reapplyTemplate` is the deliberate push (the manager's *Re-apply Project Template to Checked*), and `updateMembership` is how one subject deliberately diverges (the manager's *Session Settings...*). `copyProject`'s member copies are stamped from the **new** project's template, never from the source memberships, so a study's next phase starts on agreed settings.

`assignToSession` resolves each planned subject's membership **before any side effect** and refuses the whole batch when the chosen memberships disagree on a session-level field (`report.aborted`, with a machine-readable `report.mismatch` naming the field, the values, and who carries which). The manager's **Settings** column shows `template` or `edited` per row, so the refusal is predictable before the click. Once the batch agrees, any one membership speaks for all, and its values land on the session:

| Membership field | Applied to | Notes |
|---|---|---|
| `DefaultDataPath` | `RunExpt.DefaultDataPath` | The root every subject folder is created under. |
| `SavingFcn` | `RunExpt.FUNCS.SavingFcn` | `SaveFcn(RUNTIME)`; logged at level 0 if it is not on the path. |
| `TimerStartFcn` … `TimerErrorFcn` | `RunExpt.FUNCS.TIMERfcn.*` | The trial loop itself; `''` runs the `ep_TimerFcn_*` built-ins. A custom loop travels with the study. |
| `TimerPeriod` | `RunExpt.FUNCS.TimerPeriod` | `NaN` inherits the built-in 0.01 s. Read by `CreateTimer` at run start, so applying it here is enough. |
| `VideoRootDir` | `RunExpt.PATHS.VideoRootDir` | Empty still falls back to the data path. |
| `IntanRootDir` | `RunExpt.PATHS.IntanRootDir` | Logged at level 0 if it contains spaces, which RHX cannot express. |
| `IntanSettingsFile` | `RunExpt.PATHS.IntanSettingsFile` | A protocol that names its own settings file still wins over this. |
| `BehaviorGUI` | `RunExpt.FUNCS.BehaviorGUI` | Three states; see below. |

Two rules hold across all of them. **Empty is "inherit the built-in default"** (`ep_SaveDataFcn`, `ep_GenericGUI`, the `ep_TimerFcn_*` callbacks, 0.01 s) — the only meaning a roster written before these fields existed can have, and deterministic for the first time: there is no rig-local preference layer underneath anymore. And **nothing is written back to the machine's preferences**: a session follows the study it is running, and the next session starts from the built-ins again. `RunExpt.PATHS` exists for exactly that reason — the recording roots used to be read from `getpref` at the moment of use, which left a study no way to override them for one session only.

[`gui.SubjectManager`](../gui/gui_SubjectManager.md#the-project-dialog)'s dialogs fill every one of these in before the operator sees it and refuse blanks on OK, so a template or membership written there is never partly empty; the all-inherit state can arise only from scripts and rosters written before the fields existed.

#### The behavior GUI, in three states

Committing a subject is what puts its membership's GUI on the session's `FUNCS.BehaviorGUI`. Three states, because "inherit" and "launch nothing" are different answers:

| `BehaviorGUI` | Effect on `FUNCS.BehaviorGUI` |
|---|---|
| `''` | Untouched — the session keeps whatever it has (`ep_GenericGUI` unless a script says otherwise). The only meaning an existing roster could have, so old files behave exactly as before. |
| `epsych.SubjectRoster.BEHAVIORGUI_NONE` (`'none'`) | Cleared: the session runs with no behavior GUI. |
| anything else | Set to that name; `epsych.RunExpt.PsychTimerStart` will `feval` it with `RUNTIME`. |

A name that is not on the path is still applied — it is the operator's stated intent, and a lab that adds its GUI to the path later would be badly served by having it silently dropped — but it is logged at level 0 when committed, rather than surfacing as a failure at run start.

`epsych.RunExpt` launches exactly one behavior GUI per session (see `plans/multi-subject-support.md`); the mismatch refusal is what keeps a multi-subject commit from carrying two answers to that question.

### The study's own bookkeeping

`Investigator` and `IACUCProtocol` are free text the roster only records — nothing validates or enforces them. They are here because they are the two facts a lab is asked for about a study and has nowhere else to keep next to the animals themselves.

`Archived` retires a **project** the way `Active` retires a membership: the record, its subjects, and their protocol memory all stay: only [`gui.SubjectManager`](../gui/gui_SubjectManager.md)'s project list hides it, and the project currently selected is never hidden. Every roster method still resolves an archived project by ID or name, so a script and `assignToSession` are unaffected.

### Copying a project

A study's second phase, a replication, a sister experiment on the next rig: each wants the template fields above set exactly as they are on a project that already runs. `copyProject` mints a new project carrying all of them, and takes overrides in the same call so nothing has to be written twice.

```matlab
p2 = R.copyProject('Tone Detection', 'Tone Detection Phase 2', ...
        IncludeSubjects = true, DefaultProtocol = phase2File);
```

Every override option deliberately has **no default**, so "not stated" and "stated as empty" stay distinguishable: only the former follows the source. That is what lets [`gui.SubjectManager`](../gui/gui_SubjectManager.md) put the whole copy in front of the operator for editing and then commit their answer, blank fields and all.

`Archived` is the one field a copy does **not** inherit. A project is copied to start work; a copy that opened hidden would look like nothing happened. Pass `Archived = true` to clone an archived project as archived.

**Subjects are a separate question, and neither answer is assumed.** The two reasons to copy pull opposite ways — a new cohort wants the settings and none of the animals, a second phase wants both — so `IncludeSubjects` is off by default.

| Option | Default | Effect |
|---|---|---|
| `IncludeSubjects` | `false` | Enroll the source's members in the copy. They stay in the source too: membership is many-to-many, so a subject is simply in both. |
| `IncludeRetired` | `false` | Bring retired members as well, still retired. Off because a finished animal has no place in a study that has not started. |
| `CopyProtocolMemory` | `true` | Copied memberships keep the protocol, version, and box they last used in the source. `false` gives the same cohort with no memory, so each member falls back to the copy's `DefaultProtocol`. |

`ProtocolHistory` is never copied, even with `CopyProtocolMemory` on. The history answers "put this membership back the way it was", and a membership created a moment ago has no way it was — the pointer it starts on is a starting point, not a change to undo.

The project is created first and its members enrolled second, so a copy interrupted between the two leaves an **empty project** rather than rolling back. That is the recoverable half: the settings are the part that cannot be reconstructed by clicking, and "Add to Project" finishes the job.

### Links, and why the scheme is checked

`Links` is a `(1,:)` struct array of `Label` and `URL`, for the addresses a study is actually logged at — the electronic notebook, the shared sheet, the issue tracker, the analysis folder on the NAS.

```matlab
L = [epsych.SubjectRoster.makeLink('Lab notebook','https://elog.lab.edu/gap'), ...
     epsych.SubjectRoster.makeLink('\\nas\gapdetect\logs')];

P = struct();      % assign the field; struct('Links', L) would build one
P.Links = L;       % project struct per link instead of one holding them all
R.updateProject(p, P);
```

`epsych.SubjectRoster.isSafeUrl` is the gate, and it exists because **a roster is a shared file**: an address stored in it is untrusted input that some other person typed, and `matlab:` or `javascript:` would make an `.esub` file executable by every rig that clicks it. Only `http`, `https`, `mailto`, and `file` are accepted; everything else is refused with the reason.

It also normalizes, because it is checking what an operator pastes rather than what a program builds:

| Typed | Stored |
|---|---|
| `docs.google.com/spreadsheets/d/1` | `https://docs.google.com/spreadsheets/d/1` |
| `C:\lab\My Logs\notes.html` | `file:///C:/lab/My%20Logs/notes.html` |
| `\\nas\gap\logs` | `file://nas/gap/logs` |
| `matlab:!del /q c:\` | refused |

A blank label is filled from the host (`docs.google.com`), the mail address, or the file name — a link with no visible text would be unclickable.

Validation is **on the way in only**: `addProject` and `updateProject` refuse an unsafe address before the file is touched, but `reload` does not, because one operator's typo must not make the shared roster unreadable for the lab. `epsych.SubjectRoster.openLink` re-checks at the moment of the click, which is the backstop for a file written by an older build or edited by hand, and is also what routes a `file:` URL naming a folder to the platform's file manager rather than to a browser.

---

## File format

`-mat`, extension **`.esub`**, holding `formatVersion`, `subjects`, `projects`, `memberships`, `meta`.

MAT rather than JSON for one decisive reason: `jsonencode(NaN)` emits `null` and `jsondecode` returns `[]`, which would silently destroy `Weight = NaN` — the documented "not measured" value. `datetime` also round-trips natively, and `.eprot`/`.epj` are `-mat` already. For a readable copy use `File > Export CSV...` (`exportTable` + `writetable`); the CSV is a one-way snapshot, never re-imported, because a round trip through a spreadsheet mangles both `NaN` and datetimes.

`formatVersion` is a gate, not a label: a file written by a newer build opens **read-only**, so this build cannot save it back having dropped fields it does not know about.

---

## Identity and the rename rule

Records are keyed by a minted `SubjectID` (`S_20260814T143012_7f3a9c` — timestamp plus six hex characters, so it sorts chronologically and stays readable in a debug dump), never by `Name`. Two projects may legitimately reuse a short animal code.

**Renaming is refused once experiment data exists.** `Name` is a filesystem path component — `ExptDispatch` saves into `<DataPath>/<Name>/` and the crash journal embeds it in filenames — and nothing downstream consults `NameHistory`. Before a rename, `updateSubject` looks for `<root>/<oldName>` under both the session data root (`RunExpt`/`DataPath`) and every `DefaultDataPath` of a project the subject belongs to; finding one raises `epsych:SubjectRoster:RenameBlocked` naming the folder. Nothing on disk is ever moved: reconciling experiment data is out of this class's remit.

A typo discovered after the first session is therefore not correctable here. That is a deliberate trade — the alternative silently orphans data.

---

## Where the file lives — there is no default

**EPsych does not choose a roster location, and there is no fallback.** `configuredFile` returns `''` until an operator answers, `isConfigured` reports whether they have, and a roster constructed with no path is **unbound**: it reads as empty, `IsBound` is false, `IsWritable` is false, and `mutate_` throws `epsych:SubjectRoster:NoFile` rather than inventing somewhere to write.

Older builds fell back to `<prefdir>/epsych/subjects.esub`. That was the wrong place for the only copy of a lab's animal records on two counts: `prefdir` is **release-specific**, so upgrading MATLAB silently produced an empty roster, and nothing about it is anywhere an operator would think to look, back up, or point a second rig at. The choice between *one shared file on a network drive* and *a private file per workstation* is a decision only the lab can make, so it is asked rather than guessed.

### Who asks, and when

[`gui.SubjectManager`](../gui/gui_SubjectManager.md) opens fine with no file chosen — browsing is harmless, so it explains itself and waits. The demand comes from `ensureRoster_` at the **first action that would write something**: New Project or New Subject. That prompt is a loop with two exits, choosing a file or closing the window; "carry on without one" is not offered, because it would mean filling in a record with nowhere to save it.

A file can also be named ahead of time, from `Subjects > Roster File...` or the Paths tab of Customize. The file itself need not exist: naming a new shared roster before there is anything to put in it is the normal way to start one.

### What `setConfiguredFile` checks

Validation happens when the file is chosen, not at the first save, so an unusable path is reported while the file dialog is still in mind:

| Check | Behaviour |
|---|---|
| Relative path | Resolved against the current folder and stored absolute — the preference outlives whatever folder MATLAB was in. |
| Path names a folder | `epsych:SubjectRoster:PathIsFolder`. `movefile` onto a directory *succeeds* by moving the file inside it. |
| No extension | `.esub` is appended. |
| Parent folder missing | Created now, or `epsych:SubjectRoster:FolderNotWritable`. |
| `''` | Clears the preference. The rig then has **no** roster, not a private one. |

---

## Sharing one file between rigs

Point every rig at the same file (`Subjects > Roster File...`, or the Paths tab of Customize) and they share one roster.

Every mutation runs through `mutate_`, which is the whole of the concurrency story:

1. take the advisory lock,
2. **re-read the file if another process changed it** (`dir` mtime + size, the same key `epsych.Runtime.phaseCache` uses),
3. apply the change,
4. write atomically — save to a temp file *in the same directory*, then `movefile` over the target.

Reload-before-write is the real protection, and it works because writes are record-scoped: rig A adding X while rig B adds Y cannot lose either, since B's write already contains X. The `<file>.lock` sidecar (30 s stale breaker) only narrows the remaining window — MATLAB has no atomic create-exclusive open, so it cannot close it.

The one genuinely lossy case is two rigs editing the **same record** between reloads. Last writer wins — a rig must never be stuck — but the loss is logged at level 0 naming both timestamps.

### Failure modes, and what each does

| Situation | Behaviour |
|---|---|
| No file chosen | Empty roster, `IsBound` false, **not** writable, and `LoadError` stays empty — nothing failed, the question has simply not been answered. Mutations throw `epsych:SubjectRoster:NoFile`. |
| File does not exist | Empty roster, writable. It is created on the first mutation, so merely opening the manager leaves nothing on disk. |
| File's **folder** does not exist | The same at this level — but the manager marks it `(folder not found)` and refuses to write, because `saveAtomic_` creates a missing folder and would otherwise resurrect a dead path and save into it. See [`gui.SubjectManager`](../gui/gui_SubjectManager.md#layout). |
| File unparseable | Empty roster, **not** writable, `LoadError` set. A corrupt file is never overwritten with whatever little was recovered. |
| Path names a folder | Rejected on read and on write. `movefile` onto a directory *succeeds* by moving the file inside it, so this would otherwise look like a working save that stored nothing. |
| `formatVersion` too new | Loaded read-only with an explanation in `LoadError`. |
| Share unreachable mid-session | `IsWritable` latches false, mutations refuse and log, reads serve the last in-memory copy. A file-server hiccup never stops a loaded session from running. |

There is no polling timer and no file watcher. The roster is re-read when the window opens, on Refresh/F5, and inside every mutation; the manager shows "Last read HH:MM:SS" so staleness is visible rather than guessed at.

---

## Protocol memory

`lastProtocol(subject, project)` resolves most-specific-first:

```
membership.LastProtocol  →  project.DefaultProtocol  →  ''  (the caller browses)
```

Pass an empty `projectId` to search across every project the subject belongs to, most recently modified first — that is what the All Projects view uses, where there is no project context. `rememberProtocol` is called by `assignToSession` after a successful commit, so next session proposes what actually ran.

---

## Protocol versions

`epsych.Protocol.save` overwrites an `.eprot` in place and bumps `meta.protocolVersion` (`vN.YYMMDD`). The file now archives the version it replaces inside itself (see [version history](epsych_Protocol.md#4-version-history)) — but a *subject* carries no version at all, so **the roster is still the only thing that can notice a protocol was edited since a subject last ran it**. `rememberProtocol` therefore records the version alongside the path, in `LastProtocolVersion`.

### Checking

`protocolStatus(subjectIds, projectId)` answers it for one subject or a whole project, from a script or from the manager's table. Two different things can make an answer *no*, and they are reported separately because they call for different fixes:

| `Status` | Meaning |
|---|---|
| `current` | Recorded version matches the file, and the file is the project's default |
| `outdated` | The file has been saved since — `LatestVersion` is ahead of `Version` |
| `differs` | The subject is on a **different file** from the project's default |
| `unknown` | Nothing recorded yet; the subject has never been committed to a session |
| `missing` | The recorded `.eprot` is no longer on disk |
| `none` | Nothing remembered and the project has no default |

Reading the version is a cheap peek (`epsych.Protocol.versionOnDisk`) at one metadata field, not an `epsych.Protocol.load` — the full object graph would be far too expensive for a question asked per subject on every repaint. Results are cached per distinct file within one call, so sixteen animals on one protocol read that file once. `epsych.Protocol.versionNumber` supplies the comparable integer `N`; an unparseable version is `NaN`, which compares false against everything, so **an unknown version is never reported as outdated**.

### Updating

`updateProtocol(subjectIds, projectId)` records the version each subject's file holds right now. `UseProjectDefault = true` also moves them onto the project's default file, and `Protocol = pfn` onto a named one.

Nothing about a protocol's *content* changes, and nothing needs to: a session loads the `.eprot` at commit time, so the newest saved version runs regardless. What updating changes is which version each subject is *expected* to be on — which is what turns the check green, and what makes the next unexpected edit visible.

### Reverting

Each change pushes the outgoing file and version onto the membership's `ProtocolHistory` (most recent first, de-duplicated, capped at `PROTOCOL_HISTORY_LIMIT`). `revertProtocol(subject, project, Index = k)` restores one, pushing the protocol being left in its place — so reverting is itself undoable, and the same call run twice returns where it started.

Whether the *content* comes back too depends on where the recorded version can still be found, which the report names in `Source`:

| `Source` | Situation | `Recoverable` | Result |
|---|---|---|---|
| `disk` | The entry names an `.eprot` that still holds its recorded version | `true` | Exact — re-pointing is enough |
| `archive` | The file was saved over, but the version sits in the file's [embedded archive](epsych_Protocol.md#4-version-history) | `true` | Exact **when asked**: `RestoreContent = true` rewrites the file back via `epsych.Protocol.restoreVersion(..., Mode='exact')` before touching the roster |
| `none` | The file was last saved by an EPsych release without version archiving, or is missing | `false` | Pointer and version restored; the report says the content is not recoverable |

`RestoreContent` defaults to **false** because rewriting a protocol file is more than roster bookkeeping: the file may be shared, and every subject on it gets the restored content. The report's `OthersOnFile` lists the other memberships recorded on the same file at a different version so a caller — the manager's dialog does exactly this — can warn before opting in. A content restore archives what it replaces, so it is itself undoable, and `ContentRestored` in the report says whether it happened. `Mode='exact'` is what the roster uses because `LastProtocolVersion` must match the file again afterward; the counter rewinding is the accepted cost, visible to other subjects as `Status = 'current'`-vs-file drift the check reports honestly.

`protocolHistory(subject, project)` returns the list with `OnDiskVersion`, `Source`, and `Recoverable` already resolved, which is what the manager's revert dialog shows.

### Format compatibility

`LastProtocolVersion`, `ProtocolHistory`, the four project `Timer*Fcn` template fields, and the membership `SESSION_FIELDS` are all **additive**, so `FORMAT_VERSION` stays at 1: an older file's missing fields normalize to "inherit the built-in default", which is exactly what that file meant. `normalize_` fills them in from the template when an older file is read, and a rig on an older build that writes the file back drops them — losing a version memory that the next commit re-records, rather than losing data. Bumping the format instead would open every new file **read-only** on every rig that had not been updated, which for a shared network roster is much the worse failure.

The same reasoning covers `Investigator`, `IACUCProtocol`, `Links`, and `Archived`. This is why every default in `blankProject_` has to mean *what an older file implicitly meant*: no investigator, no links, and not archived are all correct readings of a roster written before those fields existed — exactly as `BehaviorGUI = ''` means "inherit". A default that changed behaviour would silently rewrite the past on first read.

`normalize_` shapes the outer record only, so `reload` gives a project's nested `Links` array its own pass. It runs **without** validation there, deliberately: see [Links](#links-and-why-the-scheme-is-checked).

---

## Committing to a session

`assignToSession(runExpt, subjectIds, ...)` resolves a free box and a protocol for each subject, validates **everything** up front, then writes into `CONFIG` through `epsych.RunExpt.appendSubjectToConfig_` (which owns the slot-1-reuse rule shared with `AddSubject`), and finally applies the project's [session settings](#a-project-owns-the-session-settings).

It is all-or-nothing where partial success would be worse than none:

| Outcome | Trigger |
|---|---|
| **Abort**, nothing committed | a named protocol is missing or fails to load; more than 16 boxes needed; a session is running; no session open |
| **Skip** that row, commit the rest | subject not in the roster; already in the session; its explicit box is taken; no protocol resolvable at all |

The distinction: having *no* protocol means the subject simply is not ready, while a protocol that was named but cannot be used means the operator's intent cannot be honoured.

The returned report has `ok`, `aborted`, `added` (Name/BoxID/Protocol), `skipped` (Name/reason), `removed` (names displaced by a replacement) and a one-line `message`.

### `ReplaceExisting`

`ReplaceExisting=true` makes the batch the session's **whole** subject list: whoever is in `CONFIG` is cleared as the new rows land. This is what [`gui.SubjectManager`](../gui/gui_SubjectManager.md#add-checked-to-session)'s **Add Checked to Session** button asks for — what an operator ticks there is their answer to "who is running", and yesterday's animal left behind in a box would go on dispatching trials.

Three consequences:

- The clear happens **after** every check that can refuse the batch, and after every protocol has loaded. An aborted batch leaves the session exactly as it was, and `removed` stays empty.
- Boxes and names held by the outgoing subjects are **not** taken, so the same animal can be re-added in the same box. Without that, a subject already in the session would skip as "already in the session" and the commit would be empty.
- Nothing is removed when the batch resolves to no usable subject at all: an operator who ticks only unready animals keeps the list they had.

Default `false` — appending is what a script asking for one more subject means.

> ⚠️ Committing more than one subject logs a level-1 note. `ExptDispatch` takes hardware interfaces from `CONFIG(1).PROTOCOL` only, so subjects 2+ can dispatch into orphan objects — see `plans/multi-subject-support.md`. The roster does not cause this, but it makes multi-subject sessions a two-click operation.

---

## Preferences

Group **`ep_RunExpt_Subjects`**:

| Key | Meaning |
|---|---|
| `RosterFile` | Full path, always absolute. **Unset means no roster**, not a default one — Subjects & Projects asks before it saves anything. |
| `LastProject` | Struct **keyed by roster path** → project ID, so re-pointing the file cannot restore a project belonging to a different roster. |
| `ShowRetired` | The manager's retired toggle. |
| `ShowArchived` | The manager's archived-projects toggle. |

---

## Testing

```
matlab -batch "cd('tmp'); smoke_test_subject_roster"
```

Covers the file round trip (including that a `NaN` weight stays `NaN`), many-to-many membership, per-project retire, the protocol fallback chain, the rename block, two rosters writing one file concurrently, an unwritable target leaving the good file byte-identical, the `BoxID` seam, the batch commit passing self-test group D, both all-or-nothing refusals, and all three `BehaviorGUI` states reaching `FUNCS.BehaviorGUI` (applied via the membership, cleared, inherited).

Protocol versions get their own section, driven by real `epsych.Protocol.save` calls rather than hand-written version strings: a fresh subject reads `unknown`, a recorded one `current`, one whose file was saved again `outdated`; `updateProtocol` clears it and the record survives a reload; a superseded same-file entry reports `Recoverable` with `Source = 'archive'` (the save archived it inside the file), a revert between two distinct files is exact from `disk` and leaves the restored entry out of the history rather than in it twice, a default revert never rewrites the protocol file, and `RestoreContent = true` rewrites it back to the recorded version — undoably, with the replaced content archived in turn. The file-side mechanics have their own standing proof in `tmp/smoke_test_protocol_versioning.m`.

Copying gets its own section: a settings-only copy is compared field by field against its source off disk (and asserted **not** archived), a copy with subjects takes the active members while leaving the retired one and the source's own membership alone, an override beats the inherited value, `IncludeRetired` and `CopyProtocolMemory = false` each do exactly one thing, and a copy is refused both an existing name and a source that does not exist.

Project options get two more: every `isSafeUrl` verdict and normalization, links surviving a reload, a `matlab:` address refused by `updateProject` leaving the stored links untouched — and, separately, a roster **written without the new fields at all**, synthesized by stripping them from a real `.esub`. That one asserts the file still opens writable, still reports every project, and defaults each new field to what the older file meant. It is the assertion that fails if a default is ever chosen for convenience rather than for backward compatibility.

See also: [`gui.SubjectManager`](../gui/gui_SubjectManager.md), [`epsych.Subject`](../overviews/Class_Map.md), `plans/multi-subject-support.md`
