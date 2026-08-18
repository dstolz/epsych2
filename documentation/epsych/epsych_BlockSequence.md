# epsych.BlockSequence — Block-Randomized Values, Indexed by the Caller

`epsych.BlockSequence` draws from a fixed list the way an experiment wants it drawn: in
**blocks**, so every value appears exactly its share within each block rather than merely on
average over an infinite session. The sequence is generated ahead of time, and the **caller
supplies the index** — usually `TRIALS.TrialIndex` — so the value for a trial can be
re-read, rewound, or fast-forwarded and is always the same value.

Source: `obj/+epsych/@BlockSequence/`, gated by `tmp/smoke_test_blocksequence.m`.

```matlab
s = epsych.BlockSequence([500 1000 1500 2000], Label = "ITI");
iti = s.valueAt(TRIALS.TrialIndex);
```

## Why it exists

The existing way to randomize a per-trial value is `hw.Parameter.isRandom`, which redraws
`randi([Min Max])` inside `set.Value` on **every** dispatch. That is memoryless,
integer-only, uniform over a range rather than a list, and unbalanced over any finite
session: 40 trials can easily deliver twelve 500 ms intervals and three 2000 ms ones. It
also cannot be re-read — nothing knows what trial 12 got except the saved record.

A BlockSequence fixes all four. Balance is exact per block; the pool is an arbitrary list,
not a range; values may be non-integer, strings, or filenames; and the sequence is a
**session record** rather than a generator, because the same index always returns the same
value.

The three legacy sequence generators in `helpers/` (`RandomTrialSequence.m`,
`randGellerman.m`, `FellowsSeq.m`) are binary-only and unused; this class supersedes them
for value selection.

## The block model

A block is one shuffled permutation of the value list. `Repeats` gives a value more than one
slot per block, so proportions are exact rather than probabilistic:

```matlab
epsych.BlockSequence([500 1000 1500 2000])                      % block = shuffle of all four
epsych.BlockSequence([500 1000 1500 2000], Repeats = [2 2 2 1]) % block of 7, 2000 ms is rarer
epsych.BlockSequence([1 2 3], Repeats = [1 0 2])                % Repeats = 0 drops a value
```

`Repeats` is a scalar or one entry per value, and must be a whole number. Fractional weights
are deliberately not supported: a weight that is not an exact per-block count is precisely
what block randomization exists to eliminate. A 25% catch rate is `Repeats = [3 1]`.

`Values` may be numeric, a string array, or a cell of char/string. The sequence internally
stores **positions** into `Values`, so every type block-randomizes identically:

```matlab
s = epsych.BlockSequence(["tone" "noise" "am"]);
s = epsych.BlockSequence({'a.wav', 'b.wav', 'c.wav'});
```

For anything the class does not store — a struct array, a `stimgen.StimType` array — build
the sequence over the indices and use `indexAt`:

```matlab
s = epsych.BlockSequence(1:numel(stimuli));
thisStim = stimuli(s.indexAt(TRIALS.TrialIndex));
```

## Constraints

All three are off by default and configured per caller. Each is a real distortion of the
sampling distribution, so none is inherited silently.

| Property | Default | Effect |
|---|---|---|
| `MaxConsecutive` | `Inf` (off) | Cap on runs of one value, enforced across block boundaries as well as within a block |
| `NoRepeatAcrossBlocks` | `false` (off) | A block may not begin with the value the previous block ended on |
| `Jitter` | `0` (off) | `+/-j`, or `[lo hi]`, added to a numeric value; `JitterQuantum` rounds the result and `ValueLimits` clamps it |

Block randomization already bounds runs at `2 * max(Repeats)` on its own, which is why the
run cap is off by default. `NoRepeatAcrossBlocks` is off because turning it on makes block
seams *identifiable* — a subject can in principle exploit "never the same value twice at a
boundary". It is right for some designs and wrong for others, so no default is safe.

Constraints are satisfied by **rejection sampling first** — up to 100 uniform permutations —
because a uniform permutation preserves the distribution over valid arrangements where a
swap-based repair does not. Repair is a single left-to-right pass used only when the sampler
keeps missing, and an arrangement that still violates a rule raises
`epsych:BlockSequence:UnsatisfiableConstraints` rather than quietly relaxing it.

