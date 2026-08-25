# gui.components.BufferPlot

The contents of a buffer parameter, redrawn once per completed trial. Where
`gui.components.OnlinePlot` polls scalar parameters against a scrolling clock,
`gui.components.BufferPlot` shows what is IN a buffer — a recorded waveform, a lick
trace, a spike-count vector — one trial at a time.

Source: `obj/+gui/@BufferPlot/`

## What it does

- **Plots one or more `Buffer` parameters** as traces, refreshed on every
  `NewData` event. `Coefficient Buffer` parameters are not offered: they hold
  session-static data (calibration coefficients), so there is nothing
  per-trial about one and every redraw would show the same numbers.
- **Buffer samples by default.** A buffer knows how many samples it holds and
  nothing else, so that is the x axis until someone says otherwise. Naming a
  `SampleRate` — a number, or `"auto"` to take it from the owning `hw.Module`
  — turns it into seconds or milliseconds.
- **History.** `NumTrialsShown` draws the previous N trials behind the newest
  one, fading with age, which is how you see a response drifting rather than
  just this trial's.
- **Two layouts.** `overlay` puts every buffer on one pair of axes with a
  legend; `stacked` gives each its own vertical band, labelled on the y axis.
- **Decimates by envelope.** A buffer of 131072 samples is drawn as a min/max
  envelope of at most `MaxPoints` points, so no excursion is lost and the
  axes stay responsive. `MaxPoints = Inf` draws every sample.
- **Everything is settable twice**: from code through the properties and
  `setBuffers`/`setTraceColor`, and from the axes right-click menu. Both land
  on the same setters, so nothing the operator can do is out of a script's
  reach.
- **Persists the operator's arrangement** by `PreferenceTag`, and opens in a
  window of its own through `gui.PopOut`.
- **Works offline and in review**, unchanged — see below.

## Usage

```matlab
% In a gui.BehaviorGUI subclass's build() — registered for teardown:
obj.addBufferPlot(g, Buffers="Waveform~1", SampleRate="auto");
obj.addBufferPlot(g, Buffers=["Lick~1" "Spout~1"], Layout='stacked', ...
    NumTrialsShown=5);

% Standalone, over a runtime:
bp = gui.components.BufferPlot(RUNTIME, panel, Buffers="Waveform~1", SampleRate=24414);
bp.XAxisUnits = 'milliseconds';
bp.setTraceColor('Waveform~1', [0.8 0.2 0.2]);

% Offline, over a saved session:
S = load('SUBJ01_2026-08-25.mat');
gui.components.BufferPlot([S.data_0001 S.data_0002 S.data_0003], uifigure);
```

| Property | Default | Meaning |
|----------|---------|---------|
| `XAxisUnits` | `'samples'` | `'samples'`, `'seconds'`, `'milliseconds'`. Time units with no sample rate anywhere fall back to samples. |
| `SampleRate` | `0` | Hz. `0` means unknown. The constructor also accepts `"auto"`/`"module"`. |
| `Layout` | `'overlay'` | `'overlay'` or `'stacked'`. |
| `NumTrialsShown` | `1` | Newest trial plus this many behind it. |
| `HistoryAlpha` | `0.3` | How faint the oldest history trace is. |
| `MaxPoints` | `10000` | Envelope target; `Inf` draws every sample. |
| `LineWidth`, `LineColors`, `Palette` | `1`, palette-derived, `'Okabe-Ito'` | Trace appearance. |
| `ShowGrid`, `ShowLegend` | `true`, `true` | Axes decoration. |
| `YLimMode`, `YLim` | `'auto'`, `[0 1]` | Freeze the y axis so one big trial cannot rescale the rest. |
| `Paused` | `false` | Stop capturing and redrawing. The trial record is unaffected. |
| `BoxID` | `[]` | Restrict `NewData` updates to these boxes; empty accepts all. |

| Method | What it does |
|--------|--------------|
| `setBuffers(names)` | Choose the buffers and their order. Unresolvable names are skipped, not thrown. |
| `bufferNames()` / `availableBuffers()` | What is plotted / what could be. |
| `setTraceColor(nameOrIndex, rgb)` | Colour one trace; remembered against the NAME. |
| `selectBuffers()` | The operator's picker (also on the right-click menu). |
| `exportToWorkspace(varName)` | The newest trial's buffers, at full resolution, into the base workspace. |
| `update()` | Capture and redraw now. |
| `hasSavedConfiguration()` / `forgetConfiguration()` | Query or discard the saved arrangement. |

### Right-click menu

Select Buffers…, X Axis (units and Sample Rate…), Layout, Trials Shown, Line
Width, Palette, Trace Colour (one entry per buffer), Resolution, Y Limits
(Auto / Freeze at current / Set…), Grid, Legend, Pause, Copy Data to
Workspace, Reset Appearance, and the `gui.PopOut` items.

## Why it is built this way

- **The data comes out of the trial record, not off the device.**
  `ep_TimerFcn_RunTime` already reads every readable parameter at trial
  completion — buffers included, since `all_parameters(Access='Read')`
  excludes only write-only ones — and stores it in that trial's `DATA`. A
  second read would be another multi-megabyte transfer (on `hw.TDT_RPcox`, a
  COM one) for numbers the runtime is already holding. A buffer the record
  does NOT carry — an invisible parameter, filtered out of that read — falls
  back to reading the parameter itself, once per trial.
- **Which is why it works in three places for free.** Live, under
  `epsych.ReviewSession` (which notifies with `DATA(1:k)`, so the last record
  is the trial being reviewed and seeking backward simply redraws), and
  offline over a saved `DATA` struct array. Hardware is never read in
  `ReviewMode`: `hw.Replay` answers from a snapshot whose buffer CONTENTS
  were deliberately blanked (`epsych.SessionSnapshot.capture`).
- **Envelope decimation, not striding.** Dropping 9 samples in 10 hides
  exactly the brief transient a buffer is usually being watched for. Each bin
  contributes its minimum and its maximum, in the order they occur, so the
  line never runs backwards in x. Envelopes are cached by trial index, so a
  history of past trials costs one pass per trial rather than one per redraw.
- **History is rebuilt from `DATA`, not accumulated.** Nothing to go stale
  when the operator changes `MaxPoints`, and seeking backward in a review
  shows the trials before the one being reviewed rather than the ones that
  happened to be captured last.
- **Colours blend toward the background rather than using an RGBA `Color`.**
  Alpha on a `Line` is not rendered the same way by every supported release; a
  blend reads identically on all of them.
- **A `SampleRate` stated by the caller always wins over a saved one.** It is
  a fact about the device, not a preference. The UNITS are the operator's, and
  they are restored.
- **A remembered SELECTION is restored only when the operator made it by
  hand.** A `Buffers` list passed to the constructor is what the paradigm's
  `build()` asked for, and a saved list from another protocol must not
  silently replace it — the rule `gui.components.OnlinePlot` settled on.
- **Auto-selection stops at four buffers.** A region nobody configured still
  plots something, without filling the axes.

## In the BehaviorBuilder

On the palette under **Displays** as *Buffer Plot*, poppable, with an options
dialog offering the protocol's buffer parameters, the sample rate, the layout,
and the trial depth. Leaving the buffer list empty is a real answer: the
generated `build()` then calls `gui.components.BufferPlot` with no `Buffers` and the plot
takes the session's own.

## See also

- `documentation/gui/gui_OnlinePlot.md` — live scalar traces against a clock
- `documentation/gui/gui_ParameterScatter.md` — one point per trial
- `documentation/gui/gui_PopOut.md`, `documentation/gui/gui_BehaviorGUI.md`
