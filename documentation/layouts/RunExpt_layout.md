# RunExpt UI Layout Summary

This document summarizes the layout structure of the `RunExpt` UI as defined in [obj/+epsych/@RunExpt/buildUI.m](../../obj/+epsych/@RunExpt/buildUI.m).

## Layout Overview

The main UI is organized using a 2x2 `uigridlayout` within the main figure window. The layout is further subdivided into nested grid layouts for the bottom control bar and the right-side vertical button stack.

### Main Grid Structure

| Row | Column 1 (Left)         | Column 2 (Right)         |
|-----|------------------------|--------------------------|
| 1   | Subject Table          | Right-side Button Stack  |
| 2   | Bottom Control Bar     | (Unoccupied)             |

- **Row heights:**
  - Row 1: '1x' (fills available space)
  - Row 2: 40 px (fixed height)
- **Column widths:**
  - Column 1: '1x' (fills available space)
  - Column 2: 100 px (fixed width)

### Component Placement Table

| Component                | Grid Row | Grid Column | Notes                                 |
|--------------------------|----------|-------------|---------------------------------------|
| Subject Table            | 1        | 1           | Main data table for subjects          |
| Right-side Button Stack  | 1        | 2           | 5-row vertical grid of buttons        |
| Bottom Control Bar       | 2        | 1           | 1x4 horizontal grid of control buttons|
| (Unoccupied)             | 2        | 2           | No component assigned                 |

#### Right-side Button Stack (Nested 5x1 Grid)

| Button           | Row |
|------------------|-----|
| Add Subject      | 1   |
| Remove Subject   | 2   |
| Edit Protocol    | 3   |
| View Trials      | 4   |
| Save Data        | 5   |

#### Bottom Control Bar (Nested 1x4 Grid)

| Button    | Column |
|-----------|--------|
| Run       | 1      |
| Preview   | 2      |
| Pause     | 3      |
| Stop      | 4      |

## Unoccupied Spaces

- **Main Grid Row 2, Column 2**: This cell is not assigned any component and remains empty.
- **Right-side Button Stack Row 5**: Occupied by a button, but the row is set to '1x', so it expands to fill remaining space if the window is large.

## Text Diagram

```
+---------------------------+---------------------+
| Subject Table             | Add Subject         |
|                           | Remove Subject      |
|                           | Edit Protocol       |
|                           | View Trials         |
|                           | Save Data           |
+---------------------------+---------------------+
| Run | Preview | Pause | Stop | (empty)         |
+---------------------------+---------------------+
```

## Notable Features

- The main grid uses flexible sizing for the main content and fixed sizing for the control bar and right-side panel.
- The right-side button stack is implemented as a 5-row vertical grid, with the last row set to expand as needed.
- The bottom control bar is a 1-row, 4-column grid for primary experiment controls.
- Menu items are created for configuration, customization, view, and help, but are not part of the main grid layout.

## File Reference
- [obj/+epsych/@RunExpt/buildUI.m](../../obj/+epsych/@RunExpt/buildUI.m)
