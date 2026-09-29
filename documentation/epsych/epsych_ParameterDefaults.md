# `epsych.ParameterDefaults`

Per-subject parameter values that replace the protocol's for one subject, applied
every time Run or Preview is pressed. This class is the headless half: the record
shape, which parameters can carry a default, validation, applying and undoing, and
reading values back from a session or a saved data file.
[`gui.ParameterDefaultsEditor`](../gui/gui_ParameterDefaultsEditor.md) is the window
over it; [`epsych.SubjectRoster`](epsych_SubjectRoster.md) stores the records on the
membership.

```matlab
R = epsych.SubjectRoster;
d = epsych.ParameterDefaults.blank();
d.Interface = 'TDT_RPcox'; d.Module = 'Behavior'; d.Name = 'Depth';
d.Value = -12;                          % start this animal's staircase at -12 dB
R.setParameterDefaults('M001', 'Tone Detection', d);

R.parameterDefaults('M001', 'Tone Detection')   % what M001 overrides there
```

Static only; not constructible.

## A record

| Field | Meaning |
|---|---|
| `Interface` | the owning interface's `Type` (`'Software'`, `'TDT_RPcox'`, ...) |
| `Module` | the owning module's `Name` |
| `Name` | the parameter's `Name` |
| `Value` | the replacement; `[]` leaves the protocol's value alone. A numeric vector is a list of trial levels — a roved parameter's own set for this subject |
| `Min`, `Max` | replacement bounds; `NaN` leaves the protocol's alone |

A record can set a value, bounds, or both. One that sets nothing is refused.

## Where it lives, and when it applies

The defaults belong to the **membership** — a subject in a project — like its
protocol memory and session settings, because parameter names come from the
project's protocol: the same animal in two studies keeps two sets. They are not
part of the project template and are never stamped; a batch commit never has to
agree on them.

They are read **at Run, not at commit**. `assignToSession` records on each CONFIG
entry where the subject came from (`CONFIG(i).ROSTER`, built by `rosterLink`: roster
file, SubjectID, ProjectID, and a copy of the defaults as they stood), and
`epsych.RunExpt.ExptDispatch` calls `RunExpt.applyParameterDefaults_` before it
validates and compiles anything. That re-reads the roster once per file, so a
default edited after the subject was added still counts. If the roster cannot be read
then (the share is offline, the file moved), the commit-time copy is used and the log,
status bar and session notes say so.

`RunExpt.ViewTrials` applies the same defaults to the fresh copy it compiles, so the
preview shows what the subject will run.

## Applying (`apply`)

Two steps, in this order:

1. **Restore.** Everything the previous Run replaced on this same protocol object is
   put back (the apply *state*, kept on `CONFIG(i).ROSTER.State`). A default removed
   between runs therefore returns the protocol's value, and one still there is applied
   to the protocol's value rather than on top of the last run's. The state is tied to
   the protocol handle: a protocol reloaded (Reload Protocols, Change Protocol File) is
   pristine and starts clean.
2. **Apply.** Each record is resolved, checked, and written: `Min`/`Max` first, then
   `Values`, then `Value` when there is exactly one level.

Things a reader would otherwise re-derive:

- **`Values`, not just `Value`.** `compile()` builds the trial table from `Values`, and
  `hw.Interface.resetSession` returns an undispatched parameter to `Values{1}`; a
  `Value` written alone would be overwritten by the first dispatch. `needsCompile`
  compares the file's save time with the last compile and cannot see an in-memory
  change, so `ExptDispatch` recompiles every protocol whose defaults changed anything.
- **Bounds before the value.** `hw.Parameter` clamps a value into `[Min Max]` on write
  (and not on read). A default outside the protocol's range therefore needs its bound
  moved in the same record — and `check` refuses one that is still out of range,
  rather than letting the clamp change it silently.
- **Writing `Value` reaches the hardware** on a connected backend and runs the
  parameter's update callbacks, exactly as a phase load does
  (`epsych.Runtime.readParameters`). Every backend skips the device write while
  disconnected, which is the state of the first Run and of `ViewTrials`' copy. A write
  that throws is logged; the `Values` still stand.
- **Nothing is thrown for a default that no longer fits.** A record whose parameter
  is gone, or that fails `check`, is skipped and listed in `report.Skipped`. A
  protocol revised since the default was set must not stop the subject from running;
  the operator hears about it instead.
- **Precedence during a run.** Defaults go on at Run. A phase loaded mid-session
  (`gui.components.PhaseSelector`) overwrites them for the rest of that session — the
  operator's later action wins — and the next Run applies the defaults again.

