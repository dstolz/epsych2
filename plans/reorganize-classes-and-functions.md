# Reorganize EPsych2 classes and functions for categorization and navigability

## Context

EPsych2 has grown into a ~92,000-line mixed procedural/OOP codebase, and the directory layout no
longer reflects how the code is organized. Concretely:

- **The test suite lives in a folder called `tmp/`** — 143 tracked files, 94 of them
  `smoke_test_*.m`. Nothing about the name says "this is how you validate a change," there is no
  runner, and the hardware mocks sit on the global MATLAB namespace.
- **`+psychophysics` and `+gui` form a dependency cycle**, entirely because of one line.
- **`+peripherals` and `+hw` both hold serial-port device drivers** with no stated boundary; one
  `+peripherals` class is fully superseded by an `+hw` one.
- **Signal-detection math is duplicated** in `gui.Helper` and `psychophysics.Detection`.
- **~16,000 lines of GUI code sit in domain packages** (`+epsych`, `+teensy`) rather than `+gui`.
- **`PRGMSTATE` is the only type polluting the global namespace**, while its exact analogue
  `hw.DeviceState` is properly packaged.
- Accumulated dead files and two confirmed path bugs.

**Outcome:** a layout where the folder name tells you what the code is, no package depends on a
package that depends back on it, and the test suite is discoverable and runnable — achieved
*without* breaking the saved-file compatibility real rigs depend on.

## The constraint that shapes everything

Saved `.eprot`/`.ecfg`/`.esub` files store **bare and fully-qualified class/function names**,
resolved at load via `which()`. When a name does not resolve,
`epsych.Protocol.createInterfaceFromStruct_` **silently degrades the protocol to an `hw.Software`
stub** rather than erroring.

So: **no persisted type may be renamed or re-packaged** — every `hw.*` interface, `FUNCS.BehaviorGUI`
/ `SavingFcn` / `AddSubjectFcn` / `TIMERfcn`, trial-selector names, `stimgen.*` names.

