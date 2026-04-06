# eval_staircase_training_mode

`gui.eval_staircase_training_mode` enables or disables per-parameter staircase training from a GUI state-button callback.

It is typically used by parameter-control widgets that need to temporarily suspend randomisation and let trial outcomes drive a single `hw.Parameter` through a `gui.StaircaseTraining` window.

## Call signatures

```matlab
[value, success] = gui.eval_staircase_training_mode(obj, src, event, Parameter)
[value, success] = gui.eval_staircase_training_mode(obj, src, event, Parameter, Name=Value)
```

## Behavior

When `event.Value` is true, the callback:

- Stores the current `Parameter.isRandom` state in `Parameter.UserData.isRandom`.
- Forces `Parameter.isRandom = false`.
- Opens or focuses a `gui.StaircaseTraining` window for the parameter.
- Registers a `NewData` listener on `obj.RUNTIME.HELPER`.

When `event.Value` is false, the callback:

- Restores the saved `Parameter.isRandom` state.
- Deletes the training GUI for that parameter.
- Deletes the corresponding `NewData` listener.
- Re-enables the source UI control when one was provided.

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
