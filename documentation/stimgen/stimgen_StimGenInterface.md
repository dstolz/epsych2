# `stimgen.StimGenInterface` and `stimgen.StimGenInterface_Simple`

These two classes are the classic timed playback GUIs for the `stimgen`
package.

Both controllers take one or more `stimgen.StimPlay` objects, write stimulus
buffers into the stimgen RPvds circuit, trigger playback on a timer, and save
presentation-order logs after a run.

## Which interface to use

Use `stimgen.StimGenInterface` when you need:

- multiple named `StimPlay` entries in one session
- the full sidebar with a stimulus list and selectable play modes
- one editor tab per discoverable stimulus class

Use `stimgen.StimGenInterface_Simple` when you need:

- one `StimPlay` object only
- a smaller configuration surface
- the same hardware-triggered playback path without the multi-entry list

## Basic usage

Full interface:

```matlab
sg = stimgen.StimGenInterface(RUNTIME);
```

Simple interface:

```matlab
sg = stimgen.StimGenInterface_Simple(RUNTIME);
```

In both cases, attach calibration with:

```matlab
sg.Calibration = cal;
```

## How the full interface is built

`StimGenInterface.create()` builds three main UI regions.

### Signal plot

The top-left plot shows the currently selected stimulus waveform and is kept
in sync through listeners on each editor stimulus object.

### Stimulus editor tabs

The main tab group is built from `stimgen.StimType.list()`.

For each discoverable class, the interface:

- constructs one editor object
- creates a tab titled with that object's `DisplayName`
- calls the object's `create_gui()` method to populate the tab

This means new stimulus classes can appear automatically if they live in
`obj/+stimgen`, are discoverable by `StimType.list()`, and have a no-argument
constructor.

### Sidebar controls

The right sidebar manages session-level playback state.

Important controls include:

- `Stim Name`
- `ISI`
- `Reps`
- `Add` and `Remove`
- the stimulus tree
- the play mode dropdown
- `Run` and `Pause`

The `File` menu exposes configuration load/save and calibration load.

## Play modes in the full interface

The full interface discovers cross-item selection strategies by scanning the
`@StimGenInterface` folder for `stimselect_*.m` files.

That means the play mode dropdown is effectively extensible by file naming.
The built-in strategies are:

- `Serial`
- `Shuffle`

These functions choose which `StimPlay` entry should be presented next.
Internal selection inside a multi-object `StimPlay` is still handled by the
wrapped `StimPlay` object itself.

## Playback loop

Both interfaces use the same broad sequence.

### Start phase

- reset repetition counts
- clear presentation-order logs
- select the next stimulus entry
- write the first waveform into the inactive hardware buffer
- initialize run timing

### Runtime phase

- wait until the current ISI has elapsed
- log stimulus index, time since start, and current trial number
- toggle the active trigger parameter
- advance the current `StimPlay` object
- choose the next item to present
- write the next waveform into the other buffer

### Stop phase

- save presentation-order data to disk
- restore the run button label

## Hardware buffering

Both classes implement ping-pong buffering through `TrigBufferID` and the
paired hardware parameters:

- `BufferData_0` and `BufferSize_0`
- `BufferData_1` and `BufferSize_1`
- `x_Trigger_0`
- `x_Trigger_1`

The next waveform is prepared in the non-triggered buffer so the hardware is
ready before the next pulse.

The sample rate is taken from `RUNTIME.HW.HW.FS`.

## Timing notes

Both interfaces use a fixed-rate MATLAB timer plus a short busy-wait near the
actual trigger time. The `isiAdjustment` property compensates for timer-call
granularity so the trigger does not happen a cycle late.

That design improves timing consistency, but it can also make the UI feel less
responsive during active playback.

## Saving configurations and logs

Configuration files use the `.sgi` extension.

- The full interface saves a struct named `SGI` containing `StimPlayObjs` and
  `Calibration`.
- The simple interface saves a single `StimPlay` object as `SGO`.

Presentation-order logs are saved as `.mat` files and include fields such as:

- `StimOrder`
- `StimOrderTime`
- `StimOrderTrial`

Calibration files are loaded from `.sgc` files through `set_calibration()`.

## Extension notes

When extending these interfaces, the main seams are:

- `StimType.list()` for what becomes a tab
- `stimselect_*.m` for what becomes a play mode
- `StimPlay` for internal repetition and sweep handling

If a new stimulus class appears in the tab set unexpectedly, check whether it
was added directly under `obj/+stimgen` and whether `StimType.list()` filters
it out.

## Related files

- `obj/+stimgen/@StimGenInterface/StimGenInterface.m`
- `obj/+stimgen/@StimGenInterface/create.m`
- `obj/+stimgen/@StimGenInterface/stimselect_Serial.m`
- `obj/+stimgen/@StimGenInterface/stimselect_Shuffle.m`
- `obj/+stimgen/@StimGenInterface_Simple/StimGenInterface_Simple.m`
- `obj/+stimgen/@StimGenInterface_Simple/create.m`
- `obj/+stimgen/StimPlay.m`