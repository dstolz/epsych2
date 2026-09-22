# uihtml for EPsych Behavior GUIs: assessment

## Context
The question is whether MATLAB's `uihtml` (HTML/CSS/JS in an iframe inside a uifigure) would
be a good way to build Behavior GUI controls. This file answers the three questions asked and
ends with an optional follow-up: a short test script to settle the points that can only be
checked by running MATLAB.

**Checked in this session**
- The rig runs R2024b Update 6.
- `matlab.ui.control.HTML` provides `Data`, `DataChangedFcn`, `HTMLSource`,
  `HTMLEventReceivedFcn`, `sendEventToHTMLSource`, `ContextMenu`, `Tooltip` and a `ViewReady`
  event.
- It has **no** `Value`, `Enable`, `BackgroundColor` or `FontSize`.
- Nothing in the repo uses `uihtml`, `Interpreter='html'`, or JavaScript today.

---

## 1. Integration: is it seamless? No for controls, reasonably yes for displays

**What already fits**
- `gui.BehaviorGUI.add`/`register`/teardown accept any handle object.
- A new `gui.components.*` class that declares a `gui.ComponentSpec` shows up on
  `gui.BehaviorBuilder`'s palette with no builder edits (`ComponentSpec.packageSpecs`).
- A `gui.PopOut` window is just a second instance, so it is another `uihtml` using the same
  source file.
- `add()` turns a failed constructor into a logged skip, which keeps SelfTest I6 passing.
- Display components already rebuild from the full `DATA` array on each event, so a uihtml
  view can just render what MATLAB sends it.

**What is not seamless: `hw.Parameter` controls.** The value of `Parameter_Control` (1765
lines) is its binding logic, and that logic is written directly against native widgets:
- PostSet listeners on `Value`, bounds and the interface `mode`.
- Two separate enable gates.
- `ValueUpdated` feeding `Parameter_Update`.
- The autoCommit, trial-table write-back and `SessionNotes` path.
- `ModifierActions` and the cached pre-arm appearance.

It also relies on reading and writing widget state synchronously: reverting a
`uistatebutton`'s `Value`, validating a range pair, and setting `Limits` from `Min`/`Max`.
`BehaviorGUI.wireUpdateButtons_` finds controls with `isa(c,'gui.components.Parameter_Control')`,
and the smoke tests find widgets by `Tag` (`PC_<Name>`).

**Specific friction points**
1. **The bridge is asynchronous.** The iframe holds its own state, and MATLAB cannot read a DOM
   value synchronously. MATLAB has to own the state and the page only renders it, which is the
   opposite of how `Parameter_Control` works today.
2. **Data is converted to JSON, and some values are lost.**
   - NaN and ±Inf become `null`. `hw.Parameter.Min`/`Max` default to ±Inf, and NaN means
     "not measured" and "Undefined" throughout the toolbox.
   - A cell array `Values`, `StimType` objects, and the logical/double distinction also need an
     explicit encoding. This is the same trap that made `SubjectRoster` store MAT instead of JSON.
3. **Keyboard.** When the iframe has focus, the uifigure stops delivering window key events, as
   it already does for edit fields (`KeyBindings.m:35-40`). While the HTML has focus:
   - `KeyBindings` chords do nothing.
   - `ModifierActions` never arms.
   - `RegenerateTrial`'s Ctrl+Alt+Shift gate stays dead.

   One upside: a JS click event carries `ctrlKey`/`shiftKey`/`altKey` with the click. But that
   is a second source of modifier state that `KeyBindings` does not know about.
4. **Right-click menus.** "Open in Separate Window", "Keep Window on Top", Select Traces,
   Editable and Units are all MATLAB `ContextMenu`s. Whether a right-click *inside* the iframe
   opens a MATLAB `ContextMenu` is **unverified**. If it does not, the menu has to be rebuilt in
   JS, so the menu logic lives in two places.
5. **ScreenCapture.** It uses `exportapp`, and whether that captures uihtml content is
   **unverified**.
6. **Tests cannot see inside.** Smoke tests find widgets by Tag and poke `Value`, but the DOM is
   invisible to MATLAB. Only the MATLAB side can be tested, by synthesizing
   `HTMLEventReceived` events. There is no node or JS test runner here.
7. **Each instance is an iframe.** That is fine for five panels and wasteful for forty
   parameter controls. The workable pattern is one `uihtml` per panel holding many items.
8. **Look and feel.** The CSS must imitate uifigure fonts and colors by hand, native and HTML
   widgets side by side look inconsistent, and a figure theme is not inherited.
9. **Security.** A shared roster or protocol is a source of untrusted text.
   - Render with `textContent`, never `innerHTML`.
   - Send links through `SubjectRoster.isSafeUrl`/`openLink`, not a bare `<a href>`.
   - The MATLAB event handler must whitelist event names and never `feval` a payload.
10. **Two languages.** JS exceptions are silent unless forwarded to `vprintf` as an event.
    Libraries must be vendored (rigs may be offline, so no CDN), and nobody in the lab owns a JS
    toolchain.
