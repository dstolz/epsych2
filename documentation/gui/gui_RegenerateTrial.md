# gui.RegenerateTrial

A button that re-arms the trial the rig is holding. One press dispatches the
pending trial again, from the top: randomized parameters draw fresh values,
expressions are re-evaluated against whatever the operator has since
committed, and the hardware is reset and re-triggered.

The button is **dead until Ctrl+Alt+Shift are all held down**.

Source: `obj/+gui/@RegenerateTrial/`

## Arming: hold Ctrl+Alt+Shift

The button is greyed and inert until all three modifiers are held, goes live
while they are, and goes dead again the moment any one of them is released.
A regeneration therefore takes a two-handed gesture and a click — not
something a sleeve, a stray elbow, or a mis-aimed click at the neighbouring
trigger button can do.

That combination is not arbitrary: `gui.Parameter_Update` already uses
Ctrl+Alt+Shift *held while clicking* to mean "commit now, skip the deferral",
so an operator on an EPsych rig has met this gesture before.

The gate is checked in two places, and the second is the one that matters:
the button's `Enable` state is convenience and feedback, while `regenerate`
re-checks `Armed` itself before doing anything. A script, a keyboard
shortcut, or a stale enable state cannot get past it — it fails closed.

`RequireArming=false` removes the requirement and leaves an ordinary button
that regenerates on a single click.

**One limitation worth knowing.** Arming is tracked from the figure's key
events, so if the window loses focus while the keys are held — alt-tab, with
alt being one of the three — the release may never arrive and the button can
be left armed. It still takes a deliberate click to do anything, and the
press is still logged and noted, but do not treat arming as a substitute for
attention. This is the same exposure `gui.Parameter_Update` has always had
with the same gesture.

## ⚠️ It interrupts the trial in progress

**Once armed, this component assumes the operator knows what they are doing,
and asks for no confirmation.** There is no dialog, no "are you sure", and no
undo. Read this section before putting the button in a GUI.

The button has no way to tell a rig sitting in an intertrial interval from
one with an animal part way through a response. `ResetTrig` and the
`NewTrial` trigger go out either way, so a press mid-trial:

- **restarts the trial under the subject** — the delay period and response
  window begin again, and whatever the animal was doing is discarded by the
  hardware along with the state the reset clears;
- **rewrites the trial's record.** The `DATA` record is assembled from the
  parameter values when the trial completes, so a regenerated trial is
  recorded with the values from the **last** dispatch. If the first
  presentation differed — and redrawing a randomized parameter is the usual
  reason to press the button — the record no longer describes what the
  subject first heard;
- **leaves no trace in the trial data.** The trial counter does not move: the
  regenerated trial is still one trial and still one record, which is
  deliberate (a session must not count trials the subject never saw) but
  means nothing downstream can see that it happened.

The session notes are what carry it. Every press is logged at level 1 and
written into `RUNTIME.NOTES` tagged with the box, so it reaches the data file
through the `Info` variable every saving function writes. `Note=false` turns
that off; there is then no record of the intervention anywhere but the log.

Because of all this, the button paints itself amber rather than the neutral
grey of the controls around it, and it is **not** on the `gui.BehaviorBuilder`
palette — that builder exists for operators assembling a GUI without writing
code, which is exactly who should not be given this button by accident.

## What it does

- **Re-dispatches the pending trial** by calling
  `epsych.Runtime.dispatchNextTrial`, the same call the trial loop makes at
  every trial boundary: fire `ResetTrig`, write every per-trial parameter in
  dependency order, fire `NewTrial`, broadcast the `NewTrial` event.
- **Redraws randomized parameters.** `hw.Parameter.set.Value` re-randomizes
  an `isRandom` parameter and re-evaluates an `Expression` on every
  assignment, so a stimulus delay or ITI that came out wrong gets another
  draw without waiting for the next trial.
- **Applies committed edits immediately.** A parameter the operator changed
  mid-trial normally reaches the hardware at the next dispatch; this is that
  dispatch, now.
- **Leaves the trial counter alone.** `TrialIndex` does not advance and no
  `DATA` record is written by the press itself.
- **Stays dead unless a session is running.** Preview and Record make it
  available, everything else disables it, and a review never enables it at
  all. Running is necessary but not sufficient — the hold is the other half.
- **Fires `TrialRegenerated`** after a successful press, and
  `ArmedStateChanged` when the hold is taken up or let go, for a paradigm
  that wants to mark the trial or reflect the arming in a display of its own.

## What it deliberately does not do

**It does not re-run the trial selector.** Selecting is where a paradigm's
state moves: a staircase steps, a catch hazard climbs, a queued one-shot
request is consumed. Re-running the selector to redraw a delay value would
silently advance the schedule.

`Reselect=true` asks for a selector pass as well, for a paradigm whose
selector is where the trial's values are actually made. It is safe only
because every `epsych.TrialSelector` must already tolerate being called more
than once for one trial — any control that sets `FORCE_TRIAL` brings the
selection round again — but it does move whatever that selector moves. The
default is off.

## Usage

Through `gui.BehaviorGUI`, which registers it for teardown:

```matlab
function build(obj, fig)
    g = uigridlayout(fig, [2 1]);
    obj.addRegenerateTrial(g);
end
```

Standalone, in any container:

```matlab
h = gui.RegenerateTrial(RUNTIME, panel, SubjectIndex=2);
h.regenerate();     % the button's own callback; returns whether it went out
```

