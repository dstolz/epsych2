# What lives on which wiki page

`pagemap.tsv` (next to `SKILL.md`) is the machine-readable version — `survey.sh`
reads it to turn changed files into a page list. This file explains what each
page is *for*, so you can tell whether a change belongs on it. **Add a row to the
TSV whenever you add a page or a class folder.**

## 🧪 Using EPsych — the operator path

GUI-first. The reader has MATLAB open and a rig in front of them; they do not
write MATLAB against the framework.

| Page | Owns |
|---|---|
| `Installation-and-Setup` | MATLAB version, cloning with submodules, `epsych_startup`, TDT software, first-run checks |
| `Quick-Start` | One end-to-end session with no hardware, using `examples/detection_task/` |
| `Designing-Protocols` | Protocol Designer: parameters, interfaces dialog, options, expressions, compiled preview, `.eprot` |
| `Running-a-Session` | RunExpt: subjects, `.ecfg` configs, trial preview, run/pause/stop, Self-Test entry point |
| `Stimuli-and-Calibration` | StimPlayer, speaker calibration, dB SPL → volts (links out to stimgen) |
| `Parameter-Files-and-Phases` | Phase `.eprot` files, PhaseSelector, what a phase load does and does not restore |
| `Training-and-Online-Analysis` | Staircase training, history, performance plots, session metrics |
| `Building-a-Box-GUI` | Subclassing `gui.BehaviorGUI`: lifecycle, `build(fig)`, event hooks, teardown |
| `Box-GUI-Components` | The parts list — one `###` section per `obj/+gui/` component, each with its own screenshot |
| `Generating-a-Box-GUI-with-AI` | Prompting a model to draft a behavior GUI, and verifying what it produced |
| `Teensy-Trial-Designer` 🚧 | The designer GUI, templates, test bench |
| `Video-and-Peripherals` | VLC recording, syringe-pump reward (`hw.NE1000` + `gui.SyringePump`), motorized commutators |
| `Data-and-Save-Functions` | What is saved, the trial journal, decoding `epsych.BitMask` outcomes, custom save functions |
| `Troubleshooting` | Self-Test failures, `.error_logs/`, verbosity, common breakages |

## 🔧 Developing EPsych — the extender path

The reader writes MATLAB against the framework.

| Page | Owns |
|---|---|
| `Developer-Orientation` | Repo map, architecture, where to look when changing things |
| `Runtime-and-Events` | `epsych.Runtime`, the timer chain, `NewTrial`/`NewData`/`ModeChange` |
| `Trial-Lifecycle` | A trial from dispatch to save, and every hook point along it |
| `Protocol-Internals` | `epsych.Protocol`, compilation, `toStruct`/`fromStruct`, parameter expressions |
| `Hardware-Abstraction-Layer` | `hw.Interface`/`Module`/`Parameter` contract, the backend inventory and maturity |
| `Writing-a-Hardware-Backend` | The tutorial, including the **four** hardcoded registry sites |
| `Stimgen-Integration` | The `stimbridge` seam and the submodule contract — *never* the stimgen class list |
| `Trial-Selectors` | `epsych.TrialSelector` subclassing, closed-loop selection |
| `Psychophysics-Framework` | `psychophysics.Psych` and friends, `SessionMetrics`, writing an analyzer |
| `GUI-Framework-Internals` | How `gui.BehaviorGUI`, the registry, `gui.PopOut`, and preferences work under the components |
| `Teensy-Program-Model` 🚧 | `teensy.Program`/`Compiler`/`Simulator`, the wire protocol |
| `Contributing-and-Conventions` | Coding conventions, logging policy, commit practice, submodule rules |

## 📄 Reference Overviews — mirrors

Seven pages that mirror `documentation/overviews/*.md` **1:1**. The repo copy is
authoritative; the wiki copy carries the mirror note under its H1 and exists only
so the content is browsable from the wiki. Regenerate rather than edit.

| Wiki page | Repo source |
|---|---|
| `Toolbox-Overview` | `documentation/overviews/Toolbox_Overview.md` |
| `Installation-Guide` | `documentation/overviews/Installation_Guide.md` |
| `RunExpt-GUI-Overview` | `documentation/overviews/RunExpt_GUI_Overview.md` |
| `RunExpt-SelfTest` | `documentation/overviews/RunExpt_SelfTest.md` |
| `Architecture-Overview` | `documentation/overviews/Architecture_Overview.md` |
| `Class-Map` | `documentation/overviews/Class_Map.md` |
| `Commit-History-Overview` | `documentation/overviews/CommitHistoryOverview.md` |

Link rewrites when regenerating a mirror:

- a link to another overview → the wiki page name (`[Architecture_Overview.md](Architecture-Overview)`)
- `../` or `../../` paths into the repo → `https://github.com/dstolz/epsych2/blob/master/…`
- `obj/stimgen/…` → the stimgen repository URL
- `+package` in a URL is `%2B`

## Adding a page

1. Create `Page-Name.md` in the wiki clone. The file name *is* the URL; use
   hyphens, and title-case the words.
2. `# <img src="images/icons/<icon>.svg" width="26" height="26" alt=""> Title` if
   the section has an icon; a plain `# Title` otherwise.
3. Add it to `_Sidebar.md` under the right section, and to the matching table in
   `Home.md` with a one-line "what it gets you" cell.
4. Add a `pagemap.tsv` row so the next survey routes changes to it.
5. `verify.sh` will tell you if you missed step 3.

## Known discrepancies to keep in mind

Points where the code beat the docs, found during earlier passes — check before
repeating them:

- Registering a backend touches **four** sites, not the three CLAUDE.md lists.
- `psychophysics.Detection` is a standalone handle class, **not** a
  `psychophysics.Psych` subclass.
- The behavior GUI is set from **Customize → Customize…** in RunExpt.
