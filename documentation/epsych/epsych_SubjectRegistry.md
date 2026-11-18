# `epsych.SubjectRegistry`

The seam between EPsych and a lab's **subject registry**: the database that owns each animal's identity (sex, species, birth, endpoint) and keeps the lab's record of what was done to it. EPsych ships one adapter, `labdb.Registry`, for the Caras lab's [CarasLabDB](https://github.com/dstolz/CarasLabDB) (see [labdb_Registry.md](../labdb/labdb_Registry.md)).

**EPsych needs no registry.** The class itself *is* the "none" registry, and `epsych.SubjectRegistry.current()` returns it until a computer is configured otherwise. A new installation runs exactly as it did before the seam existed:

- no preference is created (`ispref` before `getpref`);
- nothing outside this repository is loaded;
- every surface that shows registry state asks `isEnabled()` first and stays hidden.

## Division of ownership

| | Owns | Where |
|---|---|---|
| Registry | who the animal is: id, sex, species, birth, endpoint, weight history | the lab database |
| Roster | how the animal is run: protocol, session settings, parameter defaults | the `.esub` file ([epsych.SubjectRoster](epsych_SubjectRoster.md)) |

The two are joined by **`RegistryID`**, a field on each roster subject and project (`''` = not linked). One registry id names at most one roster subject (`epsych:SubjectRoster:DuplicateRegistryID`). `findSubject` deliberately does not resolve registry ids; `findByRegistryID` does. `importSubjects(records, ProjectID=)` brings registry animals in:

- it links by `RegistryID`, then by name to an *unlinked* subject, else adds one;
- it updates identity (Sex, Species) and nothing else;
- it enrols new members without reviving a retired one;
- it does all of this in one roster write.

## What EPsych tells a registry, and when

| Call | From | Carries |
|---|---|---|
| `sessionRunning(true)` | `RunExpt.PsychTimerStart`, as the trial loop starts | — |
| `sessionSaved(records)` | `RunExpt.SaveDataCallback`, after the saving function returned; never for a Preview | one [`epsych.SessionRecord`](#epsychsessionrecord) per subject |
| `sessionRunning(false)` | `SaveDataCallback`, after the save, whether it worked or not | — |
| `weightMeasured(subject, grams, when)` | `SubjectRoster.addSubject` with a finite weight; `updateSubject` when the weight **changes** | the roster record |

The weight hook sits in the roster, so every edit path reaches it: the add-subject dialog, `RunExpt.EditSubjectDetails` and the manager. `EditSubjectDetails` mirrors every edit with the weight it already had, which is why an unchanged weight is not a weighing. A weighing is reported whether or not the roster write landed, because the animal was weighed either way.

Core code calls the static wrappers: `notifySessionRunning`, `notifySessionSaved(RUNTIME, CONFIG, FUNCS)` and `notifyWeight`. Each one catches everything and logs it, so a broken adapter costs a log line, never a session or a roster write.

## What an adapter must do

An adapter subclasses `epsych.SubjectRegistry` and overrides what it supports. EPsych calls it from places where a wait or a failure would cost an experiment, so the contract is strict:

- **No network during a run.** Between `sessionRunning(true)` and `(false)` EPsych calls nothing else, and the adapter must not send in the background. The trial loop is a MATLAB timer on the same thread, and `backgroundPool` was rejected for durability ([TrialJournal](epsych_TrialJournal.md)).
- **Record locally and return.** `sessionSaved` and `weightMeasured` keep what they are given and return. Sending happens later, and a record that cannot be sent waits rather than fails.
- **`subjectStatus` answers from what the adapter holds.** That means a cache with an `AsOf` time per entry. `refreshStatus` is the one call allowed to go and look, and the manager refuses it while a session runs.
- **`findSubjects(filter)` honours `filter.CacheOnly`.** The manager sets it during a run. `filter.Project` narrows the answer to one registry project.
- **Nothing throws.**
- **New methods get safe defaults.** A method added to the base class later must be concrete with a safe default, or every adapter becomes unconstructable (the `stimbridge` rule).

The shapes are fixed by `emptyStatus(ids)`, `emptySubjects()` and `emptyProjects()`. `table2struct` of `findSubjects` feeds `importSubjects` directly.

## Warnings before a session

`sessionWarnings(subjects)` is concrete in the base class, so every adapter warns the same way. It works from `subjectStatus` (the cache only) and returns a warning in two cases:

- an endpoint is recorded for the animal;
- the latest weight is under `LOW_WEIGHT_PERCENT` (85, the lab database's own default) of the `baseline weight`.

Each warning names how old the information is. It is used in two places:

- [`gui.SubjectManager`](../gui/gui_SubjectManager.md)'s **Add Checked to Session** asks the operator first. Going ahead is logged, because the session's notes do not exist yet.
- `assignToSession` puts the warnings in `report.registryWarnings` and logs them. A script is never refused.

## `epsych.SessionRecord`

`epsych.SessionRecord.fromRun(RUNTIME, CONFIG, i)` describes one subject's finished session as plain data, so any adapter can record it. It reads no hardware and never throws; whatever it cannot find is left empty and named in `Problems`.

It is built in RunExpt, not in a saving function, because a saving function receives only `RUNTIME`. `RUNTIME` knows neither the protocol file nor the roster subject, so building the record in RunExpt is what makes it work with every saving function, a lab's own included.

Fields:

- `SessionUID`, the subject, and its roster ids and registry links. These are read from the roster **now**, so a subject linked after it was added to the session still counts.
- The saved file. `ep_SaveDataFcn`'s `.mat` rule applies, and the path is checked to exist.
- Zoned start and end times. The end is the last trial's `computerTimestamp`.
- The trial count, and the protocol file, name, version and paradigm.
- The behavior GUI and saving function.
- The operator's notes for this subject's file.
- The host, provenance checksums, and whether the run ended in an error.

## `SessionUID`

Every subject of every Run gets a session identity, minted by `ExptDispatch` beside the reserved filename (`RUNTIME.SessionUID(i)`). `SessionSnapshot.capture` stores it, so it reaches `Info.SessionUID` in every saved file and in the crash-recovery seed. `epsych.SessionFiles` reports it. It names the same session in every copy of its file and in the registry, where `labdb.Registry` uses it as the behavior event's id. It is useful with no registry at all.

`epsych.newUUID()` mints a v4 UUID under two constraints:

- **No Java,** for the same reason as `SubjectRoster.newId`.
- **The global random stream is left alone,** because a trial selector may be drawing from it.

The bits come from `tempname`, whose unique name is an RFC 4122 v4 UUID from the operating system (verified on R2024b). A private `RandStream` takes over should that ever change.

## Choosing a registry

The preference `EPsych/SubjectRegistry` names the adapter class. Set it in **RunExpt → Customize → Subject Registry**, where "(none)" is the default, or with `epsych.SubjectRegistry.setConfiguredClass(cls)`:

- the dropdown offers only adapters whose dependencies are present (`availableAdapters`, from `KNOWN_ADAPTERS`);
- a configured class that is missing or will not construct falls back to "none" and logs once.

**Self-test check A7** passes with no registry, and only ever warns when one is set up. A registry that is down costs a record waiting on this computer, never a session.

## Testing

- `tmp/smoke_test_subject_registry.m` (headless): the "none" registry, `newUUID`, `RegistryID` (including in a roster written before it), `importSubjects`, the weight hook, `SessionRecord`, the session hooks, a throwing registry, and `sessionWarnings`.
- `tmp/smoke_test_subject_registry_gui.m` (opens windows; run it on a hidden desktop): the manager and the Customize tab over `tmp/FakeSubjectRegistry.m`.

See also: [epsych_SubjectRoster.md](epsych_SubjectRoster.md), [gui_SubjectManager.md](../gui/gui_SubjectManager.md), [labdb_Registry.md](../labdb/labdb_Registry.md)
