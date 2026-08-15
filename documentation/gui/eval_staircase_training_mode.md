# eval_staircase_training_mode

`gui.eval_staircase_training_mode` enables or disables per-parameter staircase training from a GUI toggle callback.

It is typically used by parameter-control widgets that need to temporarily suspend randomisation and let trial outcomes drive a single `hw.Parameter` through a `gui.StaircaseTraining` window.

## Wiring it to a state button or to a parameter

Either a state `uibutton`'s `ValueChangedFcn` or the `PostUpdateFcn` of a `gui.Parameter_Control` checkbox works — both receive an `event` carrying `.Value`.

Prefer the checkbox. A state button's state lives only in the widget, so nothing records it and a saved phase cannot restore it; a checkbox bound to a Boolean `hw.Parameter` marked `PersistWithPhase` makes the training state part of the stage's configuration (see `documentation/hw/hw_Parameter.md`). `cl_AppetitiveDetection_BehaviorGUI` does this with `StimDelayTrainingEnabled`.

Pass `[]` as `src` when the toggle itself is the control: a non-empty `src` is *disabled* while training runs, which for the toggle would leave the operator no way to switch training back off.

Bound to a parameter, the callback also runs for **external** writes — `gui.Parameter_Control` invokes `PostUpdateFcn` on the parameter's `PostSet`, which is what lets a phase load open or close the training window. It is therefore idempotent in both directions: a repeated enable does not re-snapshot over the suspended values, and a disable with no preceding enable returns without trying to restore a snapshot that was never taken. The map entry in `StaircaseTrainingGUIs` is the record of which state is in effect.

## Call signatures

```matlab
[value, success] = gui.eval_staircase_training_mode(obj, src, event, Parameter)
[value, success] = gui.eval_staircase_training_mode(obj, src, event, Parameter, Name=Value)
```

## Behavior

When `event.Value` is true, the callback:

- Stores the current `Parameter.isRandom` state in `Parameter.UserData.STAIRCASE.isRandom`, and suspends `RepeatDelayOnAbort` the same way — **only** when training was not already on.
- Forces `Parameter.isRandom = false`.
- Opens or focuses a `gui.StaircaseTraining` window for the parameter.
- Registers a `NewData` listener on `obj.RUNTIME.EVENTS`.

When `event.Value` is false, the callback:

- Returns immediately when training was never switched on, since there is no snapshot to restore.
- Restores the saved `Parameter.isRandom` and `RepeatDelayOnAbort` states.
- Deletes the training GUI for that parameter.
- Deletes the corresponding `NewData` listener.
- Re-enables the source UI control when one was provided.

`RepeatDelayOnAbort` is resolved through `RUNTIME.find_parameter`, not the `RUNTIME.P` cache: that cache is only populated once `TRIALS` is initialized, and the toggle can now be written before a session has dispatched its first trial. A protocol that does not define the parameter simply has nothing to suspend.

## Response mapping

The listener decodes the most recent trial response code with `epsych.BitMask.decode` and applies one step when the decoded response matches either configured outcome:

- `StepUpResponse` triggers `h.updateParameter("up")`
- `StepDownResponse` triggers `h.updateParameter("down")`

Supported response names are:

- `"Hit"`
- `"Miss"`
- `"CorrectReject"`
- `"FalseAlarm"`
- `"Abort"`

The legacy spelling `"CorrectRejct"` is accepted and normalized to `"CorrectReject"`.

## Name-value options

These options are accepted by `gui.eval_staircase_training_mode`:

- `MinValue`, `MaxValue`
- `StepUp`, `StepDown`
- `StepUpLimits`, `StepDownLimits`
- `MinValueLimits`, `MaxValueLimits`
- `StepUpResponse`, `StepDownResponse`

The staircase value and limit options are forwarded to `gui.StaircaseTraining`.
The response-mapping options `StepUpResponse` and `StepDownResponse` are retained by `gui.eval_staircase_training_mode` and passed only to the `NewData` listener callback; they are not constructor arguments for `gui.StaircaseTraining`.

## Runtime requirements

`obj` must expose the following members:

- `RUNTIME`
- `StaircaseTrainingGUIs`
- `StaircaseTrainingListeners`

The callback stores GUI handles and listeners in those maps using `Parameter.Name` as the key.

## Hardware-backed parameters

For parameters whose parent is not `hw.Software`, the listener also writes the updated parameter value into the pending trial table:

- Source table: `RUNTIME.TRIALS.trials`
- Lookup map: `RUNTIME.TRIALS.writeParamIdx`

This keeps the trial record aligned with the value that was applied after the response.

## Related documentation

- See `documentation/gui/StaircaseTraining.md` for the training-window UI and stepping rules.
- See `obj/+gui/@StaircaseTraining/StaircaseTraining.m` for the class implementation.
