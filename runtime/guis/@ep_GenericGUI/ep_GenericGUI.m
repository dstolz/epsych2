classdef ep_GenericGUI < handle
    % ep_GenericGUI Generic Behavior Box GUI for EPsych experiments.
    %
    % OBJ = ep_GenericGUI(RUNTIME) creates a single GUI instance that
    % auto-discovers all visible parameters from the RUNTIME hardware and
    % software interfaces and builds:
    %   - A control button panel for trigger and toggle parameters.
    %   - A scrollable parameter-control panel for writable parameters.
    %   - A polling parameter-monitor table for read-only parameters.
    %   - An event log that records trial, data, and mode-change events.
    %
    % This class satisfies the BoxFig convention used by epsych.RunExpt:
    % the constructor signature is ep_GenericGUI(RUNTIME).
    %
    % Example:
    %   ep_GenericGUI(RUNTIME)   % called automatically by RunExpt
    %
    % See also: epsych.RunExpt, gui.Parameter_Monitor, gui.Parameter_Control

    properties (SetAccess = protected)
        RUNTIME                 % epsych.Runtime object
        h_figure                % Main figure handle
        ParameterMonitor        % gui.Parameter_Monitor instance
        hButtons                % Struct of button Parameter_Control objects
        ParamControls           % Cell array of writable parameter control handles
    end

    properties (Hidden)
        hl_NewTrial             % Listener for NewTrial events
        hl_NewData              % Listener for NewData events
        hl_ModeChange           % Listener for ModeChange events
        h_logArea               % uitextarea handle for the event log
    end

    methods
        create_gui(obj)  % Build the GUI layout and wire all controls.

        function obj = ep_GenericGUI(RUNTIME)
            % obj = ep_GenericGUI(RUNTIME)
            % Create the generic behavior box GUI.
            % Only one instance is allowed; an existing window is replaced.
            %  RUNTIME - epsych.Runtime object with interfaces configured.
            obj.RUNTIME = RUNTIME;

            % Enforce single instance
            f = findall(groot, 'Type', 'figure', '-and', 'Tag', 'ep_GenericGUI');
            for i = 1:numel(f)
                try
                    ep_GenericGUI.saveFigurePosition(f(i).Position);
                    ud = f(i).UserData;
                    f(i).UserData   = [];
                    f(i).CloseRequestFcn = [];
                    delete(f(i));
                    if isobject(ud) && isvalid(ud)
                        delete(ud);
                    end
                catch
                end
            end

            obj.create_gui;

            % Attach runtime event listeners
            if ~isempty(RUNTIME.HELPER) && isvalid(RUNTIME.HELPER)
                obj.hl_NewTrial   = listener(RUNTIME.HELPER, 'NewTrial',   @(s,e) obj.on_new_trial(s,e));
                obj.hl_NewData    = listener(RUNTIME.HELPER, 'NewData',    @(s,e) obj.on_new_data(s,e));
                obj.hl_ModeChange = listener(RUNTIME.HELPER, 'ModeChange', @(s,e) obj.on_mode_change(s,e));
            end

            if nargout == 0, clear obj; end
        end

        function delete(obj)
            % Destructor: disable and delete listeners, monitor, and timers.
            vprintf(3, 'ep_GenericGUI: destructor')

            try
                obj.hl_NewTrial.Enabled  = false;
                obj.hl_NewData.Enabled   = false;
                obj.hl_ModeChange.Enabled = false;
                delete(obj.hl_NewTrial);
                delete(obj.hl_NewData);
                delete(obj.hl_ModeChange);
            catch
            end

            try
                delete(obj.ParameterMonitor);
            catch
            end

            delete(timerfindall('Tag', 'ep_GenericGUI_Timer'));
        end

        function closeGUI(obj, src, ~)
            % closeGUI(obj, src, event)
            % Save window position then cleanly close the GUI.
            vprintf(3, 'ep_GenericGUI: closeGUI')
            try
                ep_GenericGUI.saveFigurePosition(src.Position);
            catch
            end
            delete(obj);
            try
                delete(src);
            catch
            end
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

    methods (Access = private)

        function on_new_trial(obj, ~, ~)
            obj.log_event('New trial');
        end

        function on_new_data(obj, ~, ~)
            obj.log_event('Data received');
        end

        function on_mode_change(obj, ~, event)
            try
                stateStr = string(event.state);
            catch
                stateStr = 'unknown';
            end
            obj.log_event(sprintf('Mode: %s', stateStr));
        end

    end

    methods (Static)

        function position = getSavedFigurePosition(defaultPosition)
            % getSavedFigurePosition(defaultPosition)
            % Retrieve the last-saved figure position from preferences.
            %  defaultPosition - [x y w h] fallback if no preference exists.
            position = getpref('ep_GenericGUI', 'FigurePosition', defaultPosition);
            if ~isnumeric(position) || numel(position) ~= 4 || any(~isfinite(position))
                position = defaultPosition;
            end
            position = double(reshape(position, 1, []));
        end

        function saveFigurePosition(position)
            % saveFigurePosition(position)
            % Persist figure [x y w h] to preferences for next session.
            if ~isnumeric(position) || numel(position) ~= 4 || any(~isfinite(position))
                return
            end
            setpref('ep_GenericGUI', 'FigurePosition', double(reshape(position, 1, [])));
        end

    end

end
