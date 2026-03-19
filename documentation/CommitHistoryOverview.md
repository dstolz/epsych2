# Commit History Overview

Period covered: 2026-01-01 through 2026-03-19

## March 2026

- 169 commits. The month was dominated by a broad runtime and GUI modernization pass centered on the newer RunExpt flow, RUNTIME-handle propagation, recent-configuration support, runtime filename updates, and cleaner parameter wiring across GUI and psychophysics classes.
- Adaptive timing and training behavior expanded substantially. Response-window delay randomization, evaluator-driven parameter updates, stimulus-delay controls, pre-stimulus offset handling, ProgressiveTrainingGUI, and Staircase training mode all landed or were refined during this period.
- Staircase became a major development focus. Commits repeatedly tightened reversal detection and threshold calculations, added decibel conversion support, improved listener and history handling, and expanded plotting with richer plot management, response-code colors, BitMask-derived defaults, and context-menu interactions.
- GUI behavior was polished in parallel, including updated performance and abort-rate displays, normalized layout adjustments, clearer row ordering in history views, and updated appetitive/aversive GUI integration with newer psychophysics objects.
- Hardware and recording support expanded quickly. The project added VlcRecorder, then extended it to multi-camera and frame-rate-aware workflows, introduced NanoMotorControl and NanoMotorControlGUI, and retired older standalone WebcamRecorder and deprecated figure-based paths.
- Documentation and project guidance also accelerated sharply, with new or expanded guides for RunExpt GUI behavior, custom EPsych GUIs, Staircase, BitMask, vprintf, Parameter classes, and MATLAB coding/commenting conventions.

## February 2026

- 17 commits. Work in February established the next wave of GUI and training features, starting with a pellet-focused appetitive-detection GUI that added trial controls, sound settings, and a modal save-data workflow.
- Parameter monitoring became a clear theme. The month introduced Parameter_Monitor, replaced simpler total-pellet displays with monitor-table behavior, added trigger support to Parameter, and expanded Parameter_Control event and type handling.
- Trial execution and training logic also broadened. Commits added variable response-window delay support, the initial training UI around that behavior, an appetitive stimulus-detection trial-selection routine, and repeated adjustments to NO-GO, false-alarm, depth, and probability logic.
- Several smaller usability commits improved button styling, font sizing, control layout, sound-level editing, and help text, showing an early emphasis on making the new GUI workflows easier to operate.

## January 2026

- 0 commits were recorded in this repository during January 2026.

## Overarching Trends

- The project shifted toward parameter-driven GUI behavior and explicit runtime-state management rather than older global or figure-centric patterns.
- Adaptive psychophysics and training workflows became a central product direction, especially through response-window control, ProgressiveTraining, and deeper Staircase integration.
- Staircase evolved from a supporting analysis tool into a core workflow component spanning online execution, threshold logic, and visualization.
- Hardware integration broadened while legacy paths were actively removed, indicating a move toward newer recorder and device-control abstractions.
- Documentation matured alongside implementation, with mid-March showing a particularly strong push to codify usage patterns, APIs, and coding standards.
