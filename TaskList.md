# Task List

## Instructions
* Tackle the following tasks in order of priority, with 1 being the highest priority. Mark each task as complete once finished.
* Tasks that are marked as "Plan" require additional planning before execution. Make sure to outline the steps needed to complete these tasks. Use a "Plan" agent to assist with this process.
* For tasks that are marked as "Execute," proceed with the execution phase after planning is complete.



## Task Template
_note: This is a template for task creation. Do not process this section._
_note: This template is just a suggestion and can be modified as needed._
1. **Task Name**: Develop a Marketing Strategy
   - **Priority**: 1
   - **Status**: Plan
   - **Description**: Create a comprehensive marketing strategy for the upcoming product launch. This should include target audience analysis, key messaging, and channel selection.
   - **Steps to Complete**:
     1. Conduct market research to identify target audience demographics and preferences.
     2. Define key messaging that resonates with the target audience.
     3. Select appropriate marketing channels (e.g., social media, email, paid advertising).
     4. Develop a content calendar for marketing activities leading up to the launch.

## Task List



## Processed Tasks
1. **Elapsed Time since last trial**: Generate a counter that tracks the time since the last trial was completed. This will optionally have a simple text label to be placed in a GUI. 
   - **Priority**: 1
   - **Status**: Complete
   - **Description**: Generate a counter that tracks the time since the last trial was completed. This will optionally have a simple text label to be placed in a GUI.
   - **Implementation**: `obj/+gui/@ElapsedTrialTimer/ElapsedTrialTimer.m`
   - **Steps to Complete**:
     1. Determine the method for tracking the time since the last trial based on listening to the trial completion event.
     2. Implement the elapsed time calculation.
     3. Create a simple text label to display the counter in the GUI.
     4. Provide code for an object for optional simple integration with the GUI.
     5. User options should include the ability to reset the counter and customize the display format of the elapsed time. Control over font and color attributes should also be provided for better integration with various GUI themes.
   - **Notes**:
     - Implemented as `gui.ElapsedTrialTimer` in `obj/+gui/@ElapsedTrialTimer/`.
     - Listens to `epsych.EventHub` `NewData` event to reset its clock on each trial completion.
     - A MATLAB timer fires at `UpdatePeriod` (default 0.5 s) to refresh the `uilabel` text.
     - `Format` accepts `'hms'` (HH:MM:SS), `'ms'` (MM:SS), `'s'` (SS.f), or any custom `sprintf` pattern (receives total seconds).
     - Font/color properties (`FontSize`, `FontColor`, `FontWeight`) are set at construction or updated post-hoc via `applyStyle(Name=Value)`.
     - `Prefix` property controls the text before the time value (default: `'Last trial: '`).
     - `reset()` resets the clock manually; `attachRuntime(RUNTIME)` wires the listener; `start()`/`stop()` control the refresh timer.
     - Example:
       ```matlab
       t = gui.ElapsedTrialTimer(panel, FontSize=14, Prefix='ITI: ', Format='ms');
       t.attachRuntime(RUNTIME);
       t.start;
       ```


