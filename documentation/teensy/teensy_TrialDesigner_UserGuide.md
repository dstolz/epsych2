# Teensy Trial Designer — user guide

Build an operant conditioning paradigm as a state machine, test it against a simulated subject,
and load it onto a Teensy that runs the contingency with sub-millisecond timing.

It opens from the command line, as a standalone window:

```matlab
teensy.TrialDesigner
teensy.TrialDesigner(teensy.Templates.get("GoNoGoDetection"))
```

Pass a `hw.Teensy` interface to enable Upload and Insert Into Protocol:

```matlab
teensy.TrialDesigner(Interface = iface)
```

Pass an `epsych.Runtime` to open in live monitor mode, bound to a running session:

```matlab
teensy.TrialDesigner(runtimeObj)
```

In live monitor mode the designer follows the session: it highlights the state the board is
currently in, and locks its editing controls while the session is in Preview or Record. The
window stays available during a run precisely because watching the state machine is what you
want when a paradigm is behaving oddly mid-experiment.

---

## What this is for

A behavioral trial is a set of rules: *wait three seconds, play a tone, and if the animal pokes
within two seconds give it a pellet — but if it pokes before the tone, abort the trial.* Those
rules have to run somewhere. Running them in MATLAB means every deadline inherits timer jitter.
Baking them into firmware means a new paradigm needs a firmware engineer.

This tool puts the rules in a file. You draw the states, say what leaves each one, and the
designer compiles that into a compact table the Teensy executes on its own clock. Changing the
paradigm is an edit and an upload, not a recompile.

The pieces you work with:

- **Channels** — the things wired to the board. A nose poke, a lick spout, a reward valve, a
  house light, a piezo.
- **States** — the phases of a trial. Inter-trial interval, pre-stimulus delay, stimulus,
  response window, and the outcomes.
- **Transitions** — what moves the animal from one state to the next: an input edge, a
  threshold crossing, a timer running out, a counter reaching a value, a coin flip.
- **Actions** — what happens on the way: open a valve, pulse a sync line, record a response
  code, mark the response latency.
- **Variables** — the numbers you want to change between trials without redrawing anything.

---

## The one rule that catches everybody

**Transitions are tested in order, and the first one that matches wins.**

In a response window with two transitions — "poke rises → Hit" and "state timer → Miss" — the
order decides what happens when the animal pokes on the very last tick of the window. Put the
poke first and it counts as a hit. Put the timer first and the same behavior scores as a miss.

The transition table numbers its rows for exactly this reason, and the `^` and `v` buttons
reorder them. When you cannot explain why a paradigm scores something oddly, look at the order
before you look at anything else.

---

## A worked example, start to finish

### 1. Start from a template

`File > New From Template...`, choose **Go / No-Go detection**.

Templates are complete working paradigms, not skeletons. Starting from one and editing is far
more reliable than assembling a state machine from an empty canvas, and every duration in them
is already exposed as a variable.

The **States** tab now shows ten states, laid out left to right by how far they are from the
start. `ITI` has a `>` marker in the list because trials begin there; the outcome states carry
a `*` because they end the trial.

### 2. Point the channels at your box

On the **Channels** tab, the six default channels are a generic operant box. Select `Poke` and
use the inspector on the right:

- Rename it to whatever your rig calls it. **The rename cascades**: every condition that reads
  that channel is rewritten, so nothing breaks.
- Set the pin from the **Pin** dropdown. It lists only pins the board can actually use for that
  kind of channel, and marks the ones another channel already claims.
- Set **DebounceMs**. A mechanical switch needs 5–20 ms; an optical beam break can use 1 ms.
- Clear **ActiveHigh** if your switch pulls the pin low when the animal is in the port, and set
  **PullMode** to `PullUp`. A floating input reads as noise.

For an analog channel such as the piezo, set **ThresholdHigh** and **ThresholdLow** in
engineering units. The two thresholds give you hysteresis: the input trips at the high value
and only releases at the low one, so a sensor sitting right at the threshold does not emit a
burst of spurious events.

If a board is connected, the **Live I/O** panel drives the selected output directly — the
fastest way to confirm you wired the valve to the pin you think you did.

### 3. Read the paradigm on the diagram

The center pane draws the state machine. Terminal states are outlined twice and filled with
their outcome colour: green for a hit, red for a miss, orange for a false alarm, blue for a
correct reject — the same colour language `gui.History` uses during a session.

Arrows are labelled with their condition in plain English. Drag a node to move it;
`View > Auto Layout Diagram` puts everything back in depth order.

### 4. Add a variable

Say you want to shorten the response window as training progresses.

`GoNoGoDetection` already exposes `RespWinDur`, so select the `RespWindow` state and look at
its **Duration** row: the dropdown beside it reads `RespWinDur` rather than `literal`, which
means the duration follows the variable.

