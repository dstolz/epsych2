classdef WikiKeysBehaviorGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass whose only job is to have a realistic
    % set of keyboard shortcuts bound, so generate_component_screenshots can
    % photograph the list gui.KeyBindings.showHelp puts up. Not an example to
    % copy: see examples/customgui/ExampleBehaviorGUI.m for that.
    %
    % Every binding in the shot is a REAL one. Two come from the base class
    % (F1 and Ctrl+Shift+? open the list itself), three are the default chords
    % the add* helpers ship with (Ctrl+Enter commit, Ctrl+Shift+C screenshot,
    % Ctrl+Shift+N notes), and the two arrow keys are bound in build the way
    % examples/two_afc/TwoAFCBehaviorGUI binds its subject-response keys --
    % the paradigm-authored group, which is the half of the list that differs
    % from rig to rig. They are bound first, so the paradigm's own keys head
    % the list rather than trailing the helpers'.
    %
    % The callbacks are never invoked: the shot photographs obj.Keys.list, not
    % a keystroke. respondSide_ is here so the bindings are ordinary bindings
    % with an ordinary handler rather than anonymous no-ops.
    %
    % The parameter names are the appetitive AM-detection rig's own, because
    % generate_component_screenshots drives this from a real saved session.

    methods
        function obj = WikiKeysBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='', Visible=false, ...
                PreferenceTag='wikiShotKeyBindings', ...
                DefaultPosition=[200 200 420 190]);
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            % The paradigm's own keys, bound through obj.Keys rather than
            % fig.WindowKeyPressFcn -- the whole point of the class.
            obj.Keys.bind('leftarrow',  @() obj.respondSide_(0), ...
                Description='Respond LEFT',  Group='Subject response');
            obj.Keys.bind('rightarrow', @() obj.respondSide_(1), ...
                Description='Respond RIGHT', Group='Subject response');

            g = uigridlayout(fig, [2 1]);
            g.RowHeight = {'1x', 34};

            col = obj.controlColumn(g, Title='Session Controls', Row=1, Rows=3);
            obj.addControl(col, 'Rate',    Text='AM Rate (Hz)');
            obj.addControl(col, 'StimDur', Text='Stimulus Duration (ms)');
            obj.addUpdateButton(col);          % Ctrl+Enter

            row = uigridlayout(g, [1 3]);
            row.Layout.Row = 2;
            row.ColumnWidth = {36, 96, '1x'};
            row.Padding = [0 0 0 0];
            obj.addScreenCapture(row);         % Ctrl+Shift+C
            obj.addNotesButton(row);           % Ctrl+Shift+N
        end
    end

    methods (Access = private)
        function respondSide_(obj, side)
            vprintf(3, '%s: operator answered side %d', class(obj), side)
        end
    end
end