## Which parameters qualify (`eligibility`)

| Parameter | Value | Min/Max |
|---|---|---|
| Float, Integer | yes | yes |
| Boolean, String, File | yes | no |
| randomized (`isRandom`) | no — redrawn every dispatch | yes |
| read-only, trigger | no | no |
| momentary control (`hw.Parameter.isTransientControl`) | no | no |
| has an `Expression` | no — recomputed every dispatch | no |
| Buffer, Coefficient Buffer, StimType, Undefined | no | no |

Hidden parameters qualify too: `resetSession` starts them at `Values{1}`.

## Checks (`check`)

Against the parameter it names, with the record's own bounds taking effect first:
type, finite, whole numbers for Integer, every level inside `[Min Max]`, `Min <= Max`,
finite bounds on a randomized parameter, and — for a **paired** parameter
(`UserData.Pair`) — the protocol's level count, since `compile`'s paired expansion
produces no trials otherwise.

## Matching a record to a parameter (`resolve`)

By interface, module and name; then by interface and name, when the module was
renamed. The editor saves a record matched the second way under the name the protocol
uses now, which migrates it.

## Reading values back

| Method | Reads | Takes |
|---|---|---|
| `readSession(runExpt, name, T)` | what the session holds now, for one subject | values and bounds |
| `latestDataFile(name, Roster=, RunExpt=)` | the newest saved session with trials | — |
| `readDataFile(file, T)` | the last filled trial record of a saved `Data` | values only |

`readSession` follows the phase-save rule (`Runtime.writeParametersProtocol`): for a
dispatched parameter the committed trial-table value, since a deferred commit lands
there first; for everything else the live `Value`. The departure is a column that
varies across the trial table — a parameter a staircase manages. A phase save leaves
those alone so as not to freeze the staircase; here the live `Value` is exactly what
is wanted ("start the next session where this one is"). The trial table is matched to
the subject by name, since CONFIG can be edited after a Stop and TRIALS cannot.

`latestDataFile` goes through [`epsych.SessionFiles`](epsych_SessionFiles.md), so it
looks under every data root the subject could have used and skips Preview runs and
crash-recovery copies. The newest file is not necessarily the right one for a subject
in two projects, which is why the editor names it before copying.

`readDataFile` reads fields by `validName`, as `ep_TimerFcn_RunTime` wrote them. Bounds
are never in the data. A hidden or write-only parameter is not in `Data`, so it is
simply not found.

## Methods

| Method | Does |
|---|---|
| `empty()`, `blank()` | a 0-element record array; one record at "leave the protocol alone" |
| `normalize(D)` | shape stored records; never throws, drops a nameless one |
| `validate(D)` | structural check with no protocol: names, something to apply, sane bounds, no parameter twice |
| `key(d)`, `label(d)` | `Interface\|Module\|Name`; `Module.Name` |
| `summary(D)`, `describe(d, unit)` | one line of text for an export column or a note |
| `parameters(protocol, IncludeHidden=, IncludeIneligible=)` | the rows the editor lists |
| `eligibility(P)`, `resolve(protocol, d)`, `check(d, P)` | see above |
| `parseValue(text, P)`, `formatValue(v)`, `formatLevels(P)`, `levels(v, type)` | text in the editor; numbers are parsed with `str2double` per token, never evaluated |
| `apply(protocol, D, state)`, `emptyState()`, `emptyReport()` | on Run |
| `rosterLink(file, sid, pid, D)`, `lookup(link, Roster=)`, `applyToConfigEntry(C, Roster=)` | the CONFIG seam |
| `readSession`, `latestDataFile`, `readDataFile` | capture |

## The record in the data

`RunExpt.applyParameterDefaults_` writes one note per subject into
`RUNTIME.NOTES` (tagged with the subject, stamped trial 0): what was applied, what was
skipped and why, and whether the roster copy was used. The session snapshot already
holds the resulting values; the note is what says they came from the subject.

## Testing

`tmp/smoke_test_parameter_defaults.m` is headless: record helpers, parsing,
eligibility, checks, apply/restore/recompile and the name fallback, the roster round
trip including a file written before the field existed, `copyProject` and
`exportTable`, the CONFIG seam with its snapshot fallback, and reading values from
saved data files. `readSession` needs a live `epsych.RunExpt` and is not covered.

See also: [`gui.ParameterDefaultsEditor`](../gui/gui_ParameterDefaultsEditor.md),
[`epsych.SubjectRoster`](epsych_SubjectRoster.md),
[`gui.SubjectManager`](../gui/gui_SubjectManager.md).
