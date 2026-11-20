# EPsych examples

Runnable examples, one folder each. Run them from the repository root after
`epsych_startup`. Most create their own protocol the first time (those generated
`.eprot` files are not tracked), then open a session you can play through.

## Walkthroughs: you are the subject

No hardware needed. `first_experiment`, `two_afc` and `detection_task` each have a
matching walkthrough in [documentation/examples/](../documentation/examples/);
`oddball` is documented by its own README.

| Folder | What it is | Start with |
|---|---|---|
| [`first_experiment/`](first_experiment/README.md) | A go/no-go flash detection task, the smallest complete experiment | `run_first_experiment.m` |
| [`two_afc/`](two_afc/README.md) | Two-alternative forced choice: which side was brighter | `run_2afc_experiment.m` |
| [`detection_task/`](detection_task/README.md) | Simulated go/no-go tone detection with a custom trial selector, behavior GUI and offline analysis | `run_detection_session.m` |
| [`oddball/`](oddball/README.md) | Auditory oddball: respond to the deviant among standards | `run_oddball_experiment.m` |

## Components and tools

| Folder | What it is | Start with |
|---|---|---|
| [`customgui/`](customgui/) | A template `gui.BehaviorGUI` subclass, runnable against a software runtime | `run_example.m` |
| [`syringepump/`](syringepump/README.md) | A session exercising `gui.components.SyringePump` | `run_pump_session.m` |
| [`hw_benchmark/`](hw_benchmark/README.md) | Protocols for `hw.benchmarkIO` (Utilities > Hardware > I/O Benchmark...): a TDT RPvds circuit and protocol, and a Software-only protocol | add a subject with `HwBenchmark_Software.eprot` and run the menu item |
| [`stimgen/`](stimgen/README.md) | TDT circuits and demo protocols for the `stimgen` submodule, which ships them only from here | see its README |

## Conventions

- A folder holds its own `README.md`, a `create_*_protocol.m` where a protocol is
  built in code, and a `run_*` script that starts the session.
- A protocol is tracked when it is hand-built or hardware-specific
  (`stimgen/`, `hw_benchmark/`). One that a `create_*` script regenerates from
  code is gitignored, and its `data/` output with it.
- A protocol stores the absolute path of any RPvds circuit it uses. After moving
  or cloning, re-point it in `epsych.ProtocolDesigner` before the first Run.
