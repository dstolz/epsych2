# Remove the `.ecfg` Config subsystem; the subject's membership carries the session config

> **Revision 2026-08-19** (against the working tree at `6d02855`): three substantive deltas since
> the plan was written, plus line drift.
>
> 1. **`SubjectRoster.copyProject` now exists** and is a *second* membership-creation site
>    (`applyCopyMembers` builds records directly, not via `assign`). Phase 1(a) gains its field
>    carry list; Phase 1(c) gains a stamping rule for copies — see both.
> 2. **The bug-report feature** (`ReportIssue`, landed 2026-08-19) reads `CurrentConfigFile` at
>    `issueEnvironmentText_.m:46` — a new Phase 3 edit.
> 3. **`paradigms/BehaviorGUIs/cl_AppetitiveDetection_BoxGUI.m` is already deleted** (landed with
>    the BlockSequence work); its Phase 7 row is done, the changelog line stays.
>
> Line drift: `RunExpt.m` back half **+5** (SetDefaultFuncs :586-602, GetDefaultFuncs :604-632,
> ClearConfig :648-658, ConfigBrowserRestoreOnTop :669, updateConfigLabel_ :502-518,
> set.CurrentConfigFile :212-218) and declaration blocks now :475-477/:480-481/:486-488;
> RunExpt `buildUI.m`: mConfig :152-166 unchanged, `UpdateRecentConfigsMenu` :326, config label
> :336-351, layout `[4 2]` :330-333; SubjectManager `buildUI.m`: import tool :53-57 unchanged,
> import menu item :153, mProject block :175-183, subject table :347-352, context menu ~:364-376,
> File→Refresh :148; `smoke_test_subject_roster.m` adoption section now ~:671-691 (copyProject
> sections pushed everything after ~:270 down). Work from anchors, as the plan already says.

## Context

`epsych.SubjectRoster` + `gui.SubjectManager` (landed 2026-08-13…15) took ownership of session
configuration: a project carries `DefaultProtocol`, `DefaultDataPath`, `SavingFcn`, `BehaviorGUI`,
`TimerPeriod`, and the video/Intan recording roots, and `assignToSession` commits subjects,
protocols, and boxes into `RunExpt.CONFIG` and applies those defaults. The Customize dialog was
already split along the same line — it keeps what describes *this machine* and shows grey
"where it went" notes where the paradigm-owned fields used to be.

The `.ecfg` Config subsystem is the last rival configuration path, and the two contradict each
other:

- `obj/+epsych/@SubjectRoster/assignToSession.m:229-231` states the rule — settings "land
  on the session (FUNCS, DefaultDataPath, PATHS) and **never in the machine preferences**".
- `obj/+epsych/@RunExpt/LoadConfig.m:79` and `obj/+epsych/@RunExpt/onCloseRequest.m:64` both call
  `SetDefaultFuncs`, which `setpref`s `SavingFcn` / `BehaviorGUI` / `TimerPeriod` / `TIMERfcn.*`.
  Loading a colleague's config re-points this rig's defaults, and **closing RunExpt after a project
  applied its settings persists that study's settings as the rig default.**

Two directives govern this revision:

1. **Backward compatibility is not a consideration.** No deprecation release, no migration path,
   no compat shim. `.ecfg` becomes unreadable *and unimportable*; every legacy shim in the
   configuration path is deleted.
2. **The project is not the source of session settings — the subject is.** A roster defines a
   selection of subjects; *selecting a single subject selects all config required to run it.*
   Concretely: per-run configuration lives on the **subject↔project membership** (extending the
   per-membership protocol memory already there). A project survives as **grouping + config
   template**: its Session Defaults are *stamped onto the membership* when a subject joins, and
   later project edits do **not** propagate to existing memberships. A multi-subject commit is
   **refused unless every selected membership agrees** on the session-level settings.

Outcome: one authoring path (Subjects & Projects), one precedence rule (**built-in constant →
membership value, applied session-only**), the pref write-back bug gone by construction, and no
`.ecfg` reader anywhere.

## Decisions locked (do not relitigate during implementation)

- Config home: the membership. Projects: grouping + template, stamp-on-add, no propagation.
- Multi-subject commits refused on mismatch of session-level settings.
- Legacy `.ecfg` importer deleted outright (Phase 6).
- Rig-pref floor removed: `ep_RunExpt_FUNCS/{SavingFcn,BehaviorGUI,BoxFig}` and all of
  `ep_RunExpt_TIMER` stop being read; `GetDefaultFuncs` returns literals plus the surviving
  `AddSubjectFcn` pref (Phase 2).
- Shim sweep (Phase 7): `BoxFig` alias, `SubjectRoster.aliasBehaviorGUI_`, prefdir adoption
  (`legacyFile`/`AdoptLegacy`), `cl_AppetitiveDetection_BoxGUI`, `gui.BoxGUI` +
  `tmp/LegacyShimGUI.m`, `design/ep_AddSubject.m` + the GUIDE calling convention, legacy `.prot`
  filters + the two format shims in `Protocol.load.m:33-39`.
- **Kept deliberately** (extension points or out of scope, not compat): the `AddSubjectFcn` seam
  itself (pref, Customize entry, `dispatchAddSubjectFcn_`); `epsych.DefaultSubject`'s
  `ep_AddSubject` species-pref sharing; `Runtime` property aliases (`HELPER`/`CORE`/
  `dfltDataPath`); JSON phase loading; `TrialJournal`'s legacy record path.

## Changelog obligations

Deletions that silently change behavior on a real rig; each needs a changelog line:

- A rig pref (`ep_RunExpt_FUNCS`/`ep_RunExpt_TIMER`) that customized defaults **stops applying**.
  The membership (via its project template) must name those settings now.
- A roster whose *projects* carried session settings **stops applying them to sessions** until
  the operator uses **Re-apply Project Template** — the settings moved from the project to the
  membership, and existing memberships start blank (= built-ins). The roster feature is days old,
  so the blast radius is near nil, but the line must exist.
- A pre-rename `.esub` carrying only `BoxGUI` **loses that field silently** once
  `aliasBehaviorGUI_` goes; the membership then reads as "inherit built-in".
- A project still naming `cl_AppetitiveDetection_BoxGUI` fails at run start with the clear
  "not on the path" report from `assignToSession.m:335-338` — an error, not silence.

## Ordering hazards — read before starting