Impossible configurations are caught **analytically, before any generation**, by `validate`:
a block of `B` whose commonest value appears `m` times can be arranged with runs of at most
`k` only if `m <= k*(B - m + 1)`. So `Values = [1 2], Repeats = [5 1], MaxConsecutive = 1`
fails at once rather than after 100 futile permutations, and a single distinct value with
any run constraint fails too. A silently relaxed run cap is a design defect invisible until
analysis months later.

Jitter is **baked at generation time**, not applied at read time, because `valueAt(12)` must
return on a rewind exactly what it returned on dispatch. `info.Base` and `info.Jitter` report
the two halves separately, so a jittered interval stays auditable against the saved record.
`ValueLimits` is what stops +/-200 ms of jitter on a 100 ms interval from going negative.
Jitter, `JitterQuantum`, and `ValueLimits` need a numeric pool and otherwise throw
`epsych:BlockSequence:JitterRequiresNumeric`.

## The caller owns the index

There is no cursor. `valueAt(idx)` is a pure lookup, so a selector may re-read the current
trial, rewind to inspect an earlier one, or skip ahead, and the answers never shift.

```matlab
[v, info] = s.valueAt(idx)             % idx may be a vector
v = s.valueAt(idx, Commit = false)     % inspect without recording a delivery
k = s.indexAt(idx)                     % positions into Values, no jitter
[b, pos] = s.blockAt(idx)              % block number and position within it
v = s.preview(startIdx, count)         % look ahead; never commits
n = s.tally(throughIdx)                % how often each value has been used
```

`info` is a struct of same-shape arrays: `Index`, `Base`, `Jitter`, `ValueIndex`, `Block`,
`PositionInBlock`, `Wrapped`, `Extended`.

`valueAt` advances `CommittedThrough` by default, which is what makes the ordinary selector
line correct with no ceremony, while `preview`, `indexAt`, `blockAt`, and `tally` never do.
`setCommitted` moves the mark by hand, including downward after discarding trials.

## Past the end of the sequence

`Exhaustion` is the caller's choice.

| Mode | Behavior |
|---|---|
| `"extend"` (default) | Append more blocks on demand. Extension **only ever appends**; no element already generated is rewritten, so a rewind is exact. Growth is at least `ChunkBlocks` blocks and is capped by `MaxLength` |
| `"wrap"` | Fold the index back onto the generated sequence. `info.Wrapped` is set, so a save function can record it. Note this makes the sequence periodic with period `Length` |
| `"error"` | Throw `epsych:BlockSequence:IndexExceedsSequence` |

`MaxLength` defaults to 1e6 and exists as insurance against a caller passing a timestamp
where a trial index belongs — `valueAt(1e9)` would otherwise try to allocate 8 GB. An index
of zero, a negative index, or a fractional one throws `epsych:BlockSequence:InvalidIndex`
rather than being clamped or rounded, because such an index almost always means a trial
counter was read before it was set.

## The seed

`Seed` backs a private `RandStream` and is **resolved on assignment**, so it always reads
back the concrete integer in use and can be written straight into a session record. Assign a
negative value (the default) to draw a fresh seed, which is right because a rig reusing one
fixed seed would give every animal the same sequence.

Generation never touches the global random stream — not on construction, not on a shuffle,
not on an extension — so a caller's own `rng(0)` is undisturbed either way. Shuffled seeds
come from one clock-seeded source stream rather than from `RandStream('shuffle')` per call,
so two sequences built in the same millisecond do not run in lockstep.

```matlab
vprintf(1, 'ITI sequence: seed %d', s.Seed)   % record it; the run can be replayed
```

Determinism rests on the sequence being **append-only**: the stream is created once per
rebuild and every extension appends, so earlier elements are never recomputed, only never
touched.

## Editing the value list mid-session

`Values`, `Repeats`, `Seed`, and the constraints are all writable at any time. Rebuilding is
**lazy** — it happens on the next read, not on assignment — so a multi-property edit is
validated as a set rather than throwing on the intermediate state:

```matlab
s.Repeats = [1 1 1 1 1];   % neither line throws on its own;
s.Values  = [1 2 3 4 5];   % the pair is checked together on the next read
```

**Values already delivered are frozen.** When the configuration changes, the realized values
for `1:CommittedThrough` are materialized before anything is discarded, so an operator who
edits the interval list at trial 40 does not retroactively change what the animal received on
trials 1 through 40. Rewinding stays exact across the edit, which is the whole reason the
caller owns the index.

