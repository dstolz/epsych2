# EPsych2 graphics package — Three-Channel TTL theme

Proposal assets. Nothing here is installed in the repository yet.

Replaces the previous Instrument theme. The mark is a timing diagram: an analog tone
burst on top, the stimulus gate that carries it, and the response strobe it triggers.

Ink #1d2d3d · accent #5980a6 · paper #f2f2f3 · CH2 #94bce3 · burst #b5d9fd
Type: Barlow Condensed (headings) / Barlow (body). Icons on a 24px grid, stroke 1.5.

## Files

- `banner.svg` — wiki home banner, 1280x320
- `workflow-diagram.svg` — experimenter workflow: design -> configure -> run -> analyze
- `architecture-diagram.svg` — GUIs / epsych core / stimgen / psychophysics / hw.Interface
- `logo.svg` — the three-channel mark
- `logo-outline.svg` — line variant for light grounds
- `favicon.svg` — simplified mark for 32px
- `favicon-16.svg` — single-channel fallback for 16px
- `icons/*.svg` — ten doc-section icons: install, protocol-design, run-session, calibration,
  stimulus-generation, hardware, trial-selection, analysis, box-gui, data-saving

## Notes

All assets are SVG and recolor by editing the stroke/fill values above.
Below 24px the mark drops to a single TTL channel (`favicon-16.svg`) — the stacked
three-channel version smears at that size.

The wiki carries its own copy of these files in `images/`; edit here first, then copy
over (the wiki cannot reference this repo by relative path).