One button drives one box. A multi-box rig wants one per box, each with its
own `SubjectIndex`.

## Options

| Option | Default | Meaning |
|---|---|---|
| `Text` | `'Regenerate Trial'` | Button label. |
| `Tooltip` | the warning | Hover text. Empty keeps the default, which states the risk in full — this is the one component whose whole hazard is invisible from its label. |
| `SubjectIndex` | `1` | Which box to regenerate. |
| `Reselect` | `false` | Also re-run the trial selector. See above. |
| `Note` | `true` | Record each press in the session notes. |
| `EnableWhenIdle` | `false` | Leave the button live outside a run. |
| `RequireArming` | `true` | Require the Ctrl+Alt+Shift hold. |
| `ShowIcon` | `true` | Draw the circular-arrow glyph. |
| `FontSize`, `FontWeight`, `BackgroundColor` | `12`, `normal`, amber | Appearance. `BackgroundColor` is the *armed* colour; unarmed shows a washed-out version of it, so the button reads as "not available yet" rather than broken. |

## When it will not run

Everything that can stop a press is logged and returns `false` rather than
throwing — this runs from a button callback beside a live experiment, where
an error dialog over the session window is worse than a log line:

| Condition | Behavior |
|---|---|
| Ctrl+Alt+Shift not held | Button disabled; `regenerate` refuses and logs. |
| Session is in `ReviewMode` | Button permanently disabled; `regenerate` refuses. A review replays a finished session and must not write to hardware. |
| No runtime, or a deleted one | Button inert; `regenerate` returns `false`. |
| No compiled trials | `false`, logged. |
| `SubjectIndex` past the number of boxes | `false`, logged. |
| No trial selected yet | `false`, logged — there is nothing to regenerate before the first selection. |
| Dispatch throws part way | `false`, logged as a **partly written trial**: `ResetTrig` has already fired and some parameters are written, so the box is in neither the old trial nor the new one. |

## Why it follows the run mode rather than reading it

`gui.BehaviorGUI` is built from the PsychTimer's `StartFcn`, which runs
*before* `epsych.RunExpt.PsychTimerStart` broadcasts the run mode. A button
that seated its enable state at construction would seat it as `Idle` and stay
there for the whole session, so the component listens for `ModeChange`
instead. `EnableWhenIdle=true` is for a runtime that never broadcasts one —
a script, a headless test, a demo.

Preview is enabled alongside Record because it is a distinct `hw.DeviceState`
and is not `isIdle`: a preview dispatches trials like any other run.

## Sharing the key callbacks

**Inside a `gui.BehaviorGUI` this is settled for you.** `addRegenerateTrial`
passes the GUI's [`gui.KeyBindings`](gui_KeyBindings.md) as `KeySource`, and
the component then takes the held modifiers from its `ModifiersChanged` event.
No figure callback is touched, nothing needs re-installing, and the order
`build` happens to create the Update button in no longer decides which
component sees the key.

**Standalone** — a component built into a window with no behavior GUI around
it — is still supported and still tested, and it works the same way: with no
`KeySource` the constructor joins (or starts) the figure's shared
`gui.KeyBindings` (`gui.KeyBindings.getOrCreate`) and listens to that. The
component never assigns a figure key callback itself. It used to: each
standalone component claimed the slot and chained what it displaced, and two
such components on one figure could end up chained to *each other*, recursing
to MATLAB's recursion limit on every stray keystroke. One shared dispatcher
per figure makes that impossible — a multi-box rig's several buttons all
listen to the same one.

Two things keep the gate working beside a neighbour that still assigns the
figure callbacks outright:

- **The shared dispatcher chains.** `gui.KeyBindings` keeps whatever callback
  it displaced and calls it for every key it does not answer — modifier
  presses included, since a legacy handler tracks held modifiers from exactly
  those. The chained call is wrapped in `try`/`catch`: a neighbour that
  throws must not take the safety gate down with it.
- **A self-resolved KeySource is re-claimed on the first `ModeChange`.**
  `epsych.RunExpt` broadcasts the run mode only once the whole GUI has been
  built, which makes that the first moment every component has had its turn
  at the slot. `claimFigure` takes it back there, chaining onto whoever ended
  up holding it. A `KeySource` handed in is left alone — whoever supplied it
  owns that policy (`gui.BehaviorGUI` re-claims after `build` itself).

## Verification

`tmp/smoke_test_regenerate_trial.m` is the standing check — software-only, no
hardware. It covers the mode gating, that a regeneration re-dispatches
without advancing the trial counter, that randomized parameters actually
redraw, the session-note record, `Reselect` on and off (counted through
`epsych.DefaultTrialSelector.TrialCount`), the review refusal, and each of
the degraded cases above.

The arming groups drive the figure's own installed callbacks rather than a
private method, so they exercise the shared dispatcher and its chain as
built: that two of the three modifiers do not arm, that releasing one
disarms, that a handler already on the figure keeps receiving events, that
arming survives a neighbour assigning the figure callbacks outright after
`build` (re-claimed on `ModeChange`, with the neighbour chained), that a
chained handler which throws breaks neither arming nor disarming, and that
two standalone buttons on one figure share one dispatcher without recursing.

## See also

- [gui_BehaviorGUI.md](gui_BehaviorGUI.md) — `addRegenerateTrial` and the rest
  of the component helpers
- [gui_Notes.md](gui_Notes.md) — where the record of each press goes
- `epsych.Runtime.dispatchNextTrial`, `epsych.TrialSelector`