To do this for a state that does not have it yet, pick the variable from that dropdown. The
numeric field greys out, and the program stores an `@RespWinDur` reference instead of a number.

On the **Variables** tab, leave **Per Trial** checked. That is what turns the variable into a
trial-table column in the Protocol Designer, so a protocol can step it from trial to trial.
The lower table previews every `hw.Parameter` this program will create, and the **Where used**
list shows everywhere the selected variable is referenced — click a row to jump to that state.

### 5. Test it before an animal sees it

The **Test Bench** tab is a virtual box. Press **Start** and the trial runs; each digital input
gets a button you can press mid-trial, each analog input gets a slider, and each output gets a
lamp that follows the simulation.

The timeline shows the state occupancy band along the top with the input and output traces
beneath, on a shared millisecond axis. The **Outcome** panel decodes the response code once the
trial ends.

Then use **Monte Carlo**. Pick a simulated subject — `guessing` responds half the time
regardless of the stimulus, `impulsive` responds far too early, `sluggish` responds late — set a
few hundred trials, and run it.

A progress dialog tracks the run and carries a **Stop** button. Pressing it ends the run after
the trial in flight, and the summary table still fills in — computed over the trials that
actually ran, with the status bar reporting how many those were. Useful when a long run is
obviously going nowhere, or when a paradigm bug makes every trial burn its full safety timeout.

This is the check that finds paradigms which are valid but behaviorally broken: a response
window that closes before the animal could physically reach the port, an outcome state nothing
can ever reach, a contingency where every trial aborts. Validation cannot see any of that. A few
hundred simulated trials can.

A useful sanity check: run a `guessing` subject against a detection task and confirm d′ comes
out near zero. A subject that ignores the stimulus should be unable to discriminate. If it
scores well above zero, something in the paradigm is leaking the answer.

### 6. Compile

`Program > Compile`, or the **Compile** button.

The **Compile & Upload** tab shows the validation report, tinted by severity. Errors block
compilation; warnings and notes do not. Select a row and press **Go To Issue** to jump straight
to the state, channel or variable it is about.

Below that: the wire program that would be sent, and a capacity table showing how much of each
fixed firmware array the program uses. States, transitions per state, condition tokens and
evaluator depth are all bounded, and the table tints amber past 80% and red at the limit.

### 7. Upload and insert into a protocol

**Upload to Board** sends the program over USB serial. Every record is acknowledged
individually, so a rejection names the exact record that failed rather than just failing.

**Insert Into Protocol...** creates this program's parameters on a Teensy interface in an open
Protocol Designer. That parameter set includes everything the runtime and the shipped GUIs
expect:

| Parameter | Why it exists |
|---|---|
| `x_NewTrial_<BoxID>`, `x_ResetTrig_<BoxID>` | The triggers `epsych.Runtime` pulses each trial |
| `x_TrialComplete_<BoxID>` | Polled every 10 ms tick to detect the end of a trial |
| `RespCode` | The outcome bitmask `psychophysics.Detection` and `gui.History` read |
| `RespLatency` | Milliseconds from trial start to the Mark Latency action |
| `TrialType` | The integer trial type `psychophysics.Detection` reads separately |
| `_TrigState~<BoxID>`, `_TrialNum~<BoxID>` | The exact names `gui.OnlinePlot` looks up |
| one per variable | Becomes a trial-table column when Per Trial is set |
| one per input and counter | Latched sensor state captured into each trial's saved data |

If the open protocol has no Teensy interface yet, add one first with
`Interface > Add Interface` in the Protocol Designer.

---

## Building a paradigm from scratch

1. **Channels first.** Everything else refers to them by name.
2. **Add the states** you need, then set one as the start with **Set as Start**.
3. **Mark the outcomes terminal** with **Toggle End**, and give each one its response bits with
   **Edit...** next to *Response*. A terminal state with no bits reports `Undefined`, which is
   almost never what you meant — validation warns about it.
4. **Wire the transitions.** Select a state, press **+ Add** under the transition table, and the
   transition editor opens.
5. **Add actions.** Entry actions run as the state is entered, exit actions as it is left, and a
   transition can carry its own actions that run in between.
6. **Validate early and often.**

### The condition builder

Every transition opens the same builder. In *single condition* mode you pick what to test and
the fields change to match:

| Test | What it means |
|---|---|
| the state timer runs out | Fires once the state has run for its duration |
| an input changes (edge) | Fires on the rising or falling edge — a discrete event |
| an input is held at a level | Fires while the input sits at a level, optionally for N ms |
| an analog input crosses a threshold | Above/Below test the level; CrossUp/CrossDown fire once |
| a counter reaches a value | Compare a counter against a number, e.g. five licks |
| a global timer expires | A timer that runs independently of the state timer |
| a random draw (probability) | Take this branch with probability *p* |

