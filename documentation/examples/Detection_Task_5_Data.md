# Detection Task 5 — Loading and Analyzing Saved Data

Part of the [detection task worked example](Detection_Task_Walkthrough.md).
Example file: [explore_saved_data.m](../../examples/detection_task/explore_saved_data.m).

This stage covers what a session leaves behind and how to read it — the part of
the workflow with the fewest guardrails, since a saved `.mat` is just data.

## What is in a session file

The saving function writes one file per subject. With the default
`ep_SaveDataFcn` the file holds one variable, `Data`; with `cl_SaveDataFcn`
(and the worked example) it also holds `Info`:

| Variable | Contents |
|---|---|
| `Data` | 1×N struct array, one element per completed trial, in presentation order |
| `Info` | `EPsychInfo().meta` snapshot: `Version`, `Checksum`, `commitTimestamp`, ... — which code produced the data |

Each `Data` element has one field per readable parameter (everything that is
visible, non-trigger, and not write-only — so both `Access='Read'` read-backs
like `RespCode` and dispatched stimulus values like `ToneLevel`), keyed by the
parameter's `validName`, plus four fixed fields:

| Field | Meaning |
|---|---|
| `TrialIndex` | 1-based position in the session (matches the array index) |
| `TrialID` | Row of the compiled condition list that was presented |
| `computerTimestamp` | `datetime` at trial completion |
| `isTest` | True for Preview/simulated sessions — filter these before analysis |

**The array index is chronological order.** `TrialID` is a condition label —
which row of the trial table ran — and repeats throughout the session. Sorting
or iterating by `TrialID` scrambles a session; this is a classic analysis bug.

```matlab
S = load('ExampleSubject_260808T170257.mat');
DATA = S.Data;
lvl = [DATA.ToneLevel];          % per-trial vectors line up by array index
rc  = uint32([DATA.RespCode]);
```

## Decoding outcomes

`RespCode` packs the entire trial outcome into one `uint32` whose bits are
named by [epsych.BitMask](../epsych/epsych_BitMask.md). `decode` expands a code
vector into one logical array per flag:

```matlab
M = epsych.BitMask.decode(rc);
sum(M.Hit)                        % hits in the session
M.TrialType_0                     % logical index of go trials
find(M.FalseAlarm, 5)             % first five false-alarm trials
```

From there the standard detection metrics are a few lines — hit rate per level
among go trials, false-alarm rate from catch trials, and d' via the same
static helper the online tools use (it applies finite corrections so a perfect
or empty cell stays finite):

```matlab
faRate = sum(M.FalseAlarm & M.TrialType_1) / sum(M.TrialType_1);
levels = unique(lvl(M.TrialType_0));
for k = 1:numel(levels)
    ind = M.TrialType_0 & lvl == levels(k);
    hitRate(k) = sum(M.Hit & ind) / sum(ind);
end
dprime = arrayfun(@(h) psychophysics.Detection.d_prime(h, faRate), hitRate);
```

`explore_saved_data` wraps exactly this into a printed report and a
three-panel figure: the trial timeline (every trial in presentation order,
color and marker shape per outcome), the psychometric function against the
catch false-alarm rate, and d' per level.

## Reusing the online tools offline

Several runtime components accept saved data directly:

- `gui.ParameterScatter(DATA, container)` — pass the `Data` struct array as the
  source for the same scatter view the box GUI shows live
  ([gui_ParameterScatter.md](../gui/gui_ParameterScatter.md)).
- `psychophysics.Staircase(DATA, 'ToneLevel', ...)` and the other
  [psychophysics.Psych](../psychophysics/psychophysics_Psych.md) subclasses run
  in offline mode when given a DATA struct array and a field name instead of a
  runtime and parameter.

## Recovering an interrupted session

If a session dies before the saving function runs, the data survive in the
`.epj` trial journal beside the crash-recovery file, in
`RUNTIME.TempDataDir`. Rebuild the `.mat` from it first:

```matlab
epsych.TrialJournal.recover('RUNTIME_DATA_ExampleSubject_Box_01_260808170257.epj')
```

That reports how many trials were recovered (and whether the crash tore the
final record) and writes the `.mat`. Its layout differs from a normally saved
session: an `info` struct plus one variable per trial (`data_0001`,
`data_0002`, ...). Reassemble the familiar struct array:

```matlab
S  = load('RUNTIME_DATA_ExampleSubject_Box_01_260808170257.mat');
fn = sort(fieldnames(S));
fn = fn(startsWith(fn, 'data_'));
c  = cellfun(@(f) S.(f), fn, UniformOutput = false);
Data = [c{:}];                    % identical to a normally saved Data array
```

Validation: `tmp/smoke_test_detection_example.m` (headless;
`matlab -batch "run('tmp/smoke_test_detection_example.m')"`).

Back to the [walkthrough index](Detection_Task_Walkthrough.md).
