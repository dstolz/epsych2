# The lab database (CarasLabDB) as EPsych's subject registry

`labdb.Registry` connects EPsych's [subject roster](../epsych/epsych_SubjectRoster.md) to the Caras lab's [CarasLabDB](https://github.com/dstolz/CarasLabDB):

- every session saved on a rig becomes a **behavior event** in the database, with its data file;
- every weight typed into the roster becomes a **weigh-in**;
- the Subjects & Projects window links roster animals to the database's animals, imports them, and warns before an animal with an endpoint, or one under weight, is run.

It is optional. EPsych works the same without it, and with it **a database that is down or unreachable never stops or slows a session**. What would be sent waits on the rig and goes when the database answers.

## What you need

- The CarasLabDB checkout on the MATLAB path: its `@CarasLabDB` class and its `+labclient` package, which is the client every lab toolbox shares. `addpath('C:\src\CarasLabDB')` in your `startup.m` is enough.
- That checkout must be recent enough: `labclient.Api.Version` of 3 or later (`labdb.Registry.CLIENT_VERSION`). An older one is not used; `[ok, why] = labdb.Registry.isAvailable()` says so, and the log says it when the registry is set but could not start. `git pull` in the CarasLabDB folder fixes it.
- The Database Toolbox, which CarasLabDB connects through.
- MATLAB R2024a or later, for the password vault (`setSecret`).

Without these, the Customize dialog does not offer the registry, and EPsych runs as before.

## Set it up (once per computer)

1. **RunExpt → Customize → Subject Registry**: choose **Lab DB (CarasLabDB)** and click OK.
2. Click **Settings...** on that tab (or the *Lab DB* lamp in Subjects & Projects). This opens the shared **Database window**, the same one ephys_analysis uses. A computer that is already set up for ephys_analysis is already set up here.
3. In the Database window:
   - tick **Use the lab database on this computer**;
   - fill in the server, your login and the time zone;
   - set the password (it goes to the MATLAB vault);
   - click **Test connection**.
4. Under **Storage roots on this computer**, map or register the folder this rig saves data into, for example `D:\Data` as `rig-booth3-d`. A data file outside every mapped root is held until its root is mapped.

## What is recorded

| In EPsych | In the database |
|---|---|
| A session saved on Stop (never a Preview) | One **behavior** event per subject. Its id is the session's `SessionUID`, which is also stored in the data file. It records the protocol name as `task`, the paradigm, and the number of completed trials. Its notes are the session notes. Its attributes hold the protocol file and version, box, rig, behavior GUI, roster ids and code versions. The data file is the event's output, with its SHA-256. |
| **Save Data** again before the record was sent | The waiting record is replaced. |
| **Save Data** again after it was sent | The new file is registered as replacing the old one at the same path. |
| A weight entered or changed in the roster | One **husbandry** event, `measure = weight`, in grams. A second change to the same animal on the same day, made before the first was sent, replaces it: a typo fix is not a second weighing. |

A record names the animal by its **link** (the roster subject's `RegistryID`), or by its roster name when it has no link. An animal the database does not have holds the record. The Database window's **Assign subjects...** lets you pick the right animal or create it, and the record is then sent.

ephys_analysis, copying a recording session that includes the ePsych file, finds this event by the file's bytes and records its copy as a file of it. It does not create a second behavior event.

## When things are sent

- Never while a session runs. The sender stands down from the moment the trial loop starts until the data are saved.
- Otherwise, every 15 s, one record at a time. Each try waits at most a few seconds for the server, and after a failure the next try waits longer (from 5 s up to 5 minutes).
- At once, from the Database window's **Send now**.

Sending a record twice writes it once.

## In the Subjects & Projects window

The **Lab DB** menu, the lamp and the Lab DB column are described in [gui_SubjectManager.md](../gui/gui_SubjectManager.md#the-lab-database).

- What the column shows (an endpoint, or weight as a percentage of baseline) is what the database last told this computer. **Lab DB → Refresh Status** asks again, and is refused during a session.
- **Baseline weight** is the database's subject variable `baseline weight`. Without it, no percentage is shown.

## In scripts

```matlab
labdb.Registry.enable()                      % or disable()
r = epsych.SubjectRegistry.current();        % the labdb.Registry
r.status()                                   % State, Message, Pending, NeedYou
r.refreshStatus(["SUBJ-ID-421"])             % ask the database (not during a run)
T = r.subjectStatus(["SUBJ-ID-421"])         % what it last said, offline
T = r.findSubjects(struct('Project', pid));  % its animals, in the roster's words
R = epsych.SubjectRoster();
R.importSubjects(table2struct(T), ProjectID = 'Detection');
```

## Code

| File | What |
|---|---|
| `obj/+labdb/Registry.m` | The adapter: `epsych.SubjectRegistry` over `labclient` |
| `obj/+labdb/SessionBundle.m` | The records: a session as a behavior event, a weighing as a husbandry event (`caraslabdb-bundle/1`) |
| `tmp/smoke_test_labdb_registry.m` | End to end over `labclient.FakeBackend`: no server, no Database Toolbox, nothing of yours touched. It says SKIPPED without the CarasLabDB checkout. |

See also: [epsych_SubjectRegistry.md](../epsych/epsych_SubjectRegistry.md), CarasLabDB's `labclient` documentation.
