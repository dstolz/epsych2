# Layout Documentation: cl_AppetitiveDetection_GUI_B

This document summarizes the GUI layout for the `cl_AppetitiveDetection_GUI_B` component, including a table mapping which components occupy which columns and rows, and a summary of unoccupied spaces.

## Layout Table

| Row(s)   | Column(s)   | Component/Panel                | Notes |
|----------|-------------|--------------------------------|-------|
| 1        | 1-4         | Control Buttons (buttonLayout) | Drop Pellet, Shape, Reminder, Observe, Deliver Trials |
| 1        | 5           | Phase Selector                 | gui.PhaseSelector |
| 1-2      | 6           | Next Trial Panel               | Table: Next Trial |
| 1-2      | 7           | Session Performance Panel      | Label: Performance |
| 2-6      | 1-2         | Trial Controls Panel           | Staircase & Trial Params |
| 3-5      | 3-7         | Main Plot (axPsych)            | Psychometric Plot |
| 6-10     | 3-4         | Info Table Panel               | Parameter Monitor Table |
| 6-11     | 6-7         | Response History Panel         | gui.History |
| 7-8      | 1-2         | Sound Controls Panel           | Sound Params |
| 11       | 3-5         | Filename Panel                 | Filename Validator |
| 9-10     | 1-2         | Update Parameters Button       | gui.Parameter_Update |

## Unoccupied Spaces

- Rows 2-6, Columns 3-5 (except for main plot and info table) may have overlap or be unoccupied depending on dynamic content.
- Rows 9-11, Columns 1-3 (Trial Filter panel) are commented out and not present in the current layout.
- Row 11, Columns 1-2 (except for Update button) are mostly unoccupied.
- Row 11, Columns 6-7 are unoccupied.

---

**Instructions:**
- Update this table as the layout changes.
- Use this document to quickly understand the spatial arrangement of components in the `cl_AppetitiveDetection_GUI_B` GUI.
