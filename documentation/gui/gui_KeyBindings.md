# gui.KeyBindings

The keyboard-command processor for a behavior GUI. A MATLAB figure has exactly
**one** `WindowKeyPressFcn` slot, so every component that wanted a key used to
claim it and silently take it from whoever claimed it first. This class owns
both key slots for the GUI's figure and hands out bindings instead, so a
paradigm's arrow keys, the Update button's modifier readout, and the
Regenerate button's arming gesture all coexist without knowing about each
other.

Source: `obj/+gui/@KeyBindings/`

## What it does

- **Owns the figure's key callbacks.** `gui.BehaviorGUI` constructs one before
  `build` and re-claims the slot after it, so a component that assigned the
  callback during `build` is chained rather than thrown away. A chained
  handler sees every key this object does not answer — modifier presses
  included, since a legacy handler tracks held modifiers from exactly those —
  and is called with the figure as its source, as MATLAB itself would.
- **One per figure.** The constructor registers the instance on its figure,
  and `gui.KeyBindings.getOrCreate(fig)` returns it (creating one when the
  figure has none). A component constructed without a `KeySource` joins the
  figure's dispatcher this way instead of claiming the callback slot for
  itself: two components that each claimed and chained the slot could end up
  chained to each other, recursing on every unbound keystroke.
- **Dispatches chords.** `bind('ctrl+r', @() ...)` is answered when exactly
  that chord arrives. `Ctrl+Shift+R` is a *different* command and does not
  fire `Ctrl+R`.
- **Publishes modifier state.** `CurrentModifiers` and the `ModifiersChanged`
  event are what `gui.components.Parameter_Update` and `gui.components.RegenerateTrial` read to see
  a held Ctrl+Alt+Shift, instead of installing hooks of their own.
- **Lists itself.** `Ctrl+Shift+?` or `F1` opens `showHelp`, the only place an
  operator can see what a paradigm bound.

Bindings are **code, not operator preference**: nothing here is persisted and
there is no rebinding UI. What a paradigm binds is what the rig does.

## Usage

From a `gui.BehaviorGUI` subclass's `build`:

```matlab
obj.Keys.bind('leftarrow', @() obj.respondSide(0), ...
    Description = 'Respond LEFT', Group = 'Subject response');
```

Standalone, over any figure:

```matlab
kb = gui.KeyBindings(fig);
kb.bind('ctrl+r', @() refresh(), Description = 'Refresh');
```

| `bind` option | Default | Meaning |
|---|---|---|
| `Description` | `''` | Text shown in the shortcut list |
| `Group` | owner's class name, else `General` | Section of the shortcut list |
| `Owner` | `[]` | Component handle; the binding is dropped once it is deleted |
| `EnableInReview` | `false` | Fire during an `epsych.ReviewSession` too |
| `Replace` | `false` | Overwrite an existing binding instead of erroring |

Chords are case-insensitive and `+`-joined, in any modifier order:
`Ctrl+Shift+R`, `shift+ctrl+r`, and `control+shift+r` are one binding.
`command`/`cmd` mean `ctrl`, `option` means `alt`, `?` and `/` are both
`slash`, `enter` is `return`, and `numpad3` answers as `3` — following what
`epsych.RunExpt` and `epsych.ProtocolDesigner` already special-cased.

Helpers that come with a default chord take `KeyBinding=`:

| Helper | Default chord | Action |
|---|---|---|
| `addUpdateButton` | `Ctrl+Enter` | Commit pending parameter edits |
| `addScreenCapture` | `Ctrl+Shift+C` | Copy the window to the clipboard |
| `addNotes` / `addNotesButton` | `Ctrl+Shift+N` | Jump to the notes entry |

`KeyBinding='none'` drops one; any other chord replaces it. `addSessionGate`,
`addSyringePump`, `addRegenerateTrial` and the trigger helpers deliberately
have none — see below.

## Why it is built this way

- **It owns the callback slot rather than using `addlistener`.** Figure key
  events *can* be taken with a listener, and listeners compose — but that is
  the anarchy being removed: the `Fcn` slots would stay a live clobber
  surface, and ordering among listeners is unspecified. Owning the slot is
  also what lets this class *notice* a foreign claim and chain it politely.
- **A duplicate chord is an error, not a warning.** Bindings are written in
  code, so a collision is a paradigm bug; failing at the first run beats
  leaving one of the two commands quietly dead. `Replace=true` is the
  deliberate override.
- **Bindings are suppressed in a review by default.** A review replays a
  finished session, and a binding that writes to hardware must not fire even
  if its component forgot to check. `EnableInReview=true` opts a read-only
  command back in — as the help list itself does.
- **A modifier keypress is state, never a chord.** A bare Ctrl press updates
  `CurrentModifiers` and looks up nothing, or holding Ctrl to arm something
  would also fire whatever `ctrl` was bound to.
- **No chord for the hardware-risky helpers.** `gui.components.SessionGate` starts the
  session dispatching trials, `gui.components.SyringePump` moves a syringe, and
  `gui.components.RegenerateTrial` interrupts the trial in progress — its
  hold-Ctrl+Alt+Shift gesture *is* its key handling, and a chord that fired it
  outright would undo the arming it exists to impose. Bind one by hand if a
  rig wants it.
- **A dead owner takes its binding with it.** `Owner=` means a chord is never
  answered by a component that has been torn down.
- **A failing binding is logged, not propagated.** Same reasoning as every
  other callback in this toolbox: one broken command must not take the
  keyboard down with it.

## Two limits, neither fixable here

- **Edit fields swallow keys.** A uifigure delivers no window key event while
  an edit field or text area has focus. This is also a feature: it is what
  stops a shortcut firing while the operator types a note. A shortcut that
  seems dead is usually a focused text field — click the background first.
- **A modifier released elsewhere is not reported.** Let go of Ctrl while
  another window has focus and this object still believes it is held; the set
  corrects itself at the next keystroke in the window. The hook-based
  predecessor had the same limitation.

## Validation

`tmp/smoke_test_keybindings.m` (headless;
`matlab -batch "run('tmp/smoke_test_keybindings.m')"`) — asserts chord
normalization and its aliases, exact-chord dispatch, the duplicate policy,
review suppression and its opt-in, modifier tracking across press and release,
owner pruning, foreign-handler chaining (including one that throws), and
teardown that restores the figure without stepping on a neighbour. Group 11
builds a real `gui.BehaviorGUI` whose `build` binds an arrow key *before*
calling `addUpdateButton`, which is the arrangement that used to leave the
binding dead.

## See also

- [gui_BehaviorGUI.md](gui_BehaviorGUI.md) — the `Keys` property and the `add*` helpers
- [Parameter_Update.md](Parameter_Update.md) — reads modifier state from here
- [gui_RegenerateTrial.md](gui_RegenerateTrial.md) — the arming gesture, and the standalone fallback
- `obj/+gui/@KeyBindings/`, `examples/two_afc/TwoAFCBehaviorGUI.m`
