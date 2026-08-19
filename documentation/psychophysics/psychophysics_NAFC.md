# psychophysics.NAFC

N-alternative forced choice analysis with customizable plotting.

Source: `obj/+psychophysics/@NAFC/`

`NAFC` scores tasks in which the subject must pick one of N alternatives on
every trial — 2AFC side discriminations, 4AFC spatial tasks, odd-one-out
paradigms. Where the detection classes ask "did the subject respond?", this
one asks "which alternative did they pick, and was it the right one?" — so
its outputs are choice functions, a proportion correct against a 1/N chance
level, and a confusion matrix, rather than hit and false alarm rates.

It is a `psychophysics.Psych` subclass, so it works both ways:

```matlab
A = psychophysics.NAFC(RUNTIME, Parameter);    % online: follows NewData
A = psychophysics.NAFC(Data, 'SignedContrast'); % offline: a saved DATA struct array
```

The 2AFC tutorial (`examples/two_afc`) embeds one in its behavior GUI: see
`TwoAFCBehaviorGUI.createPsych` for the online wiring and the "Choices by
Signed Contrast" panel for the plot.

## Where the per-trial facts come from

Each trial needs three things; all have a default route and an override:

| Fact | Default route | Override |
|------|---------------|----------|
| Chosen alternative | `Choice_0`..`Choice_5` bits decoded from `RespCode` | `ChoiceField` names a DATA field holding the 0-based choice; negative = no answer |
| Correct alternative | the `TrialType` DATA field (the `examples/two_afc` convention) | `CorrectField` names another field; with no such field, `TrialType_*` bits from `RespCode` |
| Stimulus value | the tracked `Parameter`, as in every `psychophysics.Psych` | may be empty — session totals and the confusion matrix need no value, only the by-value curves do |

The `Choice_*` bits stop at 6 alternatives; a `ChoiceField` supports any N.
A trial with no choice recorded is an abort; correctness is
`choice == correct`, never re-derived from outcome bits.

## NumAlternatives

`NumAlternatives = 0` (the default) auto-detects N as the largest
alternative the data mentions plus one, never fewer than 2. A fixed value
`>= 2` pins N — and then a trial mentioning an alternative outside
`0..N-1` is counted in `Results.NumInvalid` and dropped, rather than
silently growing N and rescaling the chance level a fixed-N analysis was
asked for.

## Results

`Results` is recomputed on every refresh (each `NewData` event online):

| Field | Meaning |
|-------|---------|
| `NumAlternatives`, `ChanceLevel` | N and 1/N |
| `NumTrials`, `NumAnswered`, `NumAborted`, `NumInvalid`, `AbortRate` | session counts over included trials |
| `PercentCorrect` | fraction correct over answered trials with a known correct alternative |
| `Choice`, `CorrectAlternative`, `IsCorrect`, `Included` | per-trial vectors (`NaN` = no answer / unscored) |
| `ChoiceTotals`, `ChoiceProportion`, `ChoiceBias` | per-alternative totals; bias is proportion − 1/N |
| `ConfusionCount`, `ConfusionRate` | N×N, rows = correct alternative, columns = chosen; rates are row-normalized |
| `Values`, `NumByValue` | unique tracked-parameter values with an answer, and answered counts |
| `CorrectRate`, `CorrectCount` | proportion correct per value |
| `ChoiceRate`, `ChoiceCount` | N×V: P(chose k) per value — for a 2AFC over a signed stimulus, the psychometric choice functions |

`ExcludedTrials` (inherited) drops trials from every statistic.

## Plotting

Plotting is optional, and the plot redraws itself on every refresh:

```matlab
A.Plot();                          % own window
A.Plot(ax, PlotType="confusion");  % embed in an existing axes
A.PlotType = "performance";        % a live plot switches immediately
```

Three `PlotType`s, switchable from the plot's right-click menu:

- `"choice"` (default) — one curve per alternative: P(chose k) against the
  tracked value, with the 1/N chance line.
- `"performance"` — proportion correct against the tracked value.
- `"confusion"` — the confusion matrix as a heatmap, row-normalized color
  with raw counts in the cells; never-presented alternatives render
  transparent rather than as fake zeros.

Customization: `ChoiceLabels` names the alternatives ("Left"/"Right"
instead of "Choice 0"/"Choice 1") and pads with defaults past its end;
`ChoiceColors` does the same over the toolbox `Choice_*` palette
(`epsych.BitMask.getDefaultColors`); `PerformanceColor`, `ChanceColor`,
`MarkerSize`, `LineWidth`, and `ShowChance` style the rest. Style changes
outside the context menu take effect on the next `refreshPlot()`.

The right-click menu also offers "Open in Separate Window" (`gui.PopOut`):
the pop-out is a second `NAFC` over the same trials with graphics and
settings of its own, so restyling or closing it leaves the embedded plot
untouched. `disablePlot()` releases the graphics; an embedded axes being
destroyed does the same automatically.

## Example

```matlab
% Offline, from a saved 2AFC session file:
S = load(datafile);
A = psychophysics.NAFC(S.Data, 'SignedContrast', ...
    NumAlternatives=2, ChoiceField="ChoiceSide", ChoiceLabels=["Left","Right"]);
disp(A.Results.PercentCorrect)
A.Plot();                          % choice functions
A.PlotType = "confusion";          % which side gets confused with which

% Online, inside a gui.BehaviorGUI subclass:
function p = createPsych(obj, R)
    p = psychophysics.NAFC(R, obj.P.SignedContrast, NumAlternatives=2, ...
        ChoiceField="ChoiceSide", ChoiceLabels=["Left","Right"]);
end
% ...and in build():  obj.Psych.Plot(ax, PlotType="choice");
```

`tmp/smoke_test_nafc.m` is the standing check (hand-counted 3AFC session,
data routes, plotting, pop-out, online mode); `tmp/smoke_test_two_afc.m`
exercises the live embedding end to end.

## See Also

- `documentation/psychophysics/psychophysics_Psych.md` — the base class contract
- `documentation/psychophysics/psychophysics_SessionMetrics.md` — session summary counterpart
- `documentation/gui/gui_PopOut.md` — the pop-out mixin
- `examples/two_afc/` — the 2AFC tutorial this class is embedded in

## Changelog

- 2026-08-19: Initial release: N-AFC scoring (choice functions, proportion
  correct, confusion matrix, bias) with customizable plotting, embedded in
  the 2AFC tutorial GUI.
