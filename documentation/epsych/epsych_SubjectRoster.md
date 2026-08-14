# `epsych.SubjectRoster`

The persistent, shareable record of which animals exist, which study each one belongs to, and what it last ran. It is the headless engine behind [`gui.SubjectManager`](../gui/gui_SubjectManager.md): every query, every mutation, and the batch commit into `epsych.RunExpt.CONFIG` live here, so all of it is usable from a script and testable with no figure open.

```matlab
R = epsych.SubjectRoster;                       % the configured roster
p = R.addProject('Tone Detection', DefaultProtocol='D:\protocols\tone.eprot');
s = R.addSubject(struct('Name','M001','Sex','Male','Species','Gerbil'));
R.assign(s, p);

ids = {R.subjectsInProject(p).SubjectID};
R.assignToSession(runExpt, ids, ProjectID=p);   % boxes and protocols resolved
```

> **Status: under development.** Run `tmp/smoke_test_subject_roster.m` after any change.

---

## Why a join table

Membership is many-to-many — one animal can be in several studies — **and** it carries its own attributes: an animal finished in one study may still be running in another, with a different protocol in each. Nesting subjects under projects would duplicate any two-project subject and leave no authoritative copy, so the model is three flat arrays plus a join table.

| Array | Holds |
|---|---|
| `Subjects` | `SubjectID`, `Name`, `Sex`, `Species`, `Weight`, `Notes`, `NameHistory`, `Retired`, `ImportedFrom`, `Created`, `Modified` |
| `Projects` | `ProjectID`, `Name`, `Notes`, `DefaultProtocol`, `DefaultDataPath`, `Created`, `Modified` |
| `Memberships` | `SubjectID`, `ProjectID`, `Active`, `LastProtocol`, `LastBoxID`, `Added`, `Modified` |

`Active` is the per-project archive flag. `setActive(s, p, false)` retires a subject from **that project only**; it stays active everywhere else and keeps its protocol memory, which is what makes retiring reversible in one click and `deleteSubject` a last resort.

### There is no `BoxID` on a roster record

A box belongs to a session, not to an animal. Roster records have no `BoxID` field at all; an `epsych.Subject` is *materialized* at the moment of assignment:

```matlab
S = R.toSubject(subjectId, BoxID=4);   % an epsych.DefaultSubject
```

This is why `epsych.Subject` needs no subclassing and its `isValid()` contract (`BoxID >= 1`) is never violated by a roster record. `fromSubject` is the reverse, and drops the box.

---

## File format

`-mat`, extension **`.esub`**, holding `formatVersion`, `subjects`, `projects`, `memberships`, `meta`.

MAT rather than JSON for one decisive reason: `jsonencode(NaN)` emits `null` and `jsondecode` returns `[]`, which would silently destroy `Weight = NaN` — the documented "not measured" value. `datetime` also round-trips natively, and `.ecfg`/`.eprot`/`.epj` are all `-mat` already. For a readable copy use `File > Export CSV...` (`exportTable` + `writetable`); the CSV is a one-way snapshot, never re-imported, because a round trip through a spreadsheet mangles both `NaN` and datetimes.

`formatVersion` is a gate, not a label: a file written by a newer build opens **read-only**, so this build cannot save it back having dropped fields it does not know about.

---

## Identity and the rename rule

Records are keyed by a minted `SubjectID` (`S_20260814T143012_7f3a9c` — timestamp plus six hex characters, so it sorts chronologically and stays readable in a debug dump), never by `Name`. Two projects may legitimately reuse a short animal code.

**Renaming is refused once experiment data exists.** `Name` is a filesystem path component — `ExptDispatch` saves into `<DataPath>/<Name>/` and the crash journal embeds it in filenames — and nothing downstream consults `NameHistory`. Before a rename, `updateSubject` looks for `<root>/<oldName>` under both the session data root (`RunExpt`/`DataPath`) and every `DefaultDataPath` of a project the subject belongs to; finding one raises `epsych:SubjectRoster:RenameBlocked` naming the folder. Nothing on disk is ever moved: reconciling experiment data is out of this class's remit.

A typo discovered after the first session is therefore not correctable here. That is a deliberate trade — the alternative silently orphans data.

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
| File does not exist | Empty roster, writable. It is created on the first mutation, so merely opening the manager leaves nothing on disk. |
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

Pass an empty `projectId` to search across every project the subject belongs to, most recently modified first — that is what the All Subjects view uses, where there is no project context. `rememberProtocol` is called by `assignToSession` after a successful commit, so next session proposes what actually ran.

---

## Committing to a session

`assignToSession(runExpt, subjectIds, ...)` resolves a free box and a protocol for each subject, validates **everything** up front, then writes into `CONFIG` through `epsych.RunExpt.appendSubjectToConfig_` (which owns the slot-1-reuse rule shared with `AddSubject`).

It is all-or-nothing where partial success would be worse than none:

| Outcome | Trigger |
|---|---|
| **Abort**, nothing committed | a named protocol is missing or fails to load; more than 16 boxes needed; a session is running; no session open |
| **Skip** that row, commit the rest | subject not in the roster; already in the session; its explicit box is taken; no protocol resolvable at all |

The distinction: having *no* protocol means the subject simply is not ready, while a protocol that was named but cannot be used means the operator's intent cannot be honoured.

The returned report has `ok`, `aborted`, `added` (Name/BoxID/Protocol), `skipped` (Name/reason) and a one-line `message`.

> ⚠️ Committing more than one subject logs a level-1 note. `ExptDispatch` takes hardware interfaces from `CONFIG(1).PROTOCOL` only, so subjects 2+ can dispatch into orphan objects — see `plans/multi-subject-support.md`. The roster does not cause this, but it makes multi-subject sessions a two-click operation.

---

## Importing from existing configs

`importFromConfig(configFile, ProjectID=..., Actions=...)` reads a `.ecfg` for subject structs and `protocol_fn` only — no `epsych.Protocol` is reconstructed, so it opens a colleague's config whose hardware backend this rig does not have.

Import is **offered, never automatic**, and never overwrites: an existing name defaults to `Link`, and the alternatives are `Import` and `Skip`, never merge-and-clobber. Provenance goes in `ImportedFrom`, never in operator `Notes`. `.ecfg` files are never rewritten.

`epsych.RunExpt.LoadConfig` only *mentions* unrostered subjects, in the status line's next-step half — a modal on every load would be intolerable on a rig that loads the same config every morning.

---

## Preferences

Group **`ep_RunExpt_Subjects`**:

| Key | Meaning |
|---|---|
| `RosterFile` | Full path. Unset ⇒ `<prefdir>/epsych/subjects.esub`, this user only. |
| `LastProject` | Struct **keyed by roster path** → project ID, so re-pointing the file cannot restore a project belonging to a different roster. |
| `ShowRetired` | The manager's retired toggle. |

---

## Testing

```
matlab -batch "cd('tmp'); smoke_test_subject_roster"
```

Covers the file round trip (including that a `NaN` weight stays `NaN`), many-to-many membership, per-project retire, the protocol fallback chain, the rename block, two rosters writing one file concurrently, an unwritable target leaving the good file byte-identical, the `BoxID` seam, the batch commit passing self-test group D, both all-or-nothing refusals, and a repeated import linking rather than duplicating.

See also: [`gui.SubjectManager`](../gui/gui_SubjectManager.md), [`epsych.Subject`](../overviews/Class_Map.md), `plans/multi-subject-support.md`