Two facts make the rest cheap:
- The path is `genpath`-discovered from the repo root ([epsych_startup.m:224](epsych_startup.m#L224),
  `visibleSubdirs`). **Folder moves are path-transparent.** Only explicit path *strings* break.
- A package's identity comes from its `+name` folder, not its parent.

`epsych_startup.m` and `epsych_path.m` must stay at the repo root — worktree eviction identifies a
checkout by `epsych_startup.m` at its top.

## The rule this reorg establishes

> A GUI class moves to `+gui` **unless its class name participates in identity or resolution
> checks.**

`epsych.RunExpt` fails on all three counts and **stays**: asserted by `isa`
([SelfTest.m:82](obj/+epsych/@SelfTest/SelfTest.m#L82),
[assignToSession.m:59](obj/+epsych/@SubjectRoster/assignToSession.m#L59)), introspected by metaclass
(`mc = ?epsych.RunExpt`, [checkConfig.m:202](obj/+epsych/@SelfTest/checkConfig.m#L202)), and listed in
the [checkEnvironment.m:51-58](obj/+epsych/@SelfTest/checkEnvironment.m#L51-L58) tripwire. Its statics
are also called from the extension points themselves —
[cl_SaveDataFcn.m:149](paradigms/SaveDataFcns/cl_SaveDataFcn.m#L149) and
[ep_TimerFcn_Start.m:101](runtime/timerfcns/ep_TimerFcn_Start.m#L101) both call
`epsych.RunExpt.defaultFilename`, as does every lab's custom save function.

**Neither shim shape works, so this is move-cleanly-or-not-at-all:**

| Shim | Fails because |
|---|---|
| `classdef RunExpt < gui.RunExpt` | Two live metaclasses; `?epsych.RunExpt` inspects the shim while internally-constructed objects are `gui.RunExpt`. Every `class(x)` comparison diverges. |
| `function RunExpt(varargin)` forwarding | **Actively dangerous.** `which('epsych.RunExpt')` still resolves, so the tripwire **passes falsely**, while `isa` silently returns `false` and `?epsych.RunExpt` errors. |

`epsych.ProtocolDesigner` and `teensy.TrialDesigner` fail *none* of the three tests — no identity
checks, not persisted, not in the tripwire — so they **do** move. Net: ~16,400 of the ~21,500 lines
leave their domain packages; `@RunExpt`'s 5,140 stay by design, documented as a stated exception.

## Corrections made during planning

- **Not dead code — keeping.** `gui.BasicGUI` (docstring: "a functional starting point for custom
  experiment GUIs"), `gui.components.Performance` and `gui.components.SlidingWindowPerformancePlot` (both rendered into
  the wiki by `generate_wiki_screenshots.m`), `gui.components.MicrophonePlot`, and helpers `showGridBorders`
  (documented in `Customized_GUI_Instructions.md`), `randGellerman`, `FellowsSeq`,
  `RandomTrialSequence`. These have no *internal* caller, which is not the same as dead.
- **`tmp/+psychophysics/FakeHistoryPsych.m` is not a hazard.** MATLAB merges same-named namespace
  folders across path entries, and `smoke_test_history_render.m:14` says so explicitly
  (`% +psychophysics/FakeHistoryPsych.m merges into psychophysics package`). It is a deliberate
  test-injection technique; it only needs its `addpath` target repointed when it moves.
- **`plans/` is a normal directory** — `git ls-files` was quoting an em-dash in a filename. There is
  no stray `"plans` directory to remove.
- **`.error_logs/` is not bloating git** — only its `.gitignore` stub is tracked.
- **`gui.GenericTimer` is used only inside `+gui`**; `teensy.getFieldOr` only inside `+teensy`.
  Moving them to `+util` is churn for no gain. They stay.

---

## Stages

Each stage is one commit. Always `git mv` (preserves `git log --follow`). Re-check
`git status --short` before each stage — a parallel Claude session shares this checkout.

### Stage 0 — Baseline (no commit)

Tree is currently clean at `98bd554`. Tag a restore point (`git tag reorg-baseline`), then in a
**fresh** `matlab -batch` capture two artifacts to the scratchpad — these are the diff target for
the whole project:

```matlab
run('C:\src\epsych2\epsych_startup.m');
iss = codeIssues("C:\src\epsych2");
disp(iss.Issues(iss.Issues.Severity=="error",:))
```

`codeIssues` walks the tree and reports unresolved identifiers repo-wide. **This is the highest-value
check for a rename refactor** and catches most fallout that smoke tests miss (rare branches,
callbacks). Also capture an `epsych.SelfTest` report.

### Stage 1 — Delete dead code (low risk)

```
git rm helpers/gexf.m helpers/PhotodiodeMarker.m helpers/Viemeister.m \
       helpers/ParseVarargin.m helpers/findincell.m helpers/gatestim.m
git rm -r obj/+gui/@BoxGUI obj/+peripherals/@PumpCom
git rm paradigms/BehaviorGUIs/cl_AppetitiveDetection_BoxGUI.m
git rm tmp/S_PATH.m tmp/SCRATCH_quickCalc.m tmp/TEST_NEW_PROTOCOL2.eprot.bak-20260811-expr
git rm TDTfun/SynapseAPI/support/fromjson.mexw32 TDTfun/SynapseAPI/support/tojson.mexw32
```

Rationale per item: `@BoxGUI` is a self-described one-release shim (absent from Class_Map);
`cl_AppetitiveDetection_BoxGUI.m`'s header says "then delete this file"; `@PumpCom` is superseded by
`hw.NE1000` (only surviving mention is a "See also" at [NE1000.m:99](obj/+hw/@NE1000/NE1000.m#L99));
`S_PATH.m` calls `restoredefaultpath` and hardcodes `c:\src\epsych2` — the exact thing that kills the
MCP session; the `.mexw32` files are unloadable in any supported MATLAB.

Also delete `tmp/LegacyShimGUI.m` (header: "Delete alongside gui.BoxGUI") and the `@BoxGUI` case in
`tmp/smoke_test_behaviorgui.m`. Delete `EPsychInfo.icon_img` (zero callers) but **repoint**
`iconPath` to `graphics/icons` rather than removing it — [EPsychInfo.m:86](helpers/@EPsychInfo/EPsychInfo.m#L86)
currently returns `<root>/icons`, which does not exist.

**Verify:** `codeIssues` diff clean; `git grep` for each removed name returns only doc hits.

### Stage 2 — `tmp/` → `tests/`, flat (low risk)

```
git mv tmp tests
```

Depth is unchanged, so **both** self-relative idioms still resolve and nothing needs rewriting.
Only literal strings break: `.gitignore` (`tmp/*.log`, `tmp/*.txt`), ~96 header comments
(`matlab -batch "cd('tmp'); ..."`), and 6 real sites — `smoke_test_dispatch_order.m:139`,
`smoke_test_phase_fastparse.m:53-54`, `smoke_test_staircase_plot.m:21`,
`smoke_test_subject_manager.m:34`, `smoke_test_subject_roster.m:38,215`.

Keeping this separate from the sort is what makes Stage 3 bisectable.

**Verify:** full suite — this is the cheapest point at which a full baseline is meaningful, and
Stage 3 needs one.

### Stage 3 — Sort `tests/` + build the runner (medium risk — this is the gate)

| Destination | Contents |
|---|---|
| `tests/smoke/` | 94 `smoke_test_*.m` + `crash_test_trialjournal.m` |
| `tests/mocks/` | `*_Mock.m`, `Fake*.m`, `Mock*.m`, `*Adapter.m`, `*BehaviorGUI.m`, `BrokenSink.m`, `ParameterDebuggerMock.m`, `+psychophysics/FakeHistoryPsych.m` |
| `tests/fixtures/` | `*.eprot`, `*.ecfg`, `*.prot`, `*.json` |
| `tests/tools/` | `generate_*.m`, `recreate_*.m`, `run_*.m`, `T_*.m`, `demo_adaptive_threshold.m`, `VlcRecorder_example.m` |
| `tests/scratch/` | `staircase_shots/`, `*.txt`, `*.log` |

**Two distinct idioms need different treatment** — this is the crux of the stage:

1. **`repoRoot = fileparts(fileparts(mfilename('fullpath')))`** (~21 sites, incl. inline
   `run(fullfile(fileparts(fileparts(...)),'epsych_startup.m'))`). Every smoke test lands at exactly
   `tests/smoke/`, so apply a uniform **+1 `fileparts`**.
   **Do not convert these to a `testRoot()` helper** — they run *before* `epsych_startup`, so nothing
   is on the path yet and a helper call would not resolve. Keep them literal, on purpose.
2. **`here = fileparts(mfilename('fullpath'))`** (44 sites) — used for three different things:
   - *`addpath` to reach sibling mocks* (incl. the six `+psychophysics` merge sites in
     `smoke_test_history_*.m`, `smoke_test_incremental_*.m`, `smoke_test_popout.m`): replace with an
     explicit `addpath(fullfile(repoRoot,'tests','mocks'))`. Several of these precede
     `epsych_startup`, so do not rely on `genpath` having run.
   - *fixture reads*: repoint to `tests/fixtures/`. Enumerate exhaustively first —
     `grep -rn "fullfile(here" tests/ | grep -E "\.(eprot|ecfg|prot|json|mat)"`.
   - *log/output writes* (`T_*.m`, `staircase_shots`): self-relative **by intent**. Leave `here`
     alone in `tests/tools/`; only fix the literal `'tmp'` in the `staircase_shots` path.

**Add `tests/runAll.m`** — there is no test runner today, and this is what makes every later stage
verifiable. Spec: enumerate `tests/smoke/smoke_test_*.m`; per test record `pre = findall(0,'Type','figure')`,
`try run(...) catch ME`, then `delete(setdiff(findall(0,'Type','figure'), pre))` — **only figures the
test created, never `close all`**; never `clear`/`clear classes`/`restoredefaultpath`. Return a table
`[Name Status Seconds Message]`. Ship a **declared skip list with reasons** for hardware-dependent
tests (`smoke_test_teensy*`, `_vlcrecorder_setup`, `_videoconverter`, `_ne1000`, `_bpod*`) so a skip is
never mistaken for a pass. Add a `Fast` flag selecting the core gate below.

Also add `tests/testRoot.m` for **new** tests only, and note in `CLAUDE.md` that existing bootstrap
lines stay literal deliberately.

**Core gate** (run after every later stage): `smoke_test_runexpt_selftest` (exercises the
`checkEnvironment` tripwire — the best single canary), `_first_experiment`, `_two_afc`,
`_subject_roster`, `_persist_with_phase`, `_phase_protocol`, `_behaviorgui`,
`_epsych_startup_worktree`, `_epsychinfo_worktree`, `_read_hw_parameters`.

> `smoke_test_phase_fastparse` sweeps working-tree `.eprot` files, so trust a red result only
> against a clean tree.

### Stage 4 — Dissolve `+peripherals` (low risk)

```
git mv obj/+peripherals/@NanoMotorControl    obj/+hw/@NanoMotorControl
git mv obj/+peripherals/@NanoMotorControlGUI obj/+gui/@NanoMotorControlGUI
```

One internal call site ([RunExpt.m:396](obj/+epsych/@RunExpt/RunExpt.m#L396)); not persisted. Fix the
H1 typo `%NANAMOTORCONTROLGUI` while moving. **Add a class comment noting `hw.NanoMotorControl` does
not derive from `hw.Interface`** — it therefore never appears in the "Add Interface" list and is
never resolved by `createInterfaceFromStruct_`, which is exactly why the move is name-safe. Without
that note the next reader will assume it is an interface.

Fold `documentation/peripherals/` into `documentation/hw/` and `documentation/gui/`; update
`Class_Map.md:181-182,226-227`, `Architecture_Overview.md:137-139`, `hw_NE1000.md:323`, `pagemap.tsv`.

**Gate:** core + `_ne1000`, `_syringepump_gui`, `_pump_trial_cycle`.

### Stage 5 — Utilities, `gui.Helper` split, cheap renames (medium risk)

Two commits.

**5a — moves.** `helpers/isConcreteStimType.m` → `obj/+stimbridge/` (pure stimgen-integration logic;
called from [inferSerializedParameterType_.m:11](obj/+epsych/@Protocol/inferSerializedParameterType_.m#L11)
and `Parameter_Control.m:1028`). ~~`helpers/bitmask_gui.m` → `obj/+gui/bitmaskGUI.m` (callers:
[BitMask.m:117](obj/+epsych/@BitMask/BitMask.m#L117), `TrialDesigner.m:607`).~~
**Renamed in place 2026-08-25** as `helpers/bitmaskGUI.m`, both callers updated, no alias
left behind. The MOVE into `obj/+gui/` is still open.
`obj/+gui/eval_dependent_parameter_randomization.m` and `eval_staircase_training_mode.m` → `obj/+hw/`
with camelCase names (they operate on `hw.Parameter` semantics, not GUI).

**`gui.Helper` split:** ~~`dprime2AFC`/`criterion`/`percent_correct` duplicate
`psychophysics.Detection.d_prime`/`.criterion`.~~ **Done 2026-08-19.** The destination this step
was missing is `psychophysics.Metrics`; the bodies moved there and `gui.Helper` keeps thin
forwarders — it is a documented mixin that lab BehaviorGUIs inherit, and removing superclass
methods breaks out-of-repo subclasses silently. Their hard-coded `[0.01 0.99]` bounds were
preserved for the same reason. Delete the forwarders in a later release; no deprecation warning
yet, since they run in per-trial callbacks.

**5b — `epsych.eventModeChange` → `epsych.ModeChangeEventData`.** 26 sites; the only PascalCase
violation among the three `event.EventData` types. **The event *name* string `'ModeChange'` must not
change** — only the data class, so watch the
`notify(obj,'ModeChange', epsych.eventModeChange(...))` pattern.

**Gate:** core + `_parameter_control_bounds/range`, `_parameter_monitor`, `_parameter_reset`,
`_stimtype_variant_selection`, `_history_render`.

### Stage 6 — Break the `+psychophysics` ↔ `+gui` cycle (medium risk)

The cycle is one line: [Staircase.m:1](obj/+psychophysics/@Staircase/Staircase.m#L1),
`classdef Staircase < psychophysics.Psych & gui.PopOut`. That is the **only** non-comment `gui.`
reference in all of `+psychophysics`. 15 of `@Staircase`'s 19 method files are plotting code.

`git mv` those 15 (`applyAxesStyle_`, `attachPlotDestructionListeners_`, `createPlotContextMenu_`,
`deletePlotGraphics_`, `directionColors_`, `getPlotData_`, `getTitleText_`, `onPlotFigureClose_`,
`responseCodeColors_`, `setupPlotAxes_`, `updateLegend_`, `updatePlotLabels_`, `updatePlotLimits_`,
`updatePlot_`, `updateThresholdOverlay_`, `yAxisLabel_`) into a new `obj/+gui/@StaircasePlot/`; drop
`& gui.PopOut` from the classdef; give `gui.StaircasePlot < gui.PopOut` a `Staircase` property and
invert `getPlotData_` so the plot pulls from the model. `stair.popOut()` becomes
`gui.StaircasePlot(stair)`.

**`psychophysics.Staircase`'s class name does not change** — trial selectors reference it and it is
plausibly persisted.

**Verify the cycle is gone:** `git grep -n "gui\." obj/+psychophysics/ | grep -v '^\S*: *%'` → zero.
**Gate:** core + `_staircase_plot`, `_popout`, `_session_performance`.

### Stage 7 — GUI application moves (**riskiest**)

Three commits, smallest first, so a failure is bisectable.

**7a — `DefaultSubject` dialog.** Extract the embedded uifigure from
`obj/+epsych/@DefaultSubject/DefaultSubject.m` (451 lines) into `obj/+gui/@AddSubjectDialog`.
**`epsych.DefaultSubject` stays** — `FUNCS.AddSubjectFcn` is persisted by name and
`design/ep_AddSubject.m` wraps `.open`. `.open` remains the entry point and now constructs the
dialog. Gate: `_add_subject_dialog`.

**7b — `teensy.TrialDesigner` → `gui.TrialDesigner`.** 12 files; call sites `LaunchUtility.m:42`,
`teensy/Contents.m:6`, `Templates.m:20`, `Program.m:57`, `Simulator.m:53`; banner line is already
commented out. Gate: `_teensy_designer`, `_teensy_dialogs`.

**7c — `epsych.ProtocolDesigner` → `gui.ProtocolDesigner`** (203 files incl. `private/`). Call sites:
`epsych_printBanner.m:34`, `LaunchUtility.m:40`, `RunExpt.m:248`, `SubjectManager.m:801`, plus
`See also` in `Protocol/dependencyGraph.m:9`, `hw/@Bpod/getCreationSpec.m:5`,
`hw/@Intan_RHX/Intan_RHX.m:71`. **Two that `codeIssues` will not catch — grep for them explicitly:**
[ExptDispatch.m:65](obj/+epsych/@RunExpt/ExptDispatch.m#L65), where the name is inside an HTML
`matlab:` link string, and `smoke_test_coefficient_buffer_param.m:22-29`, which reads **six exact
source paths** under the old folder. While in there, replace those path reads with
`which('gui.ProtocolDesigner')`-relative resolution so the next move doesn't break it.

Also update `.claude/skills/update-wiki/survey.sh:159` (and `:167-169,185,190`), `pagemap.tsv` rows,
and move the ProtocolDesigner docs from `documentation/epsych/` to `documentation/gui/`.

Because `epsych.RunExpt` does **not** move, `smoke_test_epsychinfo_worktree.m:63`'s
`fullfile('obj','+epsych','@RunExpt')` stays valid.

**Gate:** full suite + `_protocoldesigner_toolbar`, `_coefficient_buffer_param`, `_expression_check`,
`_add_subject_dialog`.

### Stage 8 — `PRGMSTATE` → `epsych.PRGMSTATE` (conditional — see below)

Verified safe from persistence: `SaveConfig` writes only `config`/`funcs`/`meta` and never `STATE`;
`strings` over the `.ecfg`/`.eprot` fixtures finds no `PRGMSTATE`; `PRGMSTATE.fromString` has zero
callers; and there are **zero** references in `paradigms/`, `runtime/`, `examples/`, `helpers/`,
`design/` — all 82 hits are `obj/`, `tests/`, `documentation/`.

```
git mv obj/PRGMSTATE.m obj/+epsych/PRGMSTATE.m
```

82 sites become `epsych.PRGMSTATE.*`; update the tripwire entry
[checkEnvironment.m:57](obj/+epsych/@SelfTest/checkEnvironment.m#L57) from `"PRGMSTATE"` to
`"epsych.PRGMSTATE"`, plus `Architecture_Overview.md:38,216` and `Class_Map.md:45`. This leaves `obj/`
with no loose files, which is the actual structural win.

> **Do this last, isolated, and confirm first.** An enumeration **cannot be shimmed** — you cannot
> subclass one, and a forwarding function can't support `PRGMSTATE.RUNNING` dot syntax. If any lab
> rig has an out-of-repo BehaviorGUI, TimerFcn, or TrialSelector referencing `PRGMSTATE` (the
> in-repo `gui.BehaviorGUI:658` does), this breaks it with no recovery path. **If you can't confirm
> that, drop Stage 8** — nothing depends on it and it has the smallest payoff in the plan.

### Stage 9 — Bug fixes and final sweep (low risk)

- **`getRepositoryRoot`** ([obj/+gui/@ProtocolDesigner/private/getRepositoryRoot.m](obj/+epsych/@ProtocolDesigner/private/getRepositoryRoot.m),
  post-7c path) climbs 3 `fileparts` levels from `.../private/`, landing on `obj/+epsych` — not the
  repo root. Callers `getBrowseStartPath.m:7` and `getParameterFileStartPath.m:29` open dialogs in the
  wrong folder today. Replace the climb with `epsych_path` so it cannot drift again.
- **Declare the abstract bases abstract.** `hw.Interface` and `epsych.TrialSelector` are documented as
  abstract but declared without `(Abstract)`, so both are instantiable. **Gate this hard and do it
  last** — if any concrete subclass fails to implement a newly-abstract method, that subclass stops
  loading. Run the full suite plus every `hw.*` test; back it out if anything trips. It is cosmetic.
- **`design/`** holds only `ep_AddSubject.m`, a name-resolution shim for saved `.ecfg` files.
  `plans/remove-config-subsystem.md` already slates every such shim for deletion — leave it to that
  plan rather than pre-empting it here, but don't leave a one-file top-level directory afterward.
- Final audit of `CLAUDE.md` (48 path refs + layout table), `documentation/` (43 files, 220
  `obj/+pkg` mentions), `pagemap.tsv`, `survey.sh`. Do the mechanical sed **per stage**; reserve this
  pass for prose needing a human sentence (the RunExpt exception rule, the PRGMSTATE note).
  `.claude/skills/commit/*.sh`'s hardcoded `obj/stimgen` stays valid — verify only.

---

## Verification

There is no CI, so **Stage 3's `tests/runAll.m` is the gate for everything after it.** Run MATLAB
through the `matlab-mcp-server`; never `clear`, `close all`, or `restoredefaultpath` in it.

1. **`codeIssues` diff after every stage** — any new error-severity unresolved identifier is a broken
   call site. This is the mechanical check; smoke tests are the behavioural one.
2. **Fresh `matlab -batch` to close each stage.** The persistent MCP session holds stale class
   definitions after a move and will report false passes. Use it for iteration, a fresh process for
   the verdict.
3. **Saved-file compatibility after Stages 4, 7, 8** — the one thing `runAll` will not catch. Load
   `tests/fixtures/TEST_NEW_PROTOCOL2.eprot` and `AversiveDetectionConfig.ecfg` and assert no
   interface came back as an unexpected `hw.Software` stub; that is exactly how a broken name
   resolution presents itself.
4. **`epsych.SelfTest`** — check A3 verifies the stimgen contract, `checkEnvironment` verifies the 23
   required names. It is the repo's own tripwire for this class of change.
5. **GUI smoke at the end** — launch `epsych.RunExpt`, `gui.ProtocolDesigner`, and the Subjects &
   Projects window. `exportapp` screenshot capture needs `matlab -batch`, not the MCP session.

## Out of scope

- **`epsych.RunExpt`'s 47 PascalCase method renames** — deferred per your call; collides with
  `plans/remove-config-subsystem.md`. Restated here so Stage 5 doesn't reintroduce it.
- **`gui.components.Parameter_Control` / `Parameter_Update` / `Parameter_Monitor` renames.** I proposed these as
  "cheap" when asking; they are not. 124 code sites, 75 doc mentions, and they are live public API
  used directly in `examples/syringepump/`, `paradigms/BehaviorGUIs/`, and `runtime/guis/@ep_GenericGUI/`
  — every lab's custom BehaviorGUI would break with no shim. Worth doing as its own change with a
  deprecation alias, not folded into a move.
- **Splitting the 1,000–1,900-line `+gui` classes** (`SyringePump` 1943, `Parameter_Monitor` 1537,
  `SubjectManager` 1426). This reorg makes the `+gui` line-count imbalance worse, and that is fine:
  mixing a *content* refactor into a *move* refactor destroys `git log --follow` and makes review
  impossible. Immediate follow-up.
- **Any package rename**, and **moving `obj/+pkg` up to `+pkg`** (the Aggressive option).
- **Merging `runtime/` and `paradigms/`** despite their identical three-way shape — `runtime/`'s 7
  files are all resolved by *bare name* from persisted `.ecfg` fields and five are in the tripwire.
- **Converting the 94 smoke scripts to `matlab.unittest`.** `runAll.m` is deliberately a ~60-line
  script runner, not a framework migration.
