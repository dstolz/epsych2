classdef ep_GenericGUI < gui.BehaviorGUI
    % ep_GenericGUI Generic Behavior Behavior GUI for EPsych experiments.
    %
    % OBJ = ep_GenericGUI(RUNTIME) creates a single GUI instance that
    % auto-discovers all visible parameters from the RUNTIME hardware and
    % software interfaces and builds:
    %   - A control button panel for trigger and toggle parameters.
    %   - A scrollable parameter-control panel for writable parameters.
    %   - A polling parameter-monitor table for read-only parameters.
    %   - An event log that records trial, data, and mode-change events.
    %
    % This class satisfies the BehaviorGUI convention used by epsych.RunExpt:
    % the constructor signature is ep_GenericGUI(RUNTIME). Lifecycle
    % concerns (single instance, position persistence, event listeners,
    % teardown) are inherited from gui.BehaviorGUI.
    %
    % Example:
    %   ep_GenericGUI(RUNTIME)   % called automatically by RunExpt
    %
    % See also: gui.BehaviorGUI, epsych.RunExpt, gui.components.Parameter_Monitor,
    % gui.components.Parameter_Control

    properties (SetAccess = protected)
        ParameterMonitor        % gui.components.Parameter_Monitor instance
        ParamControls           % Cell array of writable parameter control handles
    end

    properties (Hidden)
        h_logArea               % uitextarea handle for the event log
    end

    methods
        function obj = ep_GenericGUI(RUNTIME)
            % obj = ep_GenericGUI(RUNTIME)
            % Create the generic behavior GUI.
            % Only one instance is allowed; an existing window is replaced.
            %  RUNTIME - epsych.Runtime object with interfaces configured.
            obj@gui.BehaviorGUI(RUNTIME, ...
                Name='Behavior Box', ...
                PreferenceTag='ep_GenericGUI', ...
                DefaultPosition=[100 100 1100 680]);

            if nargout == 0, clear obj; end
        end

        function log_event(obj, msg)
            % log_event(obj, msg)
            % Prepend a timestamped message to the event log text area.
            %  msg - char or string message to display.
            if isempty(obj.h_logArea) || ~isvalid(obj.h_logArea), return; end
            ts      = string(datetime('now', 'Format', 'HH:mm:ss.SSS'));
            newLine = sprintf('[%s] %s', ts, msg);
            obj.h_logArea.Value = [newLine; obj.h_logArea.Value];
        end
    end

    methods (Access = protected)

        build(obj, fig)  % Build the GUI layout and wire all controls.

        function onNewTrial(obj, ~, ~)
            obj.log_event('New trial');
        end

        function onNewData(obj, ~, ~)
            obj.log_event('Data received');
        end

        function onModeChange(obj, ~, event)
            try
                stateStr = string(event.NewMode);
            catch
                stateStr = 'unknown';
            end
            obj.log_event(sprintf('Mode: %s', stateStr));
        end
    end

    methods (Static)

        function position = getSavedFigurePosition(defaultPosition)
            % Back-compatible shim: position prefs are managed by
            % gui.BehaviorGUI, keyed by PreferenceTag (same pref group as
            % before, so saved positions carry over).
            position = gui.BehaviorGUI.getSavedFigurePosition('ep_GenericGUI', defaultPosition);
        end

        function saveFigurePosition(position)
            % Back-compatible shim; see getSavedFigurePosition.
            gui.BehaviorGUI.saveFigurePosition('ep_GenericGUI', position);
        end
    end

end