The tail is regenerated starting at the **next whole block**, and the block that straddled
the edit is abandoned entirely: splicing mid-block would put half-old and half-new values in
one block and silently break the balance guarantee. The abandoned partial block is the
unavoidable cost, and it is logged at operator level (`vprintf` level 1).

One refinement falls out of storing positions rather than values: a **same-length**
replacement (`[500 1000 1500]` to `[600 1100 1600]`) is a pure lookup-table swap. The
ordering and the baked jitter are untouched, so the randomization survives an operator
retuning the values. The committed prefix is still frozen.

Changing `Seed` mid-session takes the identical path and is logged the same way, because it
changes the session's reproducibility record.

A configuration error found on the dispatch path never takes down a running experiment:
`valueAt` logs a critical record, keeps serving the sequence already in hand, and leaves the
object dirty so a corrected configuration takes effect on the next read. Call `validate`
from a selector's `initialize` so a bad design fails at run start instead.

## Using it from a trial selector

```matlab
classdef ItiSelector < epsych.TrialSelector
    properties (Access = private)
        iti_ epsych.BlockSequence
        itiCol_ (1,1) double = 0
    end

    methods
        function initialize(obj, TRIALS)
            obj.iti_ = epsych.BlockSequence([500 1000 1500 2000], ...
                Repeats = [2 2 2 1], MaxConsecutive = 2, ...
                Jitter = 50, JitterQuantum = 1, ValueLimits = [250 Inf], Label = "ITI");

            obj.iti_.validate();      % fail at run start, not at trial 1
            vprintf(1, 'ITI sequence: seed %d, %d pregenerated (block size %d)', ...
                obj.iti_.Seed, obj.iti_.Length, obj.iti_.BlockSize)

            obj.itiCol_ = TRIALS.writeParamIdx.ITI;
        end

        function nextTrialID = selectNext(obj, TRIALS)
            nextTrialID = ...;   % the paradigm's own choice of trial row

            % TRIALS arrives by value, so write through the live runtime handle.
            [iti, info] = obj.iti_.valueAt(TRIALS.TrialIndex);
            obj.runtime_.TRIALS(obj.subjectIdx_).trials{nextTrialID, obj.itiCol_} = iti;

            vprintf(3, 'trial %d: ITI %g ms (base %g, block %d pos %d)', ...
                TRIALS.TrialIndex, iti, info.Base, info.Block, info.PositionInBlock)
        end

        function onRecompile(obj, TRIALS)
            obj.itiCol_ = TRIALS.writeParamIdx.ITI;   % a recompile shifts later columns
        end
    end
end
```

**The trap: the driven parameter must have `isRandom = false`.** `hw.Parameter.set.Value`
calls `randomize_value` on every assignment, which would overwrite the selector's carefully
balanced value with `randi([Min Max])` on dispatch. The two mechanisms are alternatives, not
layers.

Record the sequence with the session data so the run can be reconstructed:

```matlab
sessionInfo.ITI = obj.iti_.toStruct();   % config, seed, and the generated sequence
```

`toStruct` includes the generated sequence by default (a few kilobytes) so the record is
exact; pass `IncludeSequence = false` for a configuration-only struct, which `fromStruct`
regenerates from the seed. `fromStruct` degrades rather than throwing, so an old record still
opens.

## Verification

`tmp/smoke_test_blocksequence.m` — headless, no figures, no hardware. Nineteen sections
covering determinism from a seed, that the global rng is never advanced, exact block balance
for both scalar and per-value `Repeats`, rewind stability across three successive extensions,
run-cap and boundary-rule satisfaction, analytic rejection of impossible configurations, all
three exhaustion policies, index validation, jitter being baked rather than redrawn, string
and cellstr pools, the frozen prefix across both a same-length and a length-changing edit, a
mid-session reseed, shuffled-seed reporting, the struct round trip, the commit policy, and a
generation-time guard.

```matlab
matlab -batch "run('tmp/smoke_test_blocksequence.m')"
```

## See also

- [epsych.TrialSelector](epsych_TrialSelector.md) — the caller this class is built for
- [hw.Parameter](../hw/hw_Parameter.md) — `isRandom`, the per-dispatch alternative
- [Trial Lifecycle](epsych_TrialLifecycle.md) — where `TrialIndex` comes from