Edge versus level matters. "Poke rises" fires once when the animal enters the port. "Poke is
high" is true the entire time it stays there, so a state whose only exit is a level condition
fires immediately on re-entry if the animal never left.

Switch to *all of several* or *any of several* to combine conditions. Each row can itself be a
combination, so nesting works, bounded by the firmware evaluator's stack depth.

### Probability branches are how you randomize on-device

`GoNoGoDetection` splits signal from catch trials with a probability transition reading
`@P_Catch`. That is deliberate: set `P_Catch` to 0 from the trial table and every trial is a
signal trial; set it to 1 and every trial is a catch trial; leave it at 0.3 and the board
randomizes. One mechanism covers both host-driven and device-driven randomization.

---

## Templates

| Template | What it is |
|---|---|
| Blank | One state and the default channels. Start from scratch. |
| Go / No-Go detection | Signal and catch trials scored hit / miss / correct reject / false alarm, with aborts |
| Two-alternative forced choice | Center initiation, then a left or right choice |
| Fixed ratio | N responses deliver a reward, using a counter |
| Progressive ratio | Like fixed ratio, with the requirement raised between trials by the host |
| Nose-poke shaping | Autoshaping: any poke pays, plus free rewards for a naive animal |
| Appetitive detection (Caras Lab) | Platform-hold detection with pellet reward |
| Passive exposure | No contingency; a cue and a sync pulse on a fixed interval |

**Appetitive detection** is worth calling out: its channels, variables and states use the same
names as `cl_AppetitiveDetection_BoxGUI` — `Platform`, `Trough`, `DelayPeriod`, `RespWindow`,
`PelletTotal`, `StimDelay`, `RespWinDelay`, `ITIDur`, `TimeoutDur`, `NumPellets` — so a
Teensy-backed protocol lights up that existing box GUI with no edits to it.

`DelayPeriod` and `RespWindow` in that template are digital *outputs* held high for the duration
of their phase. That is a useful trick generally: an output driven purely as a phase flag becomes
a readable parameter, which `gui.Parameter_Monitor` renders as a lamp and a scope can trigger on.

**Progressive ratio** deliberately does not escalate on the board. The requirement is an
ordinary per-trial variable, so a trial table, a `psychophysics.Staircase` or a custom
`epsych.TrialSelector` raises it after each rewarded trial. The board owns the within-trial
contingency and the host owns the across-trial schedule, which is how the rest of EPsych already
divides the work — putting the schedule in both places is how the two drift apart.

```matlab
disp(teensy.Templates.list())
p = teensy.Templates.get("TwoAlternativeForcedChoice");
```

---

## Files

Programs save as `.etsm`, a MAT-file holding one struct. `File > Save As...` also writes `.json`
if you want to diff or hand-edit one.

Because the format round-trips exactly, undo is exact too: `Edit > Undo` restores a snapshot
rather than replaying an inverse operation, so it cannot drift from what was on screen. The Undo
menu item names what it would undo.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Ctrl+N / Ctrl+O / Ctrl+S | New / Open / Save |
| Ctrl+Shift+S | Save As |
| Ctrl+Z / Ctrl+Y | Undo / Redo |
| Ctrl+I | Edit program information |
| Ctrl+L | Auto-layout the diagram |

---

## When something is wrong

**"No terminal state is reachable, so a trial can never complete."** Nothing on the diagram can
be reached from the start state that ends the trial. Usually a missing transition, or a start
state that was never set.

**"This state has no way out."** The state has no duration and no transition to another state,
and is not terminal, so the machine would sit in it forever.

**A terminal state warns about response bits.** It will report `Undefined`, and every analysis
downstream keys off `RespCode`. Give it the bits you mean.

**A capacity row is red.** The program is larger than the firmware's fixed arrays. Simplify it,
or raise the limit in both `firmware/EPsychTeensy/Config.h` and `teensy.Compiler.LIMITS` — they
must agree.

**The trial does not behave as you expect in the test bench.** Check the transition order first.
Then check edge versus level. Then watch the state band on the timeline to see where it actually
went.

---

## See also

- [Program model reference](teensy_Program_Model.md) — the classes behind the GUI
- [Wire protocol](../hw/hw_Teensy_Program_Protocol.md) — what the board receives
- [hw.Teensy](../hw/hw_Teensy.md) — the hardware backend
- [epsych.BitMask](../epsych/epsych_BitMask.md) — response-code encoding
- [Protocol Designer user guide](../design/ProtocolDesigner_UserGuide.md) — building the protocol this plugs into
