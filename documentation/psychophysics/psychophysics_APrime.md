# A' — nonparametric sensitivity

A distribution-free companion to d', available anywhere EPsych reports
sensitivity.

Source: `psychophysics.Metrics.aprime` (`obj/+psychophysics/Metrics.m`);
`psychophysics.Detection.a_prime` forwards to it and is kept for compatibility

A' summarizes how well a subject separates signal from noise using nothing but
the hit and false alarm rates, and without assuming the equal-variance Gaussian
evidence distributions that d' is built on. It reads as the area under the ROC
curve passing through the one observed (FA, H) point — equivalently, the
probability the subject would answer correctly in a two-alternative forced
choice task with the same discriminability.

| A' | Meaning |
|----|---------|
| `1.0` | Perfect discrimination |
| `0.7`–`0.9` | Solid sensitivity in a typical perceptual task |
| `0.5` | Chance; no discrimination |
| `< 0.5` | Reversed or confused response mapping |

## The formula

Grier's (1971) corrected formula, which is the one implemented:

```
A' = 0.5 + sign(H - FA) * ( (H - FA)^2 + |H - FA| )
                        / ( 4*max(H, FA) - 4*H*FA )
```

with `H` the hit rate over scored stimulus trials and `FA` the false alarm rate
over scored catch trials. `H == FA` is chance by definition and is returned as
exactly `0.5` — taken as a separate case because the denominator also vanishes
at `H == FA == 0` and `H == FA == 1`.

## Why it exists alongside d'

d' remains the default. Reach for A' when:

- **The rates are extreme.** d' is undefined at a hit rate of 1 or a false
  alarm rate of 0, which is exactly what a well-trained animal or an easy
  stimulus level produces. EPsych papers over that with `infCorrection`
  (default `[0.05 0.95]`), which clamps the rates before the z-transform and
  therefore *caps* d' at an arbitrary value that depends on the clamp, not on
  the behavior. A' needs no such correction: it is defined at 0 and 1.
- **Trial counts are small.** Early in a session, or in a short trial window,
  a single trial swings a clamped d' a long way. A' is bounded and better
  behaved.
- **The Gaussian equal-variance assumption is doubtful** — the usual reason for
  a nonparametric index in the first place.
- **The number goes to a non-specialist.** "0.85" on a 0.5-to-1 scale needs
  less explaining than "1.84".

The one real limitation: A' interpolates from a *single* ROC point. It is not
an empirical ROC integration, and two subjects with the same A' can still have
differently shaped ROC curves.

Because A' takes the rates uncorrected, `infCorrection` moves d' and criterion
but never A'. That is deliberate, and `tmp/smoke_test_aprime.m` asserts it.

## Where it shows up

```matlab
% The arithmetic, on any pair of rates (they broadcast; NaN in, NaN out)
a = psychophysics.Detection.a_prime(0.8, 0.2);      % 0.875
a = psychophysics.Detection.a_prime([0.3 0.6 0.9], 0.2);

% Per unique stimulus value, from a live or saved session
P = psychophysics.Detection(RUNTIME, RUNTIME.find_parameter('ToneLevel'));
P.APrime            % one A' per stimulus value, against the catch-trial FA rate

% Session summary, over any trial window
S = psychophysics.SessionMetrics(RUNTIME, TrialWindow="last 50");
S.Results.APrime
S.metric("APrime")  % value, "0.873", supporting counts

% Plots
plt = gui.PsychPlot(P, ax);  plt.PlotType = 'APrime';   % vs stimulus value
swp = gui.SlidingWindowPerformancePlot(P, ax);
swp.plotType = "aPrime";                                 % vs trial number
```

In a GUI, `gui.SessionPerformance` lists **A'** in its right-click *Show
Metric* menu — it is generated from the `SessionMetrics` catalogue, so nothing
had to be registered for it to appear — and `gui.PsychPlot`'s right-click
*ordinate* picker offers `APrime` beside `DPrime`. Neither is shown by default;
`defaultMetrics` and the default plot type are unchanged, so an existing rig
looks the same until someone asks for A'.

Both plots move their reference line to chance when A' is selected:
`gui.SlidingWindowPerformancePlot` draws a dashed line at 0.5 instead of the
d' = 1 line, and `gui.PsychPlot`'s horizontal reference line drops from 1 to
0.5 — on an A' axis, 1 is the ceiling rather than a landmark.

## Reference

Grier JB (1971). Nonparametric indexes for sensitivity and bias: computing
formulas. *Psychological Bulletin* 75(6):424–429.

Grier's paper also gives B'', the nonparametric response bias index usually
reported beside A':

```text
B'' = sign(H-F) * ( H(1-H) - F(1-F) ) / ( H(1-H) + F(1-F) )
```

It runs from −1 (extremely liberal) through 0 (no bias) to +1 (extremely
conservative), and is to `Criterion` (c) what A' is to d': distribution-free,
and defined at rates of exactly 0 and 1, so it needs no correction. It is
available as `psychophysics.Metrics.bprimeprime` and as the `BPrimePrime`
metric on `psychophysics.SessionMetrics` — in the catalogue, so
`gui.SessionPerformance` offers it, but not in the default display.

Unlike A', B'' is *unchanged* when the two rates are swapped. The `sign` factor
exists precisely for that: a subject who says "yes" rarely reads as
conservative whichever distribution the rates came from.

## See also

- [psychophysics.Metrics](psychophysics_Metrics.md) — `aprime` and `bprimeprime`, and the rest of the arithmetic
- [psychophysics.SessionMetrics](psychophysics_SessionMetrics.md) — the `APrime` and `BPrimePrime` session metrics
- [gui.SessionPerformance](../gui/gui_SessionPerformance.md) — the panel that displays them
- `psychophysics.Detection` (`obj/+psychophysics/@Detection/`) — `d_prime`, `a_prime`, `bias` (forwarders to `Metrics`)