11. **Version floor.** `uihtml` needs R2019b and its event API needs R2023a. That is fine on the
    rigs but above the stated R2014b baseline for those components.

**Pros**
- **Styling per element.** Per-row and per-cell colors, per-row dropdowns, badges, inline
  links, rich text and SVG icons. These fix documented limitations directly:
  - `uitable` ColumnFormat is per column (SubjectManager, ParameterDebugger).
  - `uilistbox` has no per-item styling.
  - `uitextarea` cannot hold a link (MetricsExplorer).
  - `uibutton` Icon accepts only four names (`toolbarIcon` pixel art).
  - `uigridlayout` has no ContextMenu.
  - `uicheckbox` and `uiswitch` have no BackgroundColor.
- **Cheap incremental updates.** Appending a DOM row costs almost nothing, while each `uitable`
  property set costs about 30-40 ms (History pads rows in blocks to work around this,
  `History.m:10-18`).
- **Clocks and animation run in the browser.** `SessionClock` (1 Hz timer), `ElapsedTrialTimer`
  (2 Hz timer) and color flashes (`gui.Helper.timed_color_change` makes one MATLAB timer per
  flash) could tick in JS with no MATLAB timers.
- **Layout.** CSS grid/flex, collapsible `<details>`, sticky headers, virtualized long lists,
  and drag-to-reorder in place of the reorder dialogs (`OnlinePlot.reorderTraces`,
  `SessionPerformance.reorderMetrics`).
- **Modifier state arrives with each click**, with no window-level tracking needed.
- **The view can be built in a browser** against a mock `htmlComponent`, without MATLAB.

**Cons (short list)**
- The async bridge, and state that lives in two places.
- JSON loses NaN and Inf.
- Keyboard and modifier tracking stop while the HTML has focus.
- Right-click menus and `exportapp` are unverified.
- The DOM cannot be tested from MATLAB.
- Iframe overhead per instance.
- Visual mismatch with native widgets.
- A new injection surface.
- A second language to maintain.

**Recommendation.** Keep native widgets for anything that *writes* hardware:
`Parameter_Control`, `Parameter_Update`, `RegenerateTrial`, `SessionGate`, and the pump and
motor panels. Use `uihtml` for displays and dialogs that are mostly read-only, show many items,
and need rich styling. Use one iframe per panel. Put the shared plumbing in one small base class
that every HTML component reuses:
- a JSON codec that keeps NaN and Inf;
- a ViewReady handshake plus a queue for messages sent before the page loads;
- an event-name whitelist;
- forwarding of JS errors to `vprintf`;
- theme CSS variables;
- `PreferenceTag` persistence.

---

## 2. Existing components: which would benefit from uihtml

| Component | Today | What uihtml fixes | Verdict |
|---|---|---|---|
| `gui.components.History` | `uitable`, ~30-40 ms per property set, rows padded in blocks, colors set through a BackgroundColor array | Appending a DOM row is incremental; outcome colors are CSS classes; header stays fixed | **Strong**: the clearest measured problem |
| `gui.SubjectManager` (subject grid only) | `uitable` + `uistyle`; no per-row protocol dropdown; "(archived)" added to text; a hand-built modal because `uiconfirm` allows only 4 options | Per-row dropdowns, template/edited and `vN (held)` badges, styled list items | **Strong**, but the window is 4.7k lines, so replace the grid first |
| `gui.ParameterDebugger` | every column is char because ColumnFormat is per column; read status shown with `uistyle` | Each row gets an editor for its own type, the read status becomes a CSS class, a virtualized list | **Good** |
| `gui.MetricsExplorer` (explanation panel) | `uitextarea` cannot hold a link, so citations are a separately rebuilt grid of `uihyperlink`s | Links inside the text (routed through MATLAB), rendered formulas | **Good**: small and low risk, a good first target |
| `gui.compareProtocolVersions` | `uitable` + `uistyle` diff | Collapsible struct paths, inline old→new, added/removed/changed colors | **Good** |
| `gui.components.Parameter_Monitor` (table/text modes) | No text-extent API, no per-line hit testing, cannot reorder | Per-line menus, drag to reorder, measured widths; polling stays in MATLAB | Moderate |
| `gui.components.SessionPerformance` | `uigridlayout` has no ContextMenu; separate reorder dialog; labels resized in place to avoid flicker | Metric cards, drag to reorder, one menu target | Moderate |
| `gui.components.NextTrial` | `uitable` | A card layout that highlights what changed since the last trial | Moderate |
| `SessionClock` + `ElapsedTrialTimer` + `ModeIndicator` + `StatusBar` | Four widgets, two MATLAB timers at 1-2 Hz | One strip whose clocks tick in JS (see new component 1) | Moderate, only if merged; one iframe each is not worth it |
| `gui.components.Notes` (log view) | Plain `uitextarea` | Styled trial stamps, automatic entries distinct from typed ones, clicking a stamp seeks in a review | Moderate. Editable mode must stay a plain `uitextarea` (the `setText` rules) |
| `epsych.RunExpt` subject table | `uitable` + `uistyle` | Badges | Low priority: the main window is on the critical path |
| OnlinePlot, BufferPlot, PsychPlot, ParameterScatter, SlidingWindowPerformancePlot, ParameterTracker, the AdaptiveTraining and MetricsExplorer axes | MATLAB graphics | — | **No**. Axes give `exportgraphics`/`copygraphics`, duration rulers, and the same plots as offline analysis. A JS plot would send every sample through JSON and add a second plotting stack |
| Parameter_Control, Parameter_Update, RegenerateTrial, SessionGate, Triggers | Bind to hardware | — | **No**. Their binding and keyboard rules depend on synchronous native widgets and figure key events |
| SyringePump, NanoMotor, PhaseSelector, selectSerialPort, ReviewTransport, ComponentToolbar/toolbarIcon | Native widgets | Only cosmetic gains (the 56 px slider row, the pixel-art icons) | **No** |

