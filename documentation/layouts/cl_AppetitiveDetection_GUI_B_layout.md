# cl_AppetitiveDetection_GUI_B Layout Summary

This document summarizes the layout structure of the GUI created by `cl_AppetitiveDetection_GUI_B.create_gui`. The GUI is organized using an 11-row by 7-column `uigridlayout`, with a variety of panels, controls, and plots arranged to support the Appetitive Detection experiment workflow.

## Layout Structure Overview

- **Main Layout:** 11 rows × 7 columns grid (`uigridlayout`)
- **Row Heights:** `[60, 40, 90, 110, 60, 130, 40, '1x', '1x', '1x', 40]`
- **Column Widths:** `[150, 150, 100, '1x', '1x', '1x', '1x']`
- **Padding:** `[1 1 1 1]`

### Notable Features
- Extensive use of nested `uigridlayout` and `uipanel` for modular grouping.
- Dedicated panels for trial controls, sound controls, trial filtering, filename entry, next trial preview, performance, and response history.
- Large central area for the main psychometric plot.
- Several rows and columns are shared by multi-row/column panels.

## Component Placement Table

| Component/Panel           | Rows        | Columns     | Notes |
|--------------------------|-------------|-------------|-------|
| Control Buttons          | 1           | 1–4         | Nested 2×3 grid for experiment controls |
| Phase Selector           | 1–2         | 5           | Only if phase directory exists |
| Trial Controls Panel     | 2–6         | 1–2         | Contains staircase and trial parameter controls |
| Sound Controls Panel     | 7–8         | 1–2         | Sound parameter controls |
| Info Table Panel         | 6–10        | 3–4         | Parameter monitor table |
| Commit Button            | 9–10        | 1–2         | Update parameters button |
| Trial Filter Panel       | 9–11        | 1–3         | (Commented out in code) |
| Filename Panel           | 11          | 3–5         | Filename entry and validation |
| Next Trial Panel         | 1–2         | 6           | Next trial preview table |
| Performance Panel        | 1–2         | 7           | Session performance label |
| Main Plot (Axes)         | 3–5         | 3–7         | Psychometric/behavioral plot |
| Microphone Axes          | 9–10        | 5           | Microphone RMS plot (commented out) |
| Response History Panel   | 6–11        | 6–7         | Response history table |

### Unoccupied Spaces
- **Rows 7–8, Columns 3–7:** Unoccupied (except for Sound Controls in 1–2)
- **Rows 9–11, Columns 4, 6–7:** Partially unoccupied (Trial Filter, Microphone, and Response History occupy some)
- **Row 11, Columns 1–2, 6–7:** Unoccupied

## Text Diagram of Layout

```
Rows ↓ / Cols → | 1     | 2     | 3     | 4     | 5     | 6     | 7     |
---------------|-------|-------|-------|-------|-------|-------|-------|
1              | Btns  | Btns  | Btns  | Btns  | Phase | Next  | Perf  |
2              | Trial | Trial |       |       | Phase | Next  | Perf  |
3              |       |       | Main Plot (3–7)                |
4              |       |       | Main Plot (3–7)                |
5              |       |       | Main Plot (3–7)                |
6              | Trial | Trial | Info  | Info  |       | RespH | RespH |
7              | Sound | Sound |       |       |       | RespH | RespH |
8              | Sound | Sound |       |       |       | RespH | RespH |
9              | TFil? | TFil? | TFil? |       | Mic?  | RespH | RespH |
10             | TFil? | TFil? | TFil? |       | Mic?  | RespH | RespH |
11             |       |       | File  | File  | File  |       |       |
```
- **Btns:** Control Buttons
- **Phase:** Phase Selector
- **Trial:** Trial Controls
- **Sound:** Sound Controls
- **Info:** Info Table
- **TFil?:** Trial Filter (commented out)
- **File:** Filename Panel
- **Next:** Next Trial
- **Perf:** Performance
- **Main Plot:** Psychometric/behavioral plot
- **Mic?:** Microphone Axes (commented out)
- **RespH:** Response History

## Observations
- The main plot and response history occupy the largest contiguous areas.
- Several panels are conditionally included or commented out (e.g., Trial Filter, Microphone Axes).
- The layout is designed for clarity and quick access to experiment controls and monitoring.

---

*This summary was generated from the layout code in cl/@cl_AppetitiveDetection_GUI_B/create_gui.m.*
