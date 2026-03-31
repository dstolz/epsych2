# cl_AppetitiveDetection_GUI_B GUI Layout Summary

This document summarizes the layout structure of the GUI created by `create_gui.m` for the Appetitive Detection experiment. The summary includes a table mapping components to their grid positions, a description of the layout, and a diagram to illustrate the structure.

---

## Layout Structure Overview

The main GUI uses an 11-row by 7-column `uigridlayout` as its primary container. Components are placed in specific rows and columns, with some spanning multiple cells. The layout is designed to group related controls (buttons, parameters, plots, tables) into logical regions, with clear separation between control panels, information displays, and plots.

Notable features:
- Top rows (1-2) are used for control buttons and phase/performance panels.
- Central columns (3-7) and rows (3-5) are dedicated to the main psychometric plot.
- Side columns (1-2) and rows (2-6) contain trial and sound controls.
- Lower rows and rightmost columns are used for filename, next trial, performance, and response history panels.
- Several rows and columns are left unoccupied, providing space for future expansion or visual separation.

---

## Component Grid Mapping Table

| Component                        | Rows      | Columns   | Notes/Description                                 |
|-----------------------------------|-----------|-----------|---------------------------------------------------|
| Control Buttons                  | 1         | 1-4       | Button grid: Drop Pellet, Shape, Reminder, etc.   |
| Phase Selector                   | 1         | 5         | Phase selection panel (if phase dir exists)       |
| Session Performance Panel        | 1-2       | 7         | Performance label                                 |
| Next Trial Panel                 | 1-2       | 6         | Table for next trial info                         |
| Trial Controls Panel             | 2-6       | 1-2       | Staircase, trial, and timing controls             |
| Sound Controls Panel             | 7-8       | 1-2       | Sound level, duration, modulation controls        |
| Info Table Panel                 | 6-10      | 3-4       | Parameter monitor table                           |
| Main Psychometric Plot           | 3-5       | 3-7       | Main experiment plot (axes)                       |
| Filename Panel                   | 11        | 3-5       | Filename validator                                |
| Response History Panel           | 6-11      | 6-7       | Response history table                            |
| (Unoccupied)                     | 9-10      | 1-2       | (Commit button placed here, not a panel)          |
| (Unoccupied)                     | 9-11      | 6-7       | (Old performance panel, commented out)            |
| (Unoccupied)                     | 9-11      | 1-3       | (Trial filter panel, commented out)               |

---

## Unoccupied Spaces

- Several grid cells, especially in the lower left (rows 9-11, columns 1-2) and some central cells, are unoccupied or reserved for future use.
- Some panels (e.g., trial filter, old performance) are present in code but commented out.
- The commit button ("Update Parameters") is placed in rows 9-10, columns 1-2, but does not occupy a full panel.

---

## Text Diagram of Main Layout

```
Rows ↓ / Cols → | 1      | 2      | 3      | 4      | 5      | 6      | 7
---------------|--------|--------|--------|--------|--------|--------|--------
1              | Btns   | Btns   | Btns   | Btns   | Phase  | Next   | Perf
2              | Trial  | Trial  |        |        |        | Next   | Perf
3              | Trial  | Trial  | Psych Plot (3-7)                        
4              | Trial  | Trial  | Psych Plot (3-7)                        
5              | Trial  | Trial  | Psych Plot (3-7)                        
6              | Trial  | Trial  | Info   | Info   |        | RespH  | RespH
7              | Sound  | Sound  | Info   | Info   |        | RespH  | RespH
8              | Sound  | Sound  | Info   | Info   |        | RespH  | RespH
9              |        |        | Info   | Info   |        | RespH  | RespH
10             |        |        | Info   | Info   |        | RespH  | RespH
11             |        |        | Filename (3-5)         | RespH  | RespH
```
Legend:
- Btns: Control Buttons
- Phase: Phase Selector
- Next: Next Trial Panel
- Perf: Performance Panel
- Trial: Trial Controls Panel
- Sound: Sound Controls Panel
- Info: Info Table Panel
- Psych Plot: Main Psychometric Plot
- Filename: Filename Panel
- RespH: Response History Panel

---

## Summary

The GUI layout is highly modular, with clear separation of control, information, and visualization areas. The use of a large grid allows for flexible arrangement and future expansion. Some areas are intentionally left unoccupied or are reserved for features that are currently commented out in the code.

For further details, see the code in `cl/@cl_AppetitiveDetection_GUI_B/create_gui.m`.