---

## 3. New EPsych2 components that suit uihtml

Each of these holds many styled items in one view, and none writes hardware, so none hits the
friction points in section 1.

1. **SessionHeader strip.** Shows:
   - mode, subject and box;
   - trial number;
   - session clock and trial timer, both ticking in JS;
   - the last outcome as a colored chip;
   - dispensed volume.

   One iframe replaces four components and two MATLAB timers. In a review MATLAB sends the time
   instead of the browser keeping wall-clock time.
2. **TrialOutcomeStrip (timeline).** One colored cell per trial (Hit/Miss/FA/CR/Abort).
   - Hovering shows that trial's parameter values.
   - Clicking seeks `epsych.ReviewSession`.
   - Phase loads, block boundaries and notes are marked on the strip.

   SVG/CSS handles thousands of cells, and adding a trial appends one cell.
3. **Trial queue viewer.** Shows `TRIALS.trials` with:
   - the next trial highlighted;
   - pending `Parameter_Update` edits shown as a diff before they are committed;
   - later, an editor on each row for its own type, which `uitable` cannot do.

   Read-only at first.
4. **Multi-box rig overview.** One tile per box: subject, trial count, rates, and a warning when
   the pump is offline or the timer falls behind. A CSS grid reflows for any number of boxes.
5. **Operator checklist.** A pre-session checklist per paradigm, written as markdown with images.
   Ticking an item writes to `RUNTIME.NOTES`, and the list can optionally arm `SessionGate`.
6. **Instructions pane.** Shows the paradigm's `documentation/*.md` inside the GUI. Links go
   through `SubjectRoster.isSafeUrl`/`openLink`.
7. **Digital I/O and bitmask lamp panel.** An RPvds bitmask bank or Teensy channels as a labeled
   grid of LEDs, fed by the batched per-interface read `OnlinePlot` already uses. Dozens of lamps
   fit in one iframe instead of dozens of `uilamp`s.
8. **Teensy state-machine live view.** A `teensy.Program` drawn as an SVG state diagram with the
   current state highlighted. It could be reused in `teensy.TrialDesigner` and in the simulator's
   test bench. Larger than the others, because it needs a vendored graph-layout library.
9. **Parameter command palette.** Ctrl+K opens a fuzzy search over every parameter to jump to it
   or edit it. The chord is registered through `KeyBindings`, and Esc must hand focus back to the
   figure (the focus problem in section 1).
10. **End-of-session summary card.** Metrics, notes, and protocol changes since the last
    session. It copies as rich HTML for a lab notebook, alongside ScreenCapture's image, and can
    be saved next to the data file.
11. *(Speculative)* **Live camera preview.** A `uihtml` `<img>`/`<video>` showing a local VLC
    stream from `hw.VlcRecorder`. Loading a localhost stream in `uihtml` is unverified.

---

## Optional next step: a test script, no production code

Settle the unverified points before anyone builds anything. The script lives in the
scratchpad (not the repo): `spike_uihtml.m` plus `spike_view.html`, run with `matlab -batch`
because it uses `exportapp` and should stay out of the shared MCP session.

**Checks the script runs**
1. Does `Data` survive a round trip for NaN, ±Inf, logical, cell and empty values?
2. Is a `sendEventToHTMLSource` sent before `ViewReady` queued or dropped?
3. What is the MATLAB→JS→MATLAB round-trip latency (median and p95 over 200 events)?
4. Does the `exportapp` PNG contain the uihtml pixels (check that the region is not blank)?
5. What are the build time and memory cost for N = 1, 10 and 40 `uihtml` instances?
6. Does it render under `-batch`/nodesktop (the SelfTest I6 path)?

**Manual checks on a rig (they need real focus and a mouse)**
1. Does `WindowKeyPressFcn` fire while the iframe has focus?
2. Does a right-click inside the iframe open the component's MATLAB `ContextMenu`?

**Result:** a short app note (`app-note` skill) with the numbers. It decides whether a first
component (the MetricsExplorer panel or History) is worth building.
