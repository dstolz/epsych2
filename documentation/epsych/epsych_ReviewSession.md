# Offline session review

Reopen a finished session in the paradigm's own behavior GUI, with every display
showing what it showed when the session ended — plus a scrubber to wind back to
any trial.

```matlab
epsych.ReviewSession                        % pick a file
R = epsych.ReviewSession('session.mat');    % opens at the last trial
R.seek(42);
R.step(-1);
R.play(4);      % 4 trials per second
R.pause();
```

From the session window: **Utilities > Review Saved Session...** (Ctrl+K), or the
toolbar's page-with-a-play-triangle tool. Both stay available while a session is
running — a review reads a file and touches no session state.

---

## Why it works without changing any display component

Three properties of the existing runtime carry the whole feature.

**The event hub is publicly notifiable.** `epsych.EventHub` declares its events
`NotifyAccess = 'public'`, so a review fires real `NewTrial` / `NewData` /
`ModeChange` into a real hub. No component can tell the difference, and none
needs a replay code path.

**Consumers recompute from the whole array.** `psychophysics.Psych.update_data`
assigns `obj.DATA = event.Data.DATA` and recomputes from scratch;
`gui.ParameterScatter`, `gui.History` and `gui.SessionPerformance` do the
equivalent. So **one notify carrying `Data(1:k)` is worth k notifies**, and
seeking *backward* costs exactly what seeking forward costs. There is no
replay-from-the-start and no per-component reset to maintain.

**Controls already disable themselves.** `gui.Parameter_Control` listens for a
`mode` `PostSet` on its parameter's interface and greys out at `Idle`/`Standby`.
A review moves its backends `Standby -> Idle` *after* the window is built, and
every control disables itself. Nothing in `+gui` was modified for this feature.

The runtime is therefore a **real `epsych.Runtime` with a real
`epsych.EventHub`**, not a stand-in. That is required rather than merely tidy:
`psychophysics.Detection` is not a `psychophysics.Psych` subclass and has no
struct-source path — it only knows how to listen to `RUNTIME.EVENTS`.

---

## The three pieces

### `epsych.SessionSnapshot` — what a file has to carry

A saved `.mat` holds `Data`: one struct per trial, fields named after the
recorded parameters. Enough to re-plot behaviour, not enough to rebuild the
paradigm's controls — a `build()` method asks for parameters by name, and
nothing in `Data` says what those parameters were.

The snapshot is a plain struct (no handles, no hardware) carrying the serialized
protocol (`epsych.Protocol.toStruct`), the compiled trial table and its column
map, the subject, and the provenance.

`ep_TimerFcn_Start` captures it once per subject **at session start** and puts it
in two places:

- `RUNTIME.TRIALS(i).SessionInfo`, for the saving function;
- the crash-recovery file's `info` record, so a session rebuilt by
  `epsych.TrialJournal.recover` reviews exactly like one that saved normally.

**Any saving function writes it in one line** — this is not limited to
`ep_SaveDataFcn`:

```matlab
Data = RUNTIME.TRIALS(i).DATA;
Info = epsych.SessionSnapshot.forSubject(RUNTIME, i);
save(fileloc, 'Data', 'Info')
```

`forSubject` never throws. Where no snapshot was captured — a scripted session
that filled `TRIALS` itself, or a custom Start function predating this — it
describes the runtime as it stands; if even that fails, it returns a blank and
the file reviews as a legacy file.

Reading back goes through `epsych.SessionSnapshot.fromInfo`, which also accepts
the two shapes that predate the class: a flat `EPsychInfo.meta` struct (what
`cl_SaveDataFcn` used to write as `Info`) and the older recovery `info` record.
`FORMAT_VERSION` is the discriminator. Adding a field is additive — `fromInfo`
fills in what an older file does not carry, so **every default must mean what a
file written before that field meant**.

### `hw.Replay` — a backend that reads the record

One `hw.Replay` per serialized interface, its module tree rebuilt from the
snapshot with `hw.Module.fromStruct` / `hw.Parameter.fromStruct`. Names are
restored verbatim, including `~`/`!` trigger prefixes and `~BoxID` box suffixes,
because `gui.BehaviorGUI.resolveParameter_` matches on `validName`.

Two design points that are easy to get wrong:

**`IsConnected` is `true` on purpose.** `hw.Parameter.get.Value` short-circuits
to the locally cached value for an `hw.Software` parent *or a disconnected one*.
Either would return the protocol's **design-time** value rather than the trial's.
Reporting connected is what routes the read into `get_parameter`, which looks the
field up in `Records(Position)`.

**Values are never assigned.** `set.Value` runs `randomize_value`, `Expression`
evaluation and `clamp_value_` — restoring values would re-derive the very numbers
being reviewed — and throws outright on a read-only parameter like `RespCode`.
The design-time fallback (for write-only, invisible and trigger parameters, which
never reach `DATA`) is read straight out of the struct and kept on the interface.
It cannot be read back off the parameter: that would recurse through
`get_parameter`, the same trap `hw.Software.get_parameter` documents.

`hw.Replay` is absent from the four backend-registry sites on purpose. It is
never saved into an `.eprot`, and it must not appear in ProtocolDesigner as
something to add to a protocol.

### `epsych.ReviewSession` — the runtime and the player

`seek(k)` is the whole player:

1. set `Position = k` on every `hw.Replay`, so every parameter read — a
   `gui.Parameter_Monitor` poll, `gui.ParameterDebugger`'s Read, a paradigm hook
   — reports what the rig held on trial k;