1. **Class-load atomicity (highest risk).** MATLAB refuses to load a classdef whose `@`-folder
   declares a method with no file, or ships a file with no declaration. Every file
   deletion/addition and its declaration edit must be **one commit** — this now applies to
   `RunExpt.m` (Phase 3), `SubjectRoster.m` (Phases 1, 6, 7), and `SubjectManager.m` (Phases 1,
   6). `clear classes` (or restart MATLAB) before testing — a cached stale classdef produces
   errors that look nothing like the cause.
2. **Phase 1 must land before Phase 3.** Delete `LoadConfig` before the membership carries the
   timer callbacks and there is an intermediate commit where a non-default timer callback is
   unreachable by any means.
3. **Phase 1 must land before Phase 2.** Phase 2 edits `projectDialog_` seed lines that
   Phase 1(f) restructures into a shared helper.
4. **Within Phase 1, (b) stamping + (e) `assignToSession` land together** (with (b)'s fields):
   stamping written but never read is benign; reading membership config before stamping exists
   is not.
5. **Wiki regeneration comes last** — running `/update-wiki` before
   `tmp/generate_wiki_screenshots.m` is rebuilt will crash in `writeConfig` or capture a window
   still showing the config strip.

## Phase 1 — Membership-owned session config (additive; must land first)

`FUNCS.TIMERfcn.{Start,RunTime,Stop,Error}` are required by
`obj/+epsych/@RunExpt/CheckReady.m:15-16`, have no GUI anywhere, and today reach a rig only via
`setpref` or a distributed `.ecfg`. Removing Config first would strand any lab running a custom
trial loop — so the carrier fields land first, and under the new model the carrier is the
**membership**, with the project holding the template.

### (a) Template fields on the project

Add four **flat char** fields to the project record: `TimerStartFcn`, `TimerRunTimeFcn`,
`TimerStopFcn`, `TimerErrorFcn`. Flat rather than a nested `TIMERfcn` struct because `normalize_`
reprojects shape-only onto `fieldnames(template)` (`normalize_.m:23-38`) and `updateProject`'s
text loop coerces with `char(string(...))` — flat char fields ride both with no new branches.
Default `''` = inherit. `FORMAT_VERSION` stays 1 (additive; see (b) for why a v2 gate buys
nothing).

- **`blankProject_.m`** — 17 → 21 fields. Insert after `'SavingFcn'`, before `'TimerPeriod'`, so
  the timer group is contiguous. (`emptyProject.m` derives from this — no edit needed.)
- **`addProject.m`** — four `(1,:) char = ''` options after `SavingFcn`, four `rec.X = options.X;`
  assignments after ~:95, four docstring lines.
- **`updateProject.m`** — append the four names to the text-field loop at :81-83; do **not** add
  them to the `Links`/`TimerPeriod`/`Archived` special cases.
- **`copyProject.m`** (new since the plan was written) — four `(1,:) char` entries in the
  `arguments` block (no defaults, like every override there), four names in the carry-loop
  string array (~:99-101), and the docstring's override-field list (~:31) grows by four.

### (b) Config fields on the membership

`blankMembership_.m` gains **11 fields**, inserted after `LastBoxID` (:21), before `Added` (the
`ProtocolHistory` post-assignment at :28 stays last):

```matlab
'DefaultDataPath','', 'SavingFcn','', 'BehaviorGUI','', 'TimerPeriod',NaN, ...
'TimerStartFcn','', 'TimerRunTimeFcn','', 'TimerStopFcn','', 'TimerErrorFcn','', ...
'VideoRootDir','', 'IntanRootDir','', 'IntanSettingsFile','', ...
```

Flat char (TimerPeriod double), **identical names to the project's**, so stamping, the mismatch
check, `updateMembership`, and the dialog collector iterate one shared constant. Add to
`SubjectRoster.m` `properties (Constant)` (after `PROTOCOL_HISTORY_LIMIT`, :122-127):

```matlab
% The session-level settings a membership carries and a project template stamps.
SESSION_FIELDS = {'DefaultDataPath','SavingFcn','BehaviorGUI','TimerPeriod', ...
    'TimerStartFcn','TimerRunTimeFcn','TimerStopFcn','TimerErrorFcn', ...
    'VideoRootDir','IntanRootDir','IntanSettingsFile'}
```

`emptyMembership.m:12-13` derives from the blank — no edit. **`FORMAT_VERSION` stays 1**:
`addProject`'s options all default empty (`addProject.m:55-67`), so a scripted project has an
empty template and stamps empty config — "empty = inherit built-in" must be a legal membership
state regardless, and a v2 gate would only add a refusal branch in `reload.m` while making a
version-1 roster (the lab's animals and protocol history) unreadable.

### (c) Stamping semantics

There are now **two** membership-creation sites (the "only site" claim predates `copyProject`):
`assign.m:41-57` (`applyAssign`, the new-record branch; `importFromConfig.m:89` routes through
`assign` and dies in Phase 6) and `copyProject.m`'s `applyCopyMembers` (~:127-176), which builds
records directly under the mutation lock. Stamp in `applyAssign`:

```matlab
rec = epsych.SubjectRoster.blankMembership_();
for f = epsych.SubjectRoster.SESSION_FIELDS
    rec.(f{1}) = p.(f{1});          % p resolved at assign.m:29-32; capture into applyAssign
end
```

And in `applyCopyMembers`, stamp each copied membership from the **new project's template** (the
record `r.Projects(k)` just created — which already equals the source's template unless the call
overrode a field), **never from the source memberships**: a copy starts a study's next phase on
agreed settings, and carrying per-subject divergence forward would seed the mismatch refusal into
a project that has never run. This is the membership-level analogue of "ProtocolHistory is never
copied". `CopyProtocolMemory` keeps its current meaning (protocol/version/box only).

Rules, chosen for least special-casing:
- **Reactivating an existing membership does not re-stamp** (`applyAssign`'s early-return branch
  :43-47 unchanged) — per-subject edits survive, and "Add to Project is safe to click twice"
  (`assign.m:5-7`) stays true.
- **Pre-pivot memberships: no error, no lazy re-stamp, no read-time inherit.** `normalize_` fills
  them to `''`/NaN = inherit built-ins; the recovery is **Re-apply Project Template** (see (f)).
  Changelog line above.
- The project dialog refuses blanks (`projectDialog_.m:341-351`), so any template authored
  through the GUI stamps complete.

### (d) Roster API

Declared in the `SubjectRoster.m` membership methods block (:186-189) — class-load atomic with
the new files:

- `updateMembership(self, subjectId, projectId, M)` — mirrors `updateProject`: text loop over the
  ten char `SESSION_FIELDS` with `char(string(...))`, `TimerPeriod` through the same
  `localToPeriod`-style validation (`updateProject.m:60-67, :109-121`); engine-owned fields
  (`SubjectID`, `ProjectID`, protocol memory) ignored if supplied. Throws
  `epsych:SubjectRoster:NoSuchMembership`.
- `reapplyTemplate(self, subjectIds, projectId)` — copies the project's `SESSION_FIELDS` onto
  each named membership; returns an updated/skipped report like `updateProtocol`'s.

### (e) `assignToSession` rewrite

Signature unchanged (:37-44). Revised flow:

1. Guards and the box/protocol planning loop unchanged (:54-142).
2. **New step — resolve config per planned subject**, after planning and **before** the
   protocol-load loop at :144 (fail fast, before any side effect): for each planned subject,
   find its membership in the chosen project; a missing membership resolves to
   `blankMembership_()` (all-inherit), noted in the report. `ProjectID = ''` (All Projects / no
   project context) skips config application entirely — same as today's early return at :236.
3. **Mismatch refusal**: compare **raw** `SESSION_FIELDS` across the resolved memberships with
   `isequaln` (handles the `TimerPeriod` NaN). Raw, not resolved: memberships in one project are
   verbatim stamps of one template and diverge only through a template edit between adds or a
   deliberate per-subject edit — exactly what must surface; resolving first would hide real
   divergence behind coincidental defaults. On disagreement, refuse through the class's
   established refusal channel (matching box exhaustion, :106-112): `report.aborted = true`,
   nothing committed, message shape:

   ```
   The checked subjects carry different session settings, so nothing was added:
   SavingFcn: "ep_SaveDataFcn" (M001, M002) vs "cl_SaveGapData" (M003).
   Edit each subject's Session Settings..., or Re-apply Project Template, until they agree.
   ```

   plus a machine-readable `report.mismatch` (struct array: `Field`, `Values`, `Names`) so the
   GUI and tests never parse the message. (`addToSession.m:47-51` already renders aborts as a
   modal. Reserve `epsych:SubjectRoster:SessionConfigMismatch` if a hard error is ever wanted.)
4. Protocol-load and commit loops unchanged (:144-187), including `rememberProtocol` per subject.
5. `localApplySessionDefaults(self, runExpt, projectId)` becomes
   `localApplySessionDefaults(self, runExpt, m, projectName)` where `m` is the agreed membership
   (any of them — they are equal): the body (:222-301) and `localApplyBehaviorGUI` (:304-341)
   survive with `p.X` → `m.X`, plus this block inserted between the `SavingFcn` block (:257-264)
   and the `TimerPeriod` block (:267-270):

```matlab
timerMap = {'TimerStartFcn','Start'; 'TimerRunTimeFcn','RunTime'; ...
            'TimerStopFcn','Stop';   'TimerErrorFcn','Error'};
changed = {};
for i = 1:size(timerMap,1)
    v = m.(timerMap{i,1});
    if isempty(v), continue, end
    if ~strcmp(char(runExpt.FUNCS.TIMERfcn.(timerMap{i,2})), v)
        runExpt.FUNCS.TIMERfcn.(timerMap{i,2}) = v;
        changed{end+1} = timerMap{i,2};
        if isempty(which(v))
            vprintf(0, 1, ['Subject''s membership names timer function "%s", which is not ' ...
                'on the path. The run would fail at %s.'], v, timerMap{i,2});
        end
    end
end
if ~isempty(changed)
    applied{end+1} = sprintf('timer %s function(s)', strjoin(changed, '/'));
end
```

   Same three rules as every neighbour: empty inherits, nothing is refused per-field, nothing
   reaches a pref. The `function_handle` guard at :323-327 simplifies — it existed because
   `DefineBehaviorGUI` accepted handles, and that dialog dies in Phase 2.
6. **Still from the project record**: its Name for messages, `DefaultProtocol` via the unchanged
   `lastProtocol` fallback chain (membership `LastProtocol` → project `DefaultProtocol` → `''`),
   and bookkeeping (`Investigator`, `IACUCProtocol`, `Links`, `Archived`). Nothing else.
7. Update the `ProjectID` option docstring (:20-24), the header comment (:189-194), and the rule
   sentence (:229-234) — all now describe the membership as the source ("land on the session …
   never in the machine preferences" stays true; the source changes).

### (f) SubjectManager UI

- **Shared grid**: extract `projectDialog_`'s Session Defaults grid (rows :184-290, seeding
  helpers `localSeed`/`localItems`/`localRemember`/`localTint` :625-700, BehaviorGUI display
  mapping :720-770) into a private `sessionDefaultsGrid_(self, parent, seed, tagPrefix)` helper.
  `projectDialog_` keeps `ProjectDlg_*` tags; the new membership dialog uses `MembershipDlg_*`
  (the smoke tests' `^ProjectDlg_` probe keeps meaning "the template").
- **Template tab growth** (the old plan's edit, unchanged in substance): Session Defaults grows
  8 → 12 rows (`uigridlayout(tabSession,[12 3])`, `repmat({28},1,12)`); new rows 6-9 under Timer
  Period; Video/Intan/IntanSettings shift to 10/11/12. Each new row an editable `uidropdown`
  tagged `ProjectDlg_TimerStartFcn` etc., seeded per-field MRU → built-in literal (no pref step —
  the floor dies in Phase 2), Reset button, `localTint` validator. **Arities from
  `checkFunctions.m:69-73` (verified): Start = 2 in / 1 out; RunTime, Stop, Error = 1 in /
  1 out.** Add all four to `onOK`'s `blanks` refusal list, the `result` struct (:370-383), and
  `localRemember` (:391-400). Retitle the tab **"Session Defaults (template)"**; docstring
  (:18-23) gains: stamped at add-to-project, edits do not reach existing members, see Re-apply.
- **Membership editor**: new private `membershipDialog_(self, seed)` built on
  `sessionDefaultsGrid_`; opened from a subject-table context-menu item **"Session Settings for
  This Row..."** (context menu at `buildUI.m:352-365`) plus a Subject-menu twin. It **also
  refuses blanks** (reuse the :341-351 collector) — every membership it opens on is stamped
  complete or seeded from built-ins, so the inherit state can arise only from scripts and
  pre-pivot rosters, never from the dialog. OK calls `updateMembership`.
- **Re-apply Project Template to Checked** — `Project` menu item (block at `buildUI.m:169-175`)
  calling `reapplyTemplate`; enabled with `writable && inProject && hasChecked`
  (`updateEnableStates_` pattern, `SubjectManager.m:536-541`). It is the mismatch refusal's named
  fix and the pre-pivot migration story.
- **Settings column**: narrow column after `Version` (`buildUI.m:336-341` — ColumnName/Format/
  Editable/Width each grow by one; `refresh.m` fills it): `''` in the All Projects view or with
  no membership, `template` when the membership's `SESSION_FIELDS` equal the project's current
  template (`isequaln` against the already-fetched record, no file I/O), `edited` otherwise.
  This is what makes the mismatch refusal predictable before the click.
- **Version column / Update-All protocol machinery: entirely unchanged** — protocol memory,
  `protocolStatus`, `updateProtocol`, `revertProtocol`, the banner (`buildUI.m:318-333`), and
  `RunExpt.UpdateSubjectList`'s orange-cell mechanics are orthogonal to this pivot.
- `updateProjectSummary_` (`SubjectManager.m:327-380`) and `localSessionDefaultsLine`
  (:1407-1426): `Session:` → `Template:`; "(session default)" → "(built-in default)" (also the
  dialog display mapping at `projectDialog_.m:746-756`).
- `onNewProject_` hand-builds the project seed (:1189-1196) and enumerates every option in its
  `addProject` call (:1202-1214); both gain the four timer fields. `onEditProject_` passes `P`
  straight through — no edit.
- New declarations (`membershipDialog_` + the two callbacks) in `SubjectManager.m:166-173` —
  one commit with the files.

### (g) Docs

`documentation/epsych/epsych_SubjectRoster.md`: project-field table gains four rows; Memberships
array-table row (:30) gains the eleven. Full doc rewrite lands in Phase 8.

## Phase 2 — Retire the pref write-back AND the pref floor

The write-back bug fix, plus the floor itself: with the membership as the config source, the
prefs' only remaining role was a rig-local default layer nothing in the UI can set anymore.
Precedence becomes **built-in constant → membership** — which also makes "inherit" deterministic
for the first time (`''` SavingFcn = `ep_SaveDataFcn`, `''` BehaviorGUI = `ep_GenericGUI`, NaN
TimerPeriod = 0.01, `''` timer fcns = `ep_TimerFcn_*`; empty paths = the rig's
`GetDefaultPaths`/`RunExpt/DataPath` values, which survive — machine facts, not paradigm facts).

- **`onCloseRequest.m`** — delete :64 (`self.SetDefaultFuncs(self.FUNCS)`) and fix the header
  comment at :4-5 ("resets functions to preferences"). This alone fixes the bug.
- **`RunExpt.m`** — delete `SetDefaultFuncs` (**:581-597** — note the original plan's back-half
  offsets were 2 low). The `BoxFig` alias write (:590) dies with it.
- **`RunExpt.m` — collapse `GetDefaultFuncs` (:599-626) to constants**: keep only the
  `AddSubjectFcn` pref read + its self-heal (:605-615); `SavingFcn`/`BehaviorGUI`/`TIMERfcn.*`/
  `TimerPeriod` become the literals `'ep_SaveDataFcn'`, `'ep_GenericGUI'`, `'ep_TimerFcn_*'`,
  `0.01`. The `BoxFig` fallback read (:618-619) dies here (Phase 7 item, lands with this edit).
- **Delete the orphaned `Define*` dialogs outright** — `DefineSavingFcn.m`,
  `DefineBehaviorGUI.m`, `DefineTimerPeriod.m` have **no menu or toolbar caller anywhere**
  (verified by repo grep; only their declarations at `RunExpt.m:56,61,62` and cross-reference
  comments). `DefineTimerPeriod.m:30` was the last session→pref write; deleting the file beats
  editing the line. `DefineBehaviorGUI`'s function-handle acceptance is why
  `assignToSession.m:323-327` guards against handles — simplify that guard in Phase 1(e).
  `DefineAddSubject` and `DefineRosterFile` stay (the seam and the roster chooser are live).
- **`checkFunctions.m`** — B6's `prefSpecs` rows for `SavingFcn` (:134) and `BehaviorGUI` (:136)
  become tautological once the prefs don't exist (permanent "drift" against a nonexistent pref):
  drop both, keep `AddSubjectFcn` (:135). The three `rmpref('ep_RunExpt_TIMER')` remedies (:78,
  :86, :100) become dead ends: reword to point at Session Settings / Edit Project → Session
  Defaults (matching :32, :63, :111).
- **`projectDialog_.m` seeds** (:72, :74, :87) — replace the `getpref` last-resorts with the
  literals; behavior nearly unchanged because `localSeed`/`localRecentPeriod` consult the
  per-field MRU first.
- **`GetRecentFuncs.m:8` / `RememberRecentFunc.m:8`** — both docstrings name a `RecentSavingFcn`
  key under `ep_RunExpt_FUNCS` that **nothing reads or writes** (verified; the `RecentSavingFcn`
  in `tmp/smoke_test_subject_manager.m:429` is a different key under `ep_RunExpt_Subjects`).
  Drop the name.

Still writing prefs legitimately, unchanged: `OpenCustomizeDialog.onOK_` (`AddSubjectFcn`,
`RunExpt/DataPath`, `ExternalViewer`, `eplog/LogDir`, roster file), `RememberRecentFunc` and the
`ep_RunExpt_Subjects/Recent*` MRUs (user memory, not settings), `ep_RunExpt_Video/EnableRecording`,
`ep_RunExpt_Setup/{PDir,DDir}`.

After this, `ep_RunExpt_FUNCS` holds only `AddSubjectFcn` + the MRU keys, and `ep_RunExpt_TIMER`
is fully retired — never read, never written. **No `rmpref` migration ships** (mutates rig state
for a cosmetic gain; can throw on a group never created).

## Phase 3 — Delete the Config subsystem (one atomic commit)

**Delete 13 files** in `obj/+epsych/@RunExpt/`: `SaveConfig.m`, `LoadConfig.m`, `RefreshConfig.m`,
`BrowseConfigs.m`, `FindConfigFiles.m`, `ConfigBrowserLoad.m`, `ConfigBrowserCancel.m`,
`RememberRecentConfig.m`, `GetRecentConfigs.m`, `UpdateRecentConfigsMenu.m`, `LoadRecentConfig.m`,
`ClearRecentConfigs.m`, `DefineConfigBrowserRoot.m`.

**`RunExpt.m` surgery** — declarations are in **five** blocks, not one:

| Lines | Action |
|---|---|
| 4-6 | class docstring: drop "loads configuration files when requested" |
| 34 | delete the `CurrentConfigFile` **property** |
| 49-51 | delete `LoadConfig`, `RefreshConfig`, `SaveConfig` declarations |
| 57-58 | delete `DefineConfigBrowserRoot`, `BrowseConfigs` declarations |
| 83-199 | constructor — see Phase 4 |
| 212-218 | delete the `set.CurrentConfigFile` setter |
| 471-473 | delete `GetRecentConfigs`, `LoadRecentConfig`, `RememberRecentConfig` declarations |
| 476-477 | delete `UpdateRecentConfigsMenu`, `ClearRecentConfigs` declarations |
| 482-484 | delete `FindConfigFiles`, `ConfigBrowserLoad`, `ConfigBrowserCancel` declarations |
| 497-513 | delete `updateConfigLabel_` |
| 664-670 | delete `ConfigBrowserRestoreOnTop` |

**`ClearConfig` survives** (RunExpt.m:641-651). Despite the name it is not part of the file
subsystem: it resets `CONFIG` to the empty struct, drops STATE to NOCONFIG, and clears the subject
table. The constructor (:185) and `RemoveSubject.m:33` both depend on it; the third caller,
`LoadConfig.m:41`, goes away with that file. Do not add it to the deletion list, and do not let the
verification's `~ismethod` assertions include it. Optionally rename it `ClearSession` in the same
commit (two call sites + its declaration) so `Config` stops meaning two things; if renamed, keep
the PRGMSTATE name `NOCONFIG` — the enum is serialized in saved data and is out of scope.

**Dangling comment references** left by the deletions, fix in the same commit:
`GetRecentFuncs.m:13` ("Mirrors GetRecentConfigs") and `RememberRecentFunc.m:12`
("Mirrors RememberRecentConfig") — reword to describe the behavior (normalize, prune, dedupe, cap)
without naming the deleted methods.

**`buildUI.m`** — delete toolbar tools :45-67; delete the whole `mConfig` block :152-166; delete
`self.UpdateRecentConfigsMenu` (:301); delete the `config_name` label and `updateConfigLabel_` call
(:312-326). **Then change the layout `[4 2]` → `[3 2]`, drop the leading `22` from `RowHeight`, and
renumber `Layout.Row` 2→1, 3→2, 4→3** for the table, bottom bar, lamp grid, and status grid — this
is the easiest place to introduce a silent visual regression. Update the toolbar comment at :31-41.
Freed accelerators: C, L, R, S (R is reused in Phase 5). SelfTest I1/I2 name no config handle, so
the eight remaining `setup*` tags are safe.

**`OpenCustomizeDialog.m`** — delete the `cfgRoot` seed (:24-28), the Config Browser Root row
(:135-142) — Paths grid 6→5 rows, renumber Error Log Path 3→2, Viewer 4→3, Roster 5→4, note 6→5 —
and the apply block (:370-375). Fix the docstring at :4.

**`UpdateGUIstate.m:100-101`** — `'No configuration loaded.'` / `'load a config or add a subject.'`
→ `'No subjects in the session.'` / `'open Subjects & Projects and add checked subjects.'`

**`epsych.SelfTest`** — `checkGui.m`: delete the I4 dispatch (:103-109), `localConfigRoundTrip`
(:210-284), `localCompareSubject` (:286-308), and the now-orphaned `localCompareProtocol`
(:310-342), `localParamNames` (:344-352), `localDeleteFile` (:496-501); fix the docstring at :4
and :12. `checkConfig.m`: reword :30 and D4's "embedded in the config only" wording (:162, :179) —
that branch is now reachable only via a hand-built CONFIG. `formatReport.m:36`: drop the
`config "%s"` clause and its `CurrentConfigFile` argument.

**`obj/+util/@VideoConverter/scan.m:15`** cites "the `epsych.RunExpt.FindConfigFiles` contract" —
reword the dangling reference.

**`issueEnvironmentText_.m:46`** (bug-report feature, new since the plan): delete the
`'Config file'` row — the neighbouring rows already name the subjects and protocol, which is
what identifies a session now.

**Fixtures** — `git rm examples/stimgen/StimGen.ecfg examples/stimgen/StimGenCal.ecfg` and drop
those rows from `examples/stimgen/README.md` (:14-15) plus the :4 sentence, **in the same commit**.
`tmp/AversiveDetectionConfig.ecfg` dies in Phase 6 with the importer.

**Prefs retired** (stop reading/writing; **do not ship an `rmpref` migration** — it mutates rig
state for a cosmetic gain and can throw on a group never created):
`ep_RunExpt_Setup/{CDir, ConfigBrowserRootDir, RecentConfigs, RecentConfigLoadedOn}`. `PDir` and
`DDir` in the same group stay live (`AddSubject`, `LocateProtocol`, `ChangeProtocolFile`,
`projectDialog_`). Phase 6's importer deletion removes the last `CDir` reader
(`onImportFromConfig_.m:19`), making the retirement unconditional.

## Phase 4 — Replacement scripted-launch API

Repurpose the positional slot from a config path to a **project name/ID**, so a stale
`epsych.RunExpt('x.ecfg')` fails loudly with `No project matches "x.ecfg"` — the right migration
message, and not a compat shim.

```matlab
epsych.RunExpt("Aversive Detection", Subjects=["M1","M2"], Run=true)
```

`arguments`: `project (1,1) string = ""`, plus `opts.Subjects`, `opts.Boxes`, `opts.Protocols`,
`opts.RosterFile`, and the existing `Verbosity`/`ReuseExisting`/`CleanupStaleFigures`/
`BringToFront`/`Run`.

Collapse both existing call sites (:173-178 and :191-196) into one call to a new private method
`obj/+epsych/@RunExpt/assignFromRoster_.m`, so the current duplication is removed rather than
doubled. It resolves the roster (erroring on `~IsBound`), resolves the project via `findProject`,
defaults `Subjects` to the project's non-retired members, calls `assignToSession`, then dispatches
`Run` — erroring with `epsych:RunExpt:NotReady` rather than silently doing nothing. Everything
routes through `assignToSession`, so the scripted path inherits the whole membership model —
including the mismatch refusal, which `assignFromRoster_` must surface as an error
(`report.aborted` → throw; a script has no modal). **No config options at launch time by
design** — the project names the grouping; config rides each subject's membership
(`addSubject` + `assign` stamps the template; `updateMembership` diverges one subject).

Two things, both verified against the source: `promptForDataPath_` (:189) raises a modal
`uiconfirm` gated only on `ispref('RunExpt','DataPath')` (`promptForDataPath_.m:8`), which blocks a
headless launch on a fresh machine — skip it when `project ~= ""`, since a stamped membership
names a data path. And `subjectsInProject` **does** filter retired members by default
(`IncludeRetired (1,1) logical = false`, `subjectsInProject.m:22`), so the "all non-retired
members" default needs no extra filtering.

Note on the migration message: `''` positional coerces to `""` under `(1,1) string`, so a stale
`epsych.RunExpt('')` is indistinguishable from no-arg and must be treated as "no project", not an
error — three tmp scripts rely on exactly that shape (see Verification items 3-4).

## Phase 5 — Fill the Refresh-Config capability gap

Refresh Config did two things. **(a) Re-read the subject/box/protocol set, discarding in-session
edits** — replaced by Remove Subject + re-add from the manager; no new affordance needed.
**(b) Reload every subject's protocol object from disk** — this is a real gap, and nothing today
covers it: `RunExpt.UpdateProtocol` (:251) reloads from disk but only for the **selected** subject;
`SubjectRoster.updateProtocol` and "Update All in Project" only re-record the expected version on
the membership ("Nothing about a protocol's *content* changes here"); `protocolStatus` only
reports; `UpdateSubjectList` flags stale rows orange but never reloads them. On a multi-subject
session Ctrl+R was the only one-click "everyone onto the freshly saved `.eprot`".

Extract the body of `UpdateProtocol` (:271-309) into a private
`[ok, oldV, newV] = reloadProtocolForSubject_(self, idx)`, then add a public `ReloadProtocols(self)`
that loops all of `CONFIG`, reports `n updated / n already latest / n failed` in one `uialert` +
`setStatus`, and calls `UpdateSubjectList` + `CheckReady` once at the end. Put it on the **Subjects**
menu as `Reload All &Protocols from Disk`, `Tag = 'setup_mnu_reload_protocols'`, `Accelerator = 'R'`
(freed above), and optionally in the toolbar slot the refresh icon vacated —
`gui.toolbarIcon("refresh")` already exists, so no icon work.

## Phase 6 — Delete the legacy importer

No migration path ships. Delete `importFromConfig.m`, `readConfigSubjects_.m`,
`onImportFromConfig_.m`, the SubjectManager toolbar tool (`buildUI.m:53-57`) + menu item
(:146-147), section 11 of `tmp/smoke_test_subject_roster.m` (:214-232), and the fixture
`tmp/AversiveDetectionConfig.ecfg`.

Blast-radius items (each verified against the tree):

- **Declarations**: `SubjectRoster.m:209` (`importFromConfig`), `:256` (`readConfigSubjects_`),
  **and `SubjectManager.m:170` (`onImportFromConfig_`)** — the SubjectManager one is the same
  class-load-atomicity hazard as RunExpt's; one commit.
- **`ImportedFrom` — three coordinated edits, in order**: the `fromSubject.m` option (:27) and
  assignment (:46) have exactly one caller (`importFromConfig.m:78`); delete the option, then the
  `blankSubject_.m:23` field. A careless `blankSubject_`-only edit makes `normalize_` silently
  discard the field from existing rosters.
- **Dangling cross-references**: `SubjectRoster.m:65` (method-list "migration" line),
  `exportTable.m:16`, `fromSubject.m:22`, `SubjectManager.m:14` (class docstring "out of existing
  .ecfg files"), `SubjectRoster.m:8` (class docstring "…none of which a `.ecfg` file records" —
  reword so the grep guard reaches zero).
- **Docs**: `epsych_SubjectRoster.md:282-286` (delete the import section) **and :309** — the
  Testing paragraph claims coverage of "a repeated import linking rather than duplicating", false
  once smoke-test section 11 goes; `gui_SubjectManager.md` toolbar table (~:41) and :239.

## Phase 7 — Legacy shim sweep

| Shim | Deletion spec |
|---|---|
| `ep_RunExpt_FUNCS/BoxFig` pref alias | write dies with `SetDefaultFuncs` (Phase 2); read dies in the `GetDefaultFuncs` collapse (:618-619, Phase 2); `LoadConfig.m:69-77`'s un-aliasing dies with Phase 3. Nothing left to do here — listed so the sweep is complete |
| `SubjectRoster.aliasBehaviorGUI_` | delete the file + declaration `SubjectRoster.m:252`; `saveAtomic_.m:31-34` → `projects = self.Projects;`; `reload.m:91-98` → plain `normalize_` call. **Data-losing for a pre-rename `.esub`** (carries only `BoxGUI`) — changelog line |
| Prefdir adoption (`legacyFile`/`AdoptLegacy`) | delete `legacyFile.m` + declaration `SubjectRoster.m:228` + docstring mention :68; strip `AdoptLegacy` from `setConfiguredFile.m` (:3, :21-27, :30-31, :37, :41, :56, :95-111; report struct at :44 shrinks to `FilePath`/`Existed`); `DefineRosterFile.m:43-46, :53-56`; `SubjectManager.m:1315-1319, :1335-1341`; `OpenCustomizeDialog.m:400-404` comment; `tmp/smoke_test_subject_roster.m:577-615` adoption section; docs `epsych_SubjectRoster.md:148`, `gui_SubjectManager.md:49`, `CLAUDE.md:126-127` |
| `paradigms/BehaviorGUIs/cl_AppetitiveDetection_BoxGUI.m` | **already deleted** (landed 2026-08-19 with the BlockSequence work; no remaining reference anywhere). Nothing to do; the changelog line for a project still naming it stays |
| `gui.BoxGUI` + `tmp/LegacyShimGUI.m` | delete both + the `tmp/smoke_test_behaviorgui.m:153-163` section. Breaks only out-of-repo subclasses, which is the point |
| `design/ep_AddSubject.m` + GUIDE calling convention | delete the forwarder + `tmp/smoke_test_add_subject_dialog.m:66-68`; delete the legacy `feval(fcn, seed, boxids)` branch in `dispatchAddSubjectFcn_.m:54-61` (**keep** the :47-51 `.open`-tolerance and the `AddSubjectFcn` seam itself); update `Architecture_Overview.md:153` |
| Legacy `.prot` | not a load branch — `epsych.Protocol.load` treats it as a plain MAT file. Drop `*.prot` from the 8 dialog filters: `AddSubject.m:48`, `LocateProtocol.m:17`, `RunExpt.m:328`, `SubjectManager.m:1164`, `projectDialog_.m:523`, `Runtime/readParameters.m:57`, `ProtocolDesigner/onLoad.m:10-11`, `PhaseSelector.m:171`. Also delete the two 3-line format shims in `Protocol.load.m:33-39` (`protocol_struct` field name; files saved as live handle objects). Update `CLAUDE.md:473` ("legacy .prot still loadable") and decide `examples/stimgen/*.prot`: re-save as `.eprot` or delete with their README rows — record the choice in the commit message |

## Phase 8 — Docs and tmp/ scripts

| File | What |
|---|---|
| `documentation/overviews/RunExpt_GUI_Overview.md` | Heaviest. **Line numbers are for the current working tree** (the connect-recovery section §5.1 shifted everything after :155 down ~26 lines; work from section anchors): TOC :16; quick-start :31-40 (both `epsych.RunExpt("...ecfg")` examples → the Phase 4 API); :69-70; §3.1 config strip :74-76 (gone); toolbar :92-95; :106; :136 and gotcha :315 (`Config → Refresh Config` → Reload All Protocols); **delete §6 entirely, :205-224**; §7.1 prefs table :239 (Config Browser Root row) and the shrunken pref story (no floor); §7.2 → the template/membership model; §8 menu inventory :269; precedence sentences → "built-in → membership" |
| `Toolbox_Overview.md:67` | Sessions are assembled from the roster; a subject's membership carries its run config |
| `epsych_SubjectRoster.md` | The big rewrite: Memberships table row (:30); the "A project owns the session settings" section (:44-76) → "A membership carries the session settings; the project is its template" (the applied-to table :50-58, the two-rules paragraph :60, and the BehaviorGUI three-state table :68-74 all move, with `''` re-glossed as "built-in default"); format paragraph :253-255 gains the membership defaults; :70, :118 `.ecfg` mentions; import section per Phase 6 |
| `SubjectRoster.m` docstrings | :23-30 ("A project also owns the behavior GUI…" → membership/template); `BEHAVIORGUI_NONE` comment :117-121 ("A membership's") |
| `blankProject_.m:24-27`, `addProject.m:9-13, :33-36` | "applied by assignToSession" → "stamped onto memberships at assign" |
| `SubjectManager.m:5-19` | class docstring: the manager edits subjects, memberships, and templates |
| `documentation/gui/gui_SubjectManager.md` | project-dialog section (template), new membership dialog + Re-apply + Settings column |
| `documentation/gui/gui_ParameterDebugger.md:72-73` | "what reloading a config leaves behind" → reloading protocols (Reload All Protocols / Update to Latest Version) |
| `design/ProtocolDesigner.md:161`, `stimgen.md:70`, `examples/stimgen/README.md:4,14,15` | `.ecfg` mentions + deleted fixture rows |
| `CLAUDE.md` | :126-127 (adoption), :134-140 (project-owns → membership/template model), :387 "Configuration Persistence" item, :446/:473 file-extension lines, deleted-shims |
| `.claude/skills/update-wiki/references/page-map.md:18` | `Running-a-Session` page description |
| `epsych_startup.m:284` | comment mentioning `.ecfg` degradation |

**`tmp/generate_wiki_screenshots.m`** — the big one. Delete `writeConfig` (:553-582). Add a shared
`[RE, cleanup] = buildSessionFromRoster(C, boxIDs)` doing what `shotSubjectManager` (:451-484)
already does — scratch `.esub`, `setConfiguredFile` (**no `AdoptLegacy` after Phase 7**),
`addProject` with full session defaults **including the four TIMERfcn fields**, `addSubject` +
`assign` ×N (which stamps), `rememberProtocol` — then `epsych.RunExpt()` + `assignToSession`.
Rewrite `shotRunExpt` (:431-439), `shotSubjectManager` (:491-492), `shotSelfTest` (:529-544).
Two traps: `shotRunExpt`/`shotSelfTest` must now `setConfiguredFile` **and clear it in cleanup**
(as `closeSubjectManager` does at :524) or they leave the rig pointed at a tempdir roster; and
the `shotRunExpt` caption (:432) mentions a saved `.ecfg`.

`tmp/S_PATH.m:9` and `tmp/T_VlcRecorder_VLM.m:24` — `epsych.RunExpt('...ecfg')` → a project name or
bare `epsych.RunExpt`. `tmp/smoke_test_eplog.m:52-53` uses `'a.ecfg'` only as a format-test payload;
leave or swap cosmetically.

Out of scope but known: `obj/stimgen/documentation/stimgen_TDT_RPvds.md:28` names `StimGen.ecfg`
(a fixture Phase 3 deletes) — that file belongs to the stimgen submodule, so either accept the
dangling mention or fix it with a separate stimgen commit + pointer bump; never edit it here.
`plans/multi-subject-support.md:11` claims ".ecfg save/load round-trips the whole array" — stale
once this lands; annotate that plan rather than silently contradicting it.

## Verification

**Static first:** run `check_matlab_code` on every edited file, especially `RunExpt.m`,
`SubjectRoster.m`, `SubjectManager.m`, and `buildUI.m` — an `@`-folder declaration/file mismatch
only surfaces at class load.

Then, via the MATLAB MCP server (persistent session, absolute paths; never `clear`/`close all` —
but **do** `clear classes` after Phases 1, 3, 6, and 7, one call at a time):

1. `tmp/smoke_test_subject_roster.m` — extend first: the `rmfield` list at :337-339 and the
   `''`-default asserts at :351-352 gain the four template fields **and a membership-fields
   variant** (strip the eleven, assert all-inherit on reload). **Section 13 (:241-271) is
   invalidated by the pivot**: it applies a BehaviorGUI via `updateProject` then commits —
   rewrite against `updateMembership`/`reapplyTemplate` (the re-stamp is the new step between the
   template edit and the assertion).
2. `tmp/smoke_test_subject_manager.m` — the dialog probe at :586-640 auto-collects any
   `^ProjectDlg_` tag, so the four new dropdowns land in `built.fields` for free; add them to the
   seeded-and-non-blank assertion at :417. Add a `MembershipDlg_` probe for the new dialog.
3. `tmp/smoke_test_runexpt_selftest.m` — **:140 passes `''` positionally**, which becomes an empty
   project name under the new signature; fix it to no-arg. Harmless either way once
   `assignFromRoster_` treats `""` as "no project" (Phase 4), but explicit is better in a test.
4. `tmp/smoke_test_runexpt_video_menu.m`, `..._video_recording.m` — exercise `buildUI` handles and
   the `setup*` lockout after the toolbar/menu surgery. **Both also pass `''` positionally**
   (`:40` and `:59`) — fix to no-arg alongside item 3.
5. `tmp/smoke_test_two_afc.m`, `..._first_experiment.m`, `..._detection_example.m` — full run paths,
   so a broken `FUNCS.TIMERfcn` shows up.
6. `gui.SelfTest` once interactively (I4 removal, D-group wording, `formatReport` header).

**New headless check — `tmp/smoke_test_session_without_config.m`**, the artifact that proves the
change:

1. Snapshot `ep_RunExpt_FUNCS`, `ep_RunExpt_TIMER`, `ep_RunExpt_Subjects`, `ep_RunExpt_Setup`
   (follow `snapshotPrefs` in `generate_wiki_screenshots.m`); restore in `onCleanup`.
   **Poison-pref probe**: inside the guard, set `ep_RunExpt_TIMER/Start` and
   `ep_RunExpt_FUNCS/SavingFcn` to sentinels; construct `epsych.RunExpt(ReuseExisting=false)`;
   assert `FUNCS` holds the built-ins — the floor is *gone*, not just unwritten.
2. Temp `.esub`; `addProject` with all session defaults incl. four explicit TIMERfcn names;
   `addSubject` ×2 + `assign` ×2; `rememberProtocol` against an examples `.eprot`.
   **Assert stamping**: both memberships' `SESSION_FIELDS` equal the template.
3. **No propagation**: `updateProject` the template's `SavingFcn` to a sentinel; assert both
   memberships unchanged. **Copy stamping**: `copyProject(..., IncludeSubjects=true)` after a
   per-subject `updateMembership` edit; assert the copied memberships carry the new project's
   template, not the edited source values.
4. **Mismatch refusal**: `updateMembership` subject 2's `TimerPeriod`; `assignToSession` both →
   assert `report.aborted`, `report.mismatch` names `TimerPeriod`, and `numel(rx.CONFIG)`
   unchanged — nothing half-committed.
5. `reapplyTemplate` both; commit; assert the subsystem is gone (`~ismethod(rx,'LoadConfig')`,
   `~ismethod(rx,'SaveConfig')`, `~isprop(rx,'CurrentConfigFile')`,
   `~isfield(rx.H,'config_name')`, no `Config` uimenu), `rx.STATE >= PRGMSTATE.READY`, **and
   every `rx.FUNCS` field including all four `TIMERfcn.*` equals the membership values** — the
   gap-closed assertion, retargeted from project to membership.
6. **Single-subject full-config commit** — the headline requirement: fresh session, one subject;
   assert every session-level field (`FUNCS.*`, `DefaultDataPath`, `PATHS.*`) landed from that
   one membership.
7. **Pref write-back regression:** re-read the pref groups, `delete(rx)` (routes through
   `onCloseRequest`), re-read, `assert(isequal(...))`. **This test fails on today's `master`.**
8. **Scripted launch:** `epsych.RunExpt("<ProjectName>", ReuseExisting=false)`; assert
   `numel(CONFIG) == 2` and boxes 1-2. Then `Run=true` against the software-only detection
   protocol, poll for `STATE == RUNNING`, `halt`, assert `STATE == STOP`. Keep the `Run` leg
   **single-subject**: `ExptDispatch` takes hardware interfaces from `CONFIG(1).PROTOCOL` only
   (`assignToSession.m:209-217`).
9. **Roster round-trip**: save + reopen via `epsych.SubjectRoster(rosterFile)`; assert membership
   session fields survive; and a strip-fields synthesis (mirror
   `smoke_test_subject_roster.m:327-352`) asserting an old-shape membership reads back as
   all-`''`/NaN and commits as built-ins.
10. **Shim absence**: `~ismethod` `importFromConfig`/`legacyFile`/`aliasBehaviorGUI_` on the
    roster; no `tb_import` in SubjectManager; `exist('ep_AddSubject','file')==0`;
    `exist('cl_AppetitiveDetection_BoxGUI','class')==0`.
11. **Grep guards**: `.ecfg` → **zero hits in code** (exemptions: `plans/`, the stimgen
    submodule, `tmp/smoke_test_eplog.m` payload);
    `BoxFig|BoxGUI|AdoptLegacy|legacyFile|ep_AddSubject` → zero outside `plans/` and the
    submodule.

**Claims verified against source while reviewing this plan** (no need to re-derive):
- `checkFunctions.m:69-73` timer arities: Start = 2 in / 1 out; RunTime/Stop/Error = 1 in / 1 out. ✓
- `checkGui.m`'s `localDeleteFile` (:496) is file-local; `checkDataSaving.m` has its own copy
  (:323), so deleting checkGui's is safe. ✓
- `buildUI.m` toolbar tools :45-67, `mConfig` block :152-166 (incl. `self.H.mnu_config` at :166),
  and `OpenCustomizeDialog` ranges (:24-28, :135-142, :370-375) all match the working tree. ✓
- `RunExpt.m` back-half offsets: `SetDefaultFuncs` :581-597, `GetDefaultFuncs` :599-626,
  `updateConfigLabel_` :497-513, `ConfigBrowserRestoreOnTop` :664-670, `ClearConfig` :641-651. ✓
- RunExpt's Ctrl+R does not collide after Phase 5: SubjectManager's File → Refresh (Ctrl+R,
  `SubjectManager/buildUI.m:142`) and ParameterDebugger's Rebuild List (Ctrl+R) live in their own
  figures — uimenu accelerators are per-figure. ✓
- `assign.m` `applyAssign` (:43-56) is the sole membership-creation site; `importFromConfig.m:89`
  routes through it. ✓
- `DefineSavingFcn`/`DefineBehaviorGUI`/`DefineTimerPeriod` have no UI caller anywhere. ✓

## Residual risks

- Pre-pivot memberships (and any subject added by a script that skips template authoring) carry
  all-inherit config until edited or re-stamped — the session runs on built-ins, which may
  surprise a lab that had set project-level or pref-level values. The Settings column shows
  `edited`/`template` at a glance, and the changelog names Re-apply Project Template as the fix.
- `projectDialog_` OK now refuses four more blanks, so every existing project's Edit dialog
  demands them on first open. They arrive pre-seeded so OK succeeds first try, but it is a
  visible change.
- The mismatch refusal makes a previously-silent state (subjects with diverged settings) a hard
  stop at commit time. That is the design working as intended, but the first time a lab hits it
  mid-morning it will read as a regression — the message's two named fixes are what keep it a
  30-second detour.
