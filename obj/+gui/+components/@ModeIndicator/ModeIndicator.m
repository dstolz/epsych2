classdef ModeIndicator < handle
    % gui.components.ModeIndicator(parent, Name=Value)
    % Lamp-and-label component that reflects the current hw.DeviceState.
    %
    % Embeds a uilamp and uilabel into any ui container, responds to
    % epsych.EventHub 'ModeChange' events, and can be driven directly via
    % setState().
    %
    % Properties:
    %   Lamp   - Underlying uilamp handle (read-only).
    %   Label  - Underlying uilabel handle (read-only).
    %
    % Usage:
    %   ind = gui.components.ModeIndicator(fig);
    %   ind = gui.components.ModeIndicator(gridCell, FontSize=13);
    %   ind.setState(hw.DeviceState.Record);
    %   ind.attachRuntime(RUNTIME);   % auto-wires ModeChange events
    %
    % See also: epsych.eventModeChange, hw.DeviceState

    properties (SetAccess = private)
        Lamp  matlab.ui.control.Lamp   % Underlying uilamp (read-only after construction)
        Label matlab.ui.control.Label  % Underlying uilabel (read-only after construction)
    end

    properties (Access = private)
        Listener_ event.listener  % Listener for RUNTIME.EVENTS ModeChange events
    end

    % Color/label lookup — one row per hw.DeviceState value (indexed by int8+2)
    properties (Constant, Access = private)
        STATE_MAP_ = gui.components.ModeIndicator.buildStateMap_()
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.components.ModeIndicator.getComponentSpec()
            % See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type          = 'ModeIndicator';
            s.label         = 'Mode Indicator';
            s.category      = 'Displays';
            s.description   = 'Lamp showing the current run mode';
            s.shape         = "parent";
            s.attachRuntime = true;
            s.options       = gui.ComponentSpecOption( ...
                'name','FontSize','inputType','numeric','defaultValue',11);
        end
    end

    methods

        function obj = ModeIndicator(parent, options)
            % gui.components.ModeIndicator(parent, Name=Value)
            % Construct a ModeIndicator inside a ui container.
            %
            % Parameters:
            %   parent   - Any UI container (uifigure, uigridlayout cell, uipanel, etc.).
            %   FontSize - Label font size in points (default: 11).
            arguments
                parent
                options.FontSize (1,1) double = 11
            end

            g = uigridlayout(parent, [2 1]);
            g.RowHeight    = {'1x', 'fit'};
            g.ColumnWidth  = {'1x'};
            g.RowSpacing   = 2;
            g.Padding      = [4 4 4 4];

            obj.Lamp = uilamp(g, 'Color', [0.55 0.55 0.55]);

            obj.Label = uilabel(g, ...
                'Text', 'Idle', ...
                'HorizontalAlignment', 'center', ...
                'FontSize', options.FontSize);
        end

        function setState(obj, mode)
            % obj.setState(mode)
            % Update the lamp color and label to reflect the given hw.DeviceState.
            %
            % Parameters:
            %   mode - hw.DeviceState scalar
            if ~isgraphics(obj.Lamp), return, end
            [color, label] = gui.components.ModeIndicator.lookupState_(mode);
            obj.Lamp.Color  = color;
            obj.Label.Text  = label;
        end

        function attachRuntime(obj, RUNTIME)
            % obj.attachRuntime(RUNTIME)
            % Wire a listener on RUNTIME.EVENTS so the indicator updates
            % automatically on every ModeChange event. Replaces any
            % previously attached listener.
            %
            % Parameters:
            %   RUNTIME - epsych.Runtime instance whose EVENTS broadcaster fires ModeChange
            delete(obj.Listener_);
            obj.Listener_ = addlistener(RUNTIME.EVENTS, 'ModeChange', ...
                @(~, ev) obj.setState(ev.NewMode));
        end

        function delete(obj)
            % Clean up the event listener when the indicator is destroyed.
            delete(obj.Listener_);
        end

    end

    methods (Static, Access = private)

        function map = buildStateMap_()
            % Returns a containers.Map from hw.DeviceState int8 value → {color, label}.
            map = containers.Map('KeyType','int32','ValueType','any');
            map(int32( 0)) = {[0.55 0.55 0.55], 'Idle'};      % Idle
            map(int32( 1)) = {[1.00 0.85 0.00], 'Standby'};   % Standby
            map(int32( 2)) = {[0.20 0.50 0.90], 'Preview'};   % Preview
            map(int32( 3)) = {[0.20 0.75 0.20], 'Recording'}; % Record
            map(int32( 4)) = {[0.85 0.25 0.25], 'Stopped'};   % Stop
            map(int32( 5)) = {[1.00 0.55 0.00], 'Paused'};    % Pause
            map(int32(-1)) = {[0.75 0.00 0.00], 'Error'};     % Error
        end

        function [color, label] = lookupState_(mode)
            % [color, label] = lookupState_(mode)
            % Return RGB color and text label for a hw.DeviceState value.
            map = gui.components.ModeIndicator.STATE_MAP_;
            key = int32(mode);
            if isKey(map, key)
                entry = map(key);
                color = entry{1};
                label = entry{2};
            else
                color = [0.55 0.55 0.55];
                label = char(mode.asString());
            end
        end

    end
end