2. build the `TRIALS` struct;
3. notify `NewData` then `NewTrial`, in that order, because that is the order
   `ep_TimerFcn_RunTime` uses.

The two notifies carry deliberately **different** trials, matching the live
meanings: `NewData` describes the trial that just completed (`TrialIndex == k`,
`numel(DATA) == k`), while `NewTrial` describes the one that would run *next*, so
`gui.NextTrial` shows the trial that actually followed rather than repeating the
one being looked at. At the last trial there is no next, so `NewTrial` repeats
trial k rather than inventing one.

`epsych.Runtime.ReviewMode` suppresses the one-shot dispatch in `set.TRIALS`.
Without it, assigning `TRIALS` would write every writable parameter through
`set.Value` and fire the `ResetTrig`/`NewTrial` hardware triggers.

**The windows own the review.** Every window a review opens holds a reference
back to it in appdata (`epsych_ReviewSession`), so the review lives exactly as
long as they do. This is load-bearing, not tidiness: `epsych.ReviewSession(file)`
with no output argument ends in `clear obj`, and without an anchor the handle
object is deleted the instant the constructor returns — closing the very windows
it just opened. Deleting a window releases its reference, so nothing has to be
unwound by hand and the review cannot outlive everything it owns.

---

## What a paradigm author has to do

**For a GUI that only displays: nothing.** Events, trial data and parameter reads
are all real.

**For a GUI that drives the rig: one guard.** `TwoAFCBehaviorGUI`,
`FirstExperimentBehaviorGUI` and `PumpBehaviorGUI` run their own timer, write
parameters, and hand the trial back by raising `x_TrialComplete_*`. Against a
finished session that would be scoring trials nobody ran. The base class cannot
decide this for a subclass — it does not know which of your methods are display
and which are contingency.

`gui.BehaviorGUI.ReviewMode` is the flag. The rule of thumb: **guard anything
that would still be a mistake if the hardware were switched off.**

```matlab
function tf = rigReady_(obj)
    if obj.ReviewMode
        tf = false;
        return
    end
    ...
end
```

The three example GUIs put it in `rigReady_`, the single gate their trial cycle
already went through, and additionally skip starting the rig timer.
`PumpBehaviorGUI` also skips its blocking `waitForBegin` — a constructor that
blocks would hang the review inside `feval` with a half-built window and no way
to reach the Begin button.

---

## Files with no snapshot

A file saved before this existed still opens. `addControl` and `addButton`
already skip parameters they cannot resolve — the guarantee `epsych.SelfTest`
check I6 rests on — so the data displays work and the control column is simply
absent. `R.IsDegraded` reports it, and the window title says so, because
otherwise missing controls look like a bug rather than a property of the file.

Point it at the protocol to get the controls back:

```matlab
R = epsych.ReviewSession('old_session.mat', Protocol = 'DetectionExample.eprot');
```

A caller-supplied `Protocol=` wins over an embedded snapshot: an operator naming
an `.eprot` is correcting what the file could not say, and should not have to
argue with a stale embedded copy.

---

## What opens

| Artifact | Shape | Notes |
|---|---|---|
| Saved session `.mat` | `Data` [+ `Info`] | The normal case. |
| Crash-recovery `.mat` | `info` + `data_0001..NNNN` | Reassembled on load; carries a snapshot since 2026-08. |
| Trial journal `.epj` | `epsych.TrialJournal.read` | Readable *while a session is running*, so a second MATLAB can watch a run in progress. A torn tail is reported and everything before it is kept. |

---

## Known limits

- **`gui.ElapsedTrialTimer`** measures wall-clock since the last event, so it is
  meaningless in a review. Derive it from `DATA.computerTimestamp` deltas if you
  need it.
- **`gui.SlidingWindowPerformancePlot`** accumulates by `trialIndex`, so scrubbing
  backward leaves stale rows past k rather than clearing them. Fixing it needs a
  `reset` method on that component.
- **The trial table is the one the session started with.** A mid-session
  recompile changes it, and the snapshot records the original — which is the
  honest thing for a review of a recompiled session, but means the
  upcoming-trial display can disagree with the last few trials.
- **Multi-subject sessions** write one file per subject, so a review shows one
  subject. `SubjectIndex=` picks from a hand-built multi-subject file.
- The scrubber commits on **release**, not during the drag: a seek re-notifies
  every display and each recomputes the whole session, which on a long session is
  slower than live scrubbing is useful.

---

## Testing

`tmp/smoke_test_review_session.m` is the standing check — eleven groups, from
snapshot capture through seeking, the transport, a rig-driving GUI standing
down, and the object-lifetime anchor. Run it after any change to the snapshot
format, `hw.Replay`, or `ep_TimerFcn_Start`:

```matlab
matlab -batch "run('c:\src\epsych2\tmp\smoke_test_review_session.m')"
```

Prefer `-batch` over the MATLAB MCP server for this one: its Live Editor figure
manager interferes with GUI teardown, which several of the assertions check.

## See also

- `epsych.SessionSnapshot`, `hw.Replay`, `gui.ReviewTransport`
- [gui_BehaviorGUI.md](../gui/gui_BehaviorGUI.md) — the behavior-GUI contract
- [epsych_TrialJournal.md](epsych_TrialJournal.md) — the `.epj` journal
- [Event_Notifications.md](Event_Notifications.md) — the runtime events a review fires
