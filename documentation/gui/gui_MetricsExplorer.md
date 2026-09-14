# `gui.MetricsExplorer`

A map of one signal-detection metric over the whole hit-rate / false-alarm
plane, with a readout of every metric at the point you click and an explanation
of what the selected one means.

It exists for the question that comes up whenever a session reports a
surprising number: *what does this metric actually do between 0 and 1?* A
`d'` of 4.65 and a `c` of −0.49 are hard to judge in isolation and obvious on a
map.

Open it from **RunExpt → View → Psychophysics Metrics...** (`Ctrl+M`), or
directly:

```matlab
gui.MetricsExplorer
gui.MetricsExplorer(Metric="criterion", HitRate=0.635, FalseAlarmRate=0.738)
gui.MetricsExplorer(Correction="none")
```

It reads no hardware and holds no runtime, so it is safe to leave open beside a
running experiment — there is nothing for it to poll.

The window's **Help** menu opens the guide on the wiki
([Metrics-Explorer](https://github.com/dstolz/epsych2/wiki/Metrics-Explorer))
or this file, and the same wiki link sits at the foot of the explanation panel.

---

## It computes nothing of its own

Every surface and every number in the readout is
[`psychophysics.Metrics`](../psychophysics/psychophysics_Metrics.md), called
with the rates on the grid. This window is a picture **of** the arithmetic the
toolbox runs, not a second implementation of it that could drift:

```matlab
% What the map draws at one point, reproduced at the command line
gui.MetricsExplorer.evaluate("dprime", 0.8, 0.2, Correction="clamp")
```

Adding a metric means adding a `catalog` entry that names a `Metrics` method.
There is no formula in this class.

## The metrics

| Shown as | Metric | Neutral | Correction? |
|---|---|---|---|
| `d'` | `Metrics.dprime` — sensitivity | 0 (chance) | yes |
| `c` | `Metrics.criterion` — decision criterion | 0 (unbiased) | yes |
| `c'` | `Metrics.criterionRelative` — `c/d'` | 0 | yes |
| `ln B` | `Metrics.lnBeta` — likelihood-ratio bias | 0 | yes |
| `A'` | `Metrics.aprime` — nonparametric sensitivity | 0.5 (chance) | **no** |
| `B''` | `Metrics.bprimeprime` — nonparametric bias | 0 | **no** |
| `pc` | `Metrics.percentCorrect` — balanced proportion correct | 0.5 (chance) | **no** |

`beta` itself is not offered: it spans orders of magnitude, and `ln B` is the
form that plots. `exp` of the readout is `beta`.

## The correction is a control, not a default

The interesting part of this plane is its edges, and that is exactly where the
z-transform is undefined: `z(0)` is `-Inf` and `z(1)` is `+Inf`. Which finite
number appears at the edge of the map is a scientific choice, so it is named on
the window the same way `psychophysics.Metrics` names it at every call.

| Correction | At the edges | Needs |
|---|---|---|
| `none` | ±Inf — the map saturates, honestly | — |
| `clamp` (default) | rates pulled into `[0.01 0.99]` | bounds |
| `halfcell` | 0 → `1/(2N)`, 1 → `1 − 1/(2N)` | N signal, N catch |
| `loglinear` | **every** rate → `(nYes+0.5)/(N+1)` | N signal, N catch |

Two things worth seeing for yourself with the dropdown:

- Under `clamp` with the default bounds, no session can report a `d'` above
  `2·z(0.99) = 4.653`, however good the subject. The whole top-left corner of
  the map is that one number.
- Under `loglinear` the surface moves everywhere, not only at the edges — that
  is what "every rate" means, and it is why the correction is worth stating in
  a methods section.

`A'`, `B''` and the balanced proportion correct are defined at rates of exactly
0 and 1, so they take **no** correction — correcting them would only bias them
toward chance. Selecting one greys the correction controls out and the status
line says why, rather than leaving a setting on screen that the picture is
ignoring. This is the same split `Metrics.fromCounts` makes internally.

The status line under the map always says what the z-transform actually saw at
the probe point, which is the first question to ask of a surprising `d'`.

## Reading the map

- **Heavy black line** — the metric's neutral level: chance for a sensitivity
  index, unbiased for a bias index. For `d'` that is the `H = F` diagonal; for
  `c` it is the `H = 1 − F` anti-diagonal. `ln B` has *both*, because
  `ln β = c · d'` vanishes where the subject is unbiased **and** where the
  subject is at chance.
- **Thin labelled contours** — round levels, eight steps across the colour
  range. The **Contour labels** checkbox turns them off; the neutral line
  stays either way.
- **Colour** — blue below the neutral value, white at it, red above. The scale
  is always *symmetric* about the neutral value, so white means chance or no
  bias in every metric and the two poles keep one meaning. Only the half-width
  is adjustable (**Colour range ±**), which is what stops the scale from ever
  being centred somewhere that means nothing.
- **`<=` / `>=` on the end ticks** — the scale is clipped there. A saturated
  colour that does not admit it reads as a measured value, so the colorbar says
  so whenever any part of the surface runs past the range.
- **Blank patches** — `NaN`. The band along the diagonal on the `c'` map is
  `d' = 0`: there is no meaningful relative criterion where there is no
  sensitivity, and infinity is reported rather than papered over.

## The readout

Click anywhere on the map — or type into the two rate fields, or nudge with the
arrow keys (`0.01`, or `0.001` with Shift) — and the strip under it shows every
metric at that point, with the selected one in bold. The rates are edit fields
rather than labels so a point can be entered exactly instead of aimed at.

`n/a` means `NaN`; `Inf` and `-Inf` are printed as themselves. Neither is
rounded into a number that was never computed.

Right-click the map for **Assign Surface to Command Window**, which puts the
surface, the rate vectors and the probe values in the base workspace as
`METRICS`.

## The explanation and its references

The panel on the right is assembled from the selected metric's catalog entry:
the formula, what the number means, how to read the map, how rates of 0 and 1
are handled, and what to watch for. Under it are the works the explanation
rests on, each followed by its DOI as a link (`doi:10.1037/h0031246`) that
opens `https://doi.org/…` in the system browser. The link text is the DOI
itself, so the identifier can be copied off the window as well as clicked.

Citations are kept in one table, `gui.MetricsExplorer.citations`, and a
catalog entry names them by key — so a DOI is written once however many
metrics cite the work, and a mistyped key fails when the catalog is built
rather than showing up as a missing link. A work with no DOI (Green & Swets,
1966) is listed without a link rather than given an invented one.

## Programmatic use

```matlab
E = gui.MetricsExplorer(Metric="aprime");
E.setPoint(0.9, 0.35);            % hit rate, false alarm rate
S = E.values();                   % every metric here, fromCounts field names
[Z, hitRates, faRates] = E.surface();

% Headless, no window:
gui.MetricsExplorer.catalog()                     % the metrics on offer
gui.MetricsExplorer.metric("criterion")           % one entry
gui.MetricsExplorer.evaluate("criterion", H, F)   % rates broadcast
gui.MetricsExplorer.citations("Grier1971")        % Key, Short, Full, DOI
gui.MetricsExplorer.openGuide()                   % the wiki page, in a browser
```

`values()` uses the field names `psychophysics.Metrics.fromCounts` uses
(`DPrime`, `Criterion`, `CriterionRelative`, `LnBeta`, `APrime`,
`BPrimePrime`, `PercentCorrectBalanced`), so a number read off this window and
the same number out of a session are looked up under one name.

## Notes

- One window at a time: opening it again closes the previous one, having first
  saved its position (`epsych2_gui_MetricsExplorer`).
- The grid is 201 × 201 rates per axis, odd so that 0.5 and every tenth land
  exactly on a grid point.
- Infinities are left infinite in the surface — they saturate the colour scale,
  which is what they mean — and are dropped only from the contour input, where
  a level crossing at infinity is meaningless.

## See also

- [`psychophysics.Metrics`](../psychophysics/psychophysics_Metrics.md) — the arithmetic
- [`psychophysics.APrime`](../psychophysics/psychophysics_APrime.md) — why `A'` takes no correction
- [`psychophysics.SessionMetrics`](../psychophysics/psychophysics_SessionMetrics.md) — the same metrics over a real session
- [`gui.components.SessionPerformance`](gui_SessionPerformance.md) — the live panel that reports them
- `tmp/smoke_test_metrics_explorer.m` — the standing proof

## References

- Green DM, Swets JA (1966) *Signal Detection Theory and Psychophysics*. New
  York: Wiley. (No DOI.)
- Macmillan NA, Creelman CD (2005) *Detection Theory: A User's Guide*, 2nd ed.
  Mahwah, NJ: Erlbaum.
  [doi:10.4324/9781410611147](https://doi.org/10.4324/9781410611147)
- Grier JB (1971) Nonparametric indexes for sensitivity and bias: computing
  formulas. *Psychol Bull* 75(6):424–429.
  [doi:10.1037/h0031246](https://doi.org/10.1037/h0031246)
