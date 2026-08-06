classdef TrialDesigner < handle
    % obj = teensy.TrialDesigner()
    % obj = teensy.TrialDesigner(program)
    % obj = teensy.TrialDesigner(filename)
    % obj = teensy.TrialDesigner(RUNTIME)
    % Design, simulate and upload Teensy trial contingencies.
    %
    % An operant paradigm is built here as an explicit state machine: states
    % with timers and output actions, connected by transitions whose
    % conditions read digital inputs, thresholded analog inputs, timers,
    % counters and probability branches. The result compiles to a state table
    % the board executes, so response timing does not inherit MATLAB timer
    % jitter, and the paradigm itself becomes a file rather than firmware.
    %
    % Five tabs, in the order a paradigm is usually built:
    %   Channels  - what is wired to which pin
    %   States    - the paradigm, as a list, a diagram and an inspector
    %   Variables - the quantities a protocol can vary per trial
    %   Test      - a virtual box for running the paradigm with no hardware
    %   Compile   - validation, the wire program, and upload
    %
    % Properties
    %   Program   - The teensy.Program being edited.
    %   Interface - Bound hw.Teensy, for upload and live I/O. May be empty.
    %   RUNTIME   - Bound epsych.Runtime for live monitoring. May be empty.
    %   Figure    - The uifigure.
    %
    % Example
    %   teensy.TrialDesigner(teensy.Templates.get("GoNoGoDetection"))
    %
    % See also: teensy.Program, teensy.Simulator, teensy.Compiler,
    %           teensy.Templates, documentation/teensy/teensy_TrialDesigner_UserGuide.md

    properties (SetAccess = protected)
        Program (1,1) teensy.Program
        Interface = []          % hw.Teensy, or [] when working offline
        RUNTIME = []            % epsych.Runtime, or [] when not attached to a session
        Figure matlab.ui.Figure
    end

    % Hidden rather than protected: the build and refresh methods delegate to
    % local functions, and a local function in a method file is not a class
    % method, so it cannot write a protected property.
    properties (Hidden)
        TabGroup matlab.ui.container.TabGroup
        StatusBar gui.StatusBar

        % One handle struct per tab. Keeping them separate means a tab can be
        % rebuilt wholesale without disturbing the others.
        HChannels (1,1) struct = struct()
        HStates (1,1) struct = struct()
        HVariables (1,1) struct = struct()
        HSim (1,1) struct = struct()
        HCompile (1,1) struct = struct()
        HMenu (1,1) struct = struct()
        HToolbar (1,1) struct = struct()

        SelectedChannel (1,1) double = 0
        SelectedState (1,1) double = 0
        SelectedVariable (1,1) double = 0

        CurrentFile (1,:) char = ''
        CompileResult (1,1) struct = struct('Ok', false, 'Lines', {{}}, 'Text', '', ...
            'Report', struct([]), 'Stats', struct([]))

        Simulator = []
        SimTimer = []
        SimSpeed (1,1) double = 1
        LiveTimer = []
    end

    properties (Access = private)
        IsModified_ (1,1) logical = false
        IsLocked_ (1,1) logical = false
        UndoStack_ (1,:) cell = {}
        RedoStack_ (1,:) cell = {}
        UndoLabels_ (1,:) cell = {}
        RedoLabels_ (1,:) cell = {}
        Listeners_ (1,:) cell = {}
        DragState_ (1,1) struct = struct('Active', false, 'Node', 0, 'Mode', "", ...
            'PrevMotionFcn', [], 'PrevUpFcn', [], 'FromNode', 0)
    end

    properties (Constant, Hidden)
        PREF_GROUP = 'epsych2_teensy_TrialDesigner'
        UNDO_DEPTH = 50
        FILE_EXT = '.etsm'
        APPDATA_RECENT = 'EPsychTeensyRecentPrograms'

        % Repo palette. Kept here so every tab tints rows the same way.
        COLOR_FIG = [0.945 0.951 0.960]
        COLOR_PANEL = [0.976 0.981 0.989]
        COLOR_HINT = [0.36 0.43 0.52]
        COLOR_PRIMARY = [0.20 0.50 0.90]
        SEVERITY_COLORS = struct( ...
            'error', [1.00 0.88 0.88], ...
            'warning', [1.00 0.96 0.85], ...
            'info', [0.92 0.95 1.00])
    end

    methods

        function obj = TrialDesigner(source, options)
            % obj = teensy.TrialDesigner(source, Name=Value)
            % Open the designer.
            %
            % Parameters
            %   source - A teensy.Program, a path to a .etsm file, an
            %       epsych.Runtime to monitor, or omitted for a new program.
            % Name=Value
            %   Interface (hw.Teensy) - Board to upload to and test against.
            %   Visible (logical)     - Show the window. Default true.
            arguments
                source = []
                options.Interface = []
                options.Visible (1,1) logical = true
            end

            obj.closeExistingInstance_();

            obj.Interface = options.Interface;

            if isa(source, 'teensy.Program')
                obj.Program = source;
            elseif isa(source, 'epsych.Runtime')
                obj.RUNTIME = source;
                obj.Program = teensy.Templates.get("Blank");
                obj.bindInterfaceFromRuntime_();
            elseif ischar(source) || isstring(source)
                obj.Program = obj.loadProgramFile_(char(source));
            else
                obj.Program = teensy.Templates.get("Blank");
            end

            obj.buildUI(options.Visible);
            obj.refreshAll();
            obj.setStatus('Ready.');

            if ~isempty(obj.RUNTIME)
                obj.attachRuntimeListeners_();
            end

            if nargout == 0, clear obj; end
        end

        function delete(obj)
            % delete(obj)
            % Stop every timer, drop listeners, save the position, close up.
            obj.stopTimer_('SimTimer');
            obj.stopTimer_('LiveTimer');

            for i = 1:numel(obj.Listeners_)
                if isvalid(obj.Listeners_{i})
                    delete(obj.Listeners_{i});
                end
            end
            obj.Listeners_ = {};

            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                setpref(obj.PREF_GROUP, 'Position', obj.Figure.Position);
                obj.Figure.CloseRequestFcn = '';
                delete(obj.Figure);
            end
        end

        function setStatus(obj, message, nextStep)
            % setStatus(obj, message, nextStep)
            % Show a message and the suggested next action.
            %
            % Parameters
            %   message  - What just happened.
            %   nextStep - What to do next. Defaults to suggestNextStep().
            arguments
                obj
                message (1,:) char
                nextStep (1,:) char = ''
            end

            if isempty(obj.StatusBar) || ~isvalid(obj.StatusBar)
                return
            end

            if isempty(nextStep)
                nextStep = obj.suggestNextStep();
            end
            obj.StatusBar.setStatus(message, nextStep);
        end

        function txt = suggestNextStep(obj)
            % txt = suggestNextStep(obj)
            % The next sensible action, given the state of the program.
            if isempty(obj.Program.Channels)
                txt = 'Add channels on the Channels tab, or load the default set.';
            elseif numel(obj.Program.States) < 2
                txt = 'Add states on the States tab, or start from a template.';
            elseif teensy.Compiler.hasError(obj.Program.validate())
                txt = 'Open the Compile tab to see what still needs fixing.';
            elseif ~obj.CompileResult.Ok
                txt = 'Compile the program on the Compile tab.';
            elseif isempty(obj.Interface)
                txt = 'Bind a Teensy interface to upload, or insert the program into a protocol.';
            else
                txt = 'Upload the program to the board.';
            end
        end

        function pushUndo(obj, label)
            % pushUndo(obj, label)
            % Snapshot the program before a change.
            %
            % Snapshots are exact because teensy.Program.toStruct round-trips
            % exactly, so undo cannot drift from what was on screen.
            arguments
                obj
                label (1,:) char = 'Change'
            end

            obj.UndoStack_{end+1} = obj.Program.toStruct();
            obj.UndoLabels_{end+1} = label;

            if numel(obj.UndoStack_) > obj.UNDO_DEPTH
                obj.UndoStack_(1) = [];
                obj.UndoLabels_(1) = [];
            end

            obj.RedoStack_ = {};
            obj.RedoLabels_ = {};
            obj.IsModified_ = true;
            obj.refreshUndoMenu_();
        end

        function onUndo(obj)
            % onUndo(obj)
            % Restore the previous program snapshot.
            if isempty(obj.UndoStack_)
                obj.setStatus('Nothing to undo.');
                return
            end

            obj.RedoStack_{end+1} = obj.Program.toStruct();
            obj.RedoLabels_{end+1} = obj.UndoLabels_{end};

            obj.applySnapshot_(obj.UndoStack_{end});
            label = obj.UndoLabels_{end};
            obj.UndoStack_(end) = [];
            obj.UndoLabels_(end) = [];

            obj.refreshAll();
            obj.setStatus(sprintf('Undid: %s', label));
        end

        function onRedo(obj)
            % onRedo(obj)
            % Reapply the snapshot that was undone.
            if isempty(obj.RedoStack_)
                obj.setStatus('Nothing to redo.');
                return
            end

            obj.UndoStack_{end+1} = obj.Program.toStruct();
            obj.UndoLabels_{end+1} = obj.RedoLabels_{end};

            obj.applySnapshot_(obj.RedoStack_{end});
            label = obj.RedoLabels_{end};
            obj.RedoStack_(end) = [];
            obj.RedoLabels_(end) = [];

            obj.refreshAll();
            obj.setStatus(sprintf('Redid: %s', label));
        end

        % --- File handling --------------------------------------------------

        function onNew(obj)
            % onNew(obj)
            % Start a blank program, after offering to save the current one.
            if ~obj.confirmDiscard_()
                return
            end
            obj.setProgram_(teensy.Templates.get("Blank"), '');
            obj.setStatus('New program.');
        end

        function onNewFromTemplate(obj)
            % onNewFromTemplate(obj)
            % Pick a paradigm template to start from.
            if ~obj.confirmDiscard_()
                return
            end

            T = teensy.Templates.list();
            items = cellstr(T.Title + "  --  " + T.Description);

            [idx, ok] = obj.chooseFromList_('Start From a Template', items, ...
                'Templates are complete, working paradigms. Pick the closest one and edit it.');
            if ~ok
                return
            end

            p = teensy.Templates.get(T.Name(idx));
            obj.setProgram_(p, '');
            obj.setStatus(sprintf('Loaded the %s template.', T.Title(idx)));
        end

        function onOpen(obj)
            % onOpen(obj)
            % Open a program file.
            if ~obj.confirmDiscard_()
                return
            end

            [f, pth] = uigetfile({'*.etsm', 'Teensy Program (*.etsm)'; ...
                '*.json', 'Teensy Program JSON (*.json)'}, 'Open Teensy Program');
            figure(obj.Figure);
            if isequal(f, 0)
                return
            end

            full = fullfile(pth, f);
            p = obj.loadProgramFile_(full);
            if isempty(p.States) && ~isfile(full)
                return
            end
            obj.setProgram_(p, full);
            obj.setStatus(sprintf('Opened %s.', f));
        end

        function tf = onSave(obj)
            % tf = onSave(obj)
            % Save in place, or fall through to Save As.
            %
            % Returns:
            %   tf - True when the program was saved.
            if isempty(obj.CurrentFile)
                tf = obj.onSaveAs();
                return
            end

            try
                obj.Program.save(obj.CurrentFile);
                obj.IsModified_ = false;
                obj.refreshTitle_();
                obj.setStatus(sprintf('Saved %s.', obj.CurrentFile));
                tf = true;
            catch ME
                vprintf(0, 1, ME);
                uialert(obj.Figure, ME.message, 'Save Failed', Icon = 'error');
                tf = false;
            end
        end

        function tf = onSaveAs(obj)
            % tf = onSaveAs(obj)
            % Save under a new name.
            %
            % Returns:
            %   tf - True when the program was saved.
            [f, pth] = uiputfile({'*.etsm', 'Teensy Program (*.etsm)'; ...
                '*.json', 'Teensy Program JSON (*.json)'}, 'Save Teensy Program', ...
                char(obj.Program.Name) + string(obj.FILE_EXT));
            figure(obj.Figure);
            if isequal(f, 0)
                tf = false;
                return
            end

            obj.CurrentFile = fullfile(pth, f);
            tf = obj.onSave();
            if tf
                obj.pushRecent_(obj.CurrentFile);
            end
        end

        function onCloseRequest(obj)
            % onCloseRequest(obj)
            % Offer to save, then close.
            if ~obj.confirmDiscard_()
                return
            end
            delete(obj);
        end

        function onEditInfo(obj)
            % onEditInfo(obj)
            % Edit the program's name, description and box.
            answer = obj.promptFields_('Program Information', { ...
                'Name', char(obj.Program.Name), 'text'; ...
                'Description', char(obj.Program.Description), 'text'; ...
                'Author', char(obj.Program.Author), 'text'; ...
                'BoxID', obj.Program.BoxID, 'numeric'});
            if isempty(answer)
                return
            end

            obj.pushUndo('Edit Info');
            obj.Program.Name = string(answer.Name);
            obj.Program.Description = string(answer.Description);
            obj.Program.Author = string(answer.Author);
            obj.Program.BoxID = max(0, round(answer.BoxID));
            obj.Program.touch();

            obj.refreshAll();
            obj.setStatus('Updated the program information.');
        end
    end

    methods

        function onTabChanged(obj, ~)
            % onTabChanged(obj, evt)
            % Keep the diagram current and stop simulating on a tab change.
            if obj.TabGroup.SelectedTab ~= obj.HSim.Tab
                obj.stopTimer_('SimTimer');
            end
            obj.refreshAll();
        end

        function onFigureKeyPress(obj, evt)
            % onFigureKeyPress(obj, evt)
            % Shortcuts that uimenu Accelerator cannot express.
            if isempty(evt.Modifier) || ~any(strcmp(evt.Modifier, 'control'))
                return
            end

            hasShift = any(strcmp(evt.Modifier, 'shift'));

            switch lower(evt.Key)
                case 's'
                    if hasShift
                        obj.onSaveAs();
                    end
                case 'l'
                    obj.onStates('autolayout');
                case 'delete'
                    obj.onStates('remove');
            end
        end

        function onOpenRecent(obj, path)
            % onOpenRecent(obj, path)
            % Open a file from the recent list.
            if ~obj.confirmDiscard_()
                return
            end
            obj.setProgram_(obj.loadProgramFile_(path), path);
            obj.setStatus(sprintf('Opened %s.', path));
        end

        function onOpenDocumentation(obj, which)
            % onOpenDocumentation(obj, which)
            % Open a documentation page in the editor.
            switch which
                case 'protocol'
                    relative = fullfile('documentation', 'hw', 'hw_Teensy_Program_Protocol.md');
                otherwise
                    relative = fullfile('documentation', 'teensy', ...
                        'teensy_TrialDesigner_UserGuide.md');
            end

            full = fullfile(EPsychInfo.root, relative);
            if ~isfile(full)
                obj.setStatus(sprintf('Documentation not found: %s', relative));
                return
            end

            open(full);
            obj.setStatus(sprintf('Opened %s.', relative));
        end

        function onDiagram(obj, verb, payload)
            % onDiagram(obj, verb, payload)
            % Mouse interaction on the state diagram.
            %
            % Presses arrive through ButtonDownFcn on the axes and on each
            % node. gui.StatusBar owns fig.WindowButtonDownFcn for its
            % double-click-to-copy behavior, so assigning that here would
            % silently destroy it; only the motion and up callbacks are
            % borrowed, and only for the duration of a drag.
            switch verb
                case 'node'
                    obj.SelectedState = payload;
                    obj.refreshAll();
                    obj.beginDrag_(payload);
                    obj.setStatus(sprintf('Selected %s. Drag to reposition it.', ...
                        obj.Program.States(payload).Name));

                case 'down'
                    % A press on empty canvas clears the selection highlight.
                    obj.setStatus('Click a state to select it.');
            end
        end

        function answer = promptFields_(obj, title, fields)
            % answer = promptFields_(obj, title, fields)
            % Modal form built from a {Name, Value, Kind} cell array.
            %
            % Kind is 'text', 'numeric', or 'choice:A|B|C'.
            %
            % Returns:
            %   answer - Struct of edited values, or [] if cancelled.
            nRows = size(fields, 1);
            dlgSize = [420, 70 + 34 * nRows];

            dlg = uifigure(Name = title, Position = obj.centeredPosition_(dlgSize), ...
                Resize = 'off', WindowStyle = 'modal');
            closer = onCleanup(@() localSafeDelete_(dlg));

            g = uigridlayout(dlg, [nRows + 1, 2]);
            g.RowHeight = [repmat({28}, 1, nRows), {34}];
            g.ColumnWidth = {130, '1x'};
            g.Padding = [10 10 10 10];

            controls = cell(1, nRows);
            for r = 1:nRows
                lbl = uilabel(g, Text = fields{r, 1}, HorizontalAlignment = 'right');
                lbl.Layout.Row = r;
                lbl.Layout.Column = 1;

                kind = fields{r, 3};
                if startsWith(kind, 'choice:')
                    items = strsplit(extractAfter(kind, 'choice:'), '|');
                    controls{r} = uidropdown(g, Items = items, Value = fields{r, 2});
                elseif strcmp(kind, 'numeric')
                    controls{r} = uieditfield(g, 'numeric', Value = fields{r, 2});
                else
                    controls{r} = uieditfield(g, 'text', Value = fields{r, 2});
                end
                controls{r}.Layout.Row = r;
                controls{r}.Layout.Column = 2;
            end

            buttons = uigridlayout(g, [1 2]);
            buttons.Layout.Row = nRows + 1;
            buttons.Layout.Column = [1 2];
            buttons.ColumnWidth = {'1x', '1x'};
            buttons.Padding = [0 4 0 0];

            uibutton(buttons, Text = 'OK', Tooltip = 'Apply these values.', ...
                ButtonPushedFcn = @(~, ~) localFinish_(dlg, true));
            uibutton(buttons, Text = 'Cancel', Tooltip = 'Discard the changes.', ...
                ButtonPushedFcn = @(~, ~) localFinish_(dlg, false));

            dlg.CloseRequestFcn = @(~, ~) localFinish_(dlg, false);
            uiwait(dlg);

            answer = [];
            if ~isvalid(dlg) || ~isequal(dlg.UserData, true)
                return
            end

            answer = struct();
            for r = 1:nRows
                answer.(matlab.lang.makeValidName(fields{r, 1})) = controls{r}.Value;
            end
        end

        function [idx, ok] = chooseFromList_(obj, title, items, hint)
            % [idx, ok] = chooseFromList_(obj, title, items, hint)
            % Modal single-choice list.
            %
            % Returns:
            %   idx - Selected index.
            %   ok  - False if cancelled.
            dlg = uifigure(Name = title, Position = obj.centeredPosition_([560 380]), ...
                Resize = 'off', WindowStyle = 'modal');
            closer = onCleanup(@() localSafeDelete_(dlg));

            g = uigridlayout(dlg, [3 2]);
            g.RowHeight = {'fit', '1x', 34};
            g.ColumnWidth = {'1x', '1x'};
            g.Padding = [10 10 10 10];

            lbl = uilabel(g, Text = hint, WordWrap = 'on', FontAngle = 'italic', ...
                FontColor = obj.COLOR_HINT);
            lbl.Layout.Row = 1;
            lbl.Layout.Column = [1 2];

            list = uilistbox(g, Items = items, Value = items{1});
            list.Layout.Row = 2;
            list.Layout.Column = [1 2];

            b1 = uibutton(g, Text = 'Use This', Tooltip = 'Load the selected item.', ...
                ButtonPushedFcn = @(~, ~) localFinish_(dlg, true));
            b1.Layout.Row = 3;
            b1.Layout.Column = 1;

            b2 = uibutton(g, Text = 'Cancel', Tooltip = 'Close without loading.', ...
                ButtonPushedFcn = @(~, ~) localFinish_(dlg, false));
            b2.Layout.Row = 3;
            b2.Layout.Column = 2;

            dlg.CloseRequestFcn = @(~, ~) localFinish_(dlg, false);
            uiwait(dlg);

            idx = 1;
            ok = false;
            if ~isvalid(dlg) || ~isequal(dlg.UserData, true)
                return
            end

            idx = find(strcmp(items, list.Value), 1);
            ok = true;
        end

        function mask = pickBitMask_(obj, initialMask, contextName)
            % mask = pickBitMask_(obj, initialMask, contextName)
            % Modal response-code picker, reusing helpers/bitmask_gui.
            %
            % Returns:
            %   mask - The chosen uint32 mask, or [] if cancelled.
            dlg = uifigure(Name = sprintf('Response Code for %s', contextName), ...
                Position = obj.centeredPosition_([460 620]), WindowStyle = 'modal');
            closer = onCleanup(@() localSafeDelete_(dlg));

            g = uigridlayout(dlg, [2 2]);
            g.RowHeight = {'1x', 34};
            g.ColumnWidth = {'1x', '1x'};
            g.Padding = [8 8 8 8];

            host = uipanel(g, BorderType = 'none');
            host.Layout.Row = 1;
            host.Layout.Column = [1 2];

            inner = bitmask_gui(Parent = host, InitialMask = uint32(initialMask));

            b1 = uibutton(g, Text = 'Use These Bits', ...
                Tooltip = 'Apply the selected outcome bits to this state.', ...
                ButtonPushedFcn = @(~, ~) localFinish_(dlg, true));
            b1.Layout.Row = 2;
            b1.Layout.Column = 1;

            b2 = uibutton(g, Text = 'Cancel', Tooltip = 'Leave the response code unchanged.', ...
                ButtonPushedFcn = @(~, ~) localFinish_(dlg, false));
            b2.Layout.Row = 2;
            b2.Layout.Column = 2;

            dlg.CloseRequestFcn = @(~, ~) localFinish_(dlg, false);
            uiwait(dlg);

            mask = [];
            if ~isvalid(dlg) || ~isequal(dlg.UserData, true)
                return
            end

            mask = obj.readBitMaskValue_(inner, initialMask);
        end

        function pos = centeredPosition_(obj, dlgSize)
            % pos = centeredPosition_(obj, dlgSize)
            % Center a dialog of the given size on the designer window.
            figPos = obj.Figure.Position;
            pos = [figPos(1) + round((figPos(3) - dlgSize(1)) / 2), ...
                   figPos(2) + round((figPos(4) - dlgSize(2)) / 2), ...
                   dlgSize];
        end
    end

    methods (Access = protected)

        function beginDrag_(obj, nodeIndex)
            % beginDrag_(obj, nodeIndex)
            % Start dragging a diagram node.
            %
            % The undo snapshot is pushed once here rather than on every mouse
            % move, so a drag is one undo step.
            if obj.IsLocked_
                return
            end

            obj.pushUndo('Move State');

            obj.DragState_.Active = true;
            obj.DragState_.Node = nodeIndex;
            obj.DragState_.PrevMotionFcn = obj.Figure.WindowButtonMotionFcn;
            obj.DragState_.PrevUpFcn = obj.Figure.WindowButtonUpFcn;

            obj.Figure.WindowButtonMotionFcn = @(~, ~) obj.dragMotion_();
            obj.Figure.WindowButtonUpFcn = @(~, ~) obj.endDrag_();
        end

        function dragMotion_(obj)
            % dragMotion_(obj)
            % Move the dragged node to follow the cursor.
            if ~obj.DragState_.Active
                return
            end

            ax = obj.HStates.Axes;
            p = ax.CurrentPoint(1, 1:2);

            if obj.HStates.Snap
                p = round(p * 20) / 20;
            end

            p = min(max(p, 0.02), 0.98);
            obj.Program.States(obj.DragState_.Node).Position = p;
            obj.drawDiagram();
        end

        function endDrag_(obj)
            % endDrag_(obj)
            % Finish a drag and hand the figure callbacks back.
            if ~obj.DragState_.Active
                return
            end

            obj.Figure.WindowButtonMotionFcn = obj.DragState_.PrevMotionFcn;
            obj.Figure.WindowButtonUpFcn = obj.DragState_.PrevUpFcn;
            obj.DragState_.Active = false;

            obj.Program.touch();
            obj.setStatus('Moved the state.');
        end

        function mask = readBitMaskValue_(~, inner, fallback)
            % mask = readBitMaskValue_(obj, inner, fallback)
            % Read the mask out of an embedded bitmask_gui.
            %
            % The helper renders a numeric "Mask" field; finding it by type is
            % more robust than depending on the order of its children.
            mask = uint32(fallback);
            try
                fields = findall(inner, 'Type', 'uinumericeditfield');
                if ~isempty(fields)
                    mask = uint32(fields(1).Value);
                end
            catch ME
                vprintf(2, 'teensy.TrialDesigner: could not read the bitmask value: %s', ...
                    ME.message);
            end
        end
    end

    methods
        % Implemented in separate files
        buildUI(obj, visible)        % Build the figure, menus, toolbar and tabs
        refreshAll(obj)              % Refresh every tab and the window chrome
        drawDiagram(obj)             % Render the state diagram
        onChannels(obj, verb, varargin)   % Channels tab actions
        onStates(obj, verb, varargin)     % States tab actions
        onVariables(obj, verb, varargin)  % Variables tab actions
        onSimulate(obj, verb, varargin)   % Test Bench actions
        onCompile(obj, verb, varargin)    % Compile tab actions
        action = editAction_(obj, action)                 % Modal action editor
        transition = editTransition_(obj, transition, stateIndex)  % Modal transition editor
        condition = editCondition_(obj, condition, stateIndex)     % Modal condition builder
    end

    methods (Access = protected)

        function setProgram_(obj, program, filename)
            % setProgram_(obj, program, filename)
            % Replace the document and reset everything derived from it.
            obj.Program = program;
            obj.CurrentFile = filename;
            obj.IsModified_ = false;
            obj.UndoStack_ = {};
            obj.RedoStack_ = {};
            obj.UndoLabels_ = {};
            obj.RedoLabels_ = {};
            obj.SelectedChannel = min(1, numel(program.Channels));
            obj.SelectedState = min(1, numel(program.States));
            obj.SelectedVariable = min(1, numel(program.Variables));
            obj.CompileResult = struct('Ok', false, 'Lines', {{}}, 'Text', '', ...
                'Report', struct([]), 'Stats', struct([]));
            obj.stopTimer_('SimTimer');
            obj.Simulator = [];
            obj.refreshAll();
        end

        function applySnapshot_(obj, snapshot)
            % applySnapshot_(obj, snapshot)
            % Replace the program contents in place from an undo snapshot.
            %
            % Copies field by field rather than swapping the handle, so any
            % listener bound to the current Program keeps working.
            restored = teensy.Program.fromStruct(snapshot);

            obj.Program.Name = restored.Name;
            obj.Program.Description = restored.Description;
            obj.Program.Author = restored.Author;
            obj.Program.BoxID = restored.BoxID;
            obj.Program.Board = restored.Board;
            obj.Program.Channels = restored.Channels;
            obj.Program.Variables = restored.Variables;
            obj.Program.States = restored.States;
            obj.Program.GlobalTimers = restored.GlobalTimers;
            obj.Program.Counters = restored.Counters;
            obj.Program.StartState = restored.StartState;

            obj.SelectedChannel = min(obj.SelectedChannel, numel(obj.Program.Channels));
            obj.SelectedState = min(obj.SelectedState, numel(obj.Program.States));
            obj.SelectedVariable = min(obj.SelectedVariable, numel(obj.Program.Variables));
            obj.IsModified_ = true;
            obj.refreshUndoMenu_();
        end

        function p = loadProgramFile_(obj, filename)
            % p = loadProgramFile_(obj, filename)
            % Load a program, degrading to a blank one on failure.
            try
                p = teensy.Program.load(filename);
                obj.pushRecent_(filename);
            catch ME
                vprintf(0, 1, ME);
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    uialert(obj.Figure, ME.message, 'Could Not Open', Icon = 'error');
                end
                p = teensy.Templates.get("Blank");
            end
        end

        function tf = confirmDiscard_(obj)
            % tf = confirmDiscard_(obj)
            % Gate a destructive action on the unsaved-changes question.
            %
            % Returns:
            %   tf - True when the caller may proceed.
            if ~obj.IsModified_
                tf = true;
                return
            end

            answer = uiconfirm(obj.Figure, ...
                'This program has unsaved changes.', 'Unsaved Changes', ...
                Options = {'Save Changes', 'Discard Changes', 'Cancel'}, ...
                DefaultOption = 'Save Changes', CancelOption = 'Cancel', Icon = 'warning');

            switch answer
                case 'Save Changes'
                    tf = obj.onSave();
                case 'Discard Changes'
                    tf = true;
                otherwise
                    tf = false;
            end
        end

        function refreshTitle_(obj)
            % refreshTitle_(obj)
            % Retitle the window with the program name and dirty marker.
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end

            marker = '';
            if obj.IsModified_
                marker = ' *';
            end

            name = char(obj.Program.Name);
            if ~isempty(obj.CurrentFile)
                [~, base, ext] = fileparts(obj.CurrentFile);
                name = [base ext];
            end

            obj.Figure.Name = sprintf('Teensy Trial Designer  [%s]%s', name, marker);
        end

        function refreshUndoMenu_(obj)
            % refreshUndoMenu_(obj)
            % Retitle the Undo and Redo items with what they would do.
            if ~isfield(obj.HMenu, 'Undo') || ~isvalid(obj.HMenu.Undo)
                return
            end

            if isempty(obj.UndoLabels_)
                obj.HMenu.Undo.Text = 'Undo';
                obj.HMenu.Undo.Enable = 'off';
            else
                obj.HMenu.Undo.Text = sprintf('Undo %s', obj.UndoLabels_{end});
                obj.HMenu.Undo.Enable = 'on';
            end

            if isempty(obj.RedoLabels_)
                obj.HMenu.Redo.Text = 'Redo';
                obj.HMenu.Redo.Enable = 'off';
            else
                obj.HMenu.Redo.Text = sprintf('Redo %s', obj.RedoLabels_{end});
                obj.HMenu.Redo.Enable = 'on';
            end
        end

        function stopTimer_(obj, which)
            % stopTimer_(obj, which)
            % Stop and delete one of the designer's timers.
            t = obj.(which);
            if isempty(t) || ~isa(t, 'timer') || ~isvalid(t)
                obj.(which) = [];
                return
            end
            try
                stop(t);
            catch ME
                vprintf(2, 'teensy.TrialDesigner: stopping %s: %s', which, ME.message);
            end
            delete(t);
            obj.(which) = [];
        end

        function closeExistingInstance_(obj)
            % closeExistingInstance_(obj)
            % Replace an already-open designer, the house single-instance idiom.
            existing = findall(groot, 'Type', 'figure', '-and', 'Tag', obj.PREF_GROUP);
            for i = 1:numel(existing)
                fig = existing(i);
                ud = fig.UserData;
                try
                    setpref(obj.PREF_GROUP, 'Position', fig.Position);
                catch ME
                    vprintf(2, 'teensy.TrialDesigner: %s', ME.message);
                end
                fig.UserData = [];
                fig.CloseRequestFcn = '';
                delete(fig);
                if isa(ud, 'teensy.TrialDesigner') && isvalid(ud)
                    delete(ud);
                end
            end
        end

        function bindInterfaceFromRuntime_(obj)
            % bindInterfaceFromRuntime_(obj)
            % Adopt the session's Teensy interface, when it has one.
            if isempty(obj.RUNTIME)
                return
            end

            for i = 1:numel(obj.RUNTIME.Interfaces)
                if isa(obj.RUNTIME.Interfaces(i), 'hw.Teensy')
                    obj.Interface = obj.RUNTIME.Interfaces(i);
                    return
                end
            end
        end

        function attachRuntimeListeners_(obj)
            % attachRuntimeListeners_(obj)
            % Follow the running session so the diagram can show the live state.
            obj.Listeners_{end+1} = addlistener(obj.RUNTIME.HELPER, 'ModeChange', ...
                @(~, evt) obj.onSessionModeChange_(evt));

            obj.LiveTimer = timer( ...
                Name = 'TeensyDesignerLive', ...
                ExecutionMode = 'fixedSpacing', ...
                Period = 0.25, ...
                BusyMode = 'drop', ...
                TimerFcn = @(~, ~) obj.onLiveTick_());
            start(obj.LiveTimer);
        end

        function onSessionModeChange_(obj, evt)
            % onSessionModeChange_(obj, evt)
            % Lock editing while a session is actually running.
            obj.IsLocked_ = ismember(evt.NewMode, [hw.DeviceState.Preview, hw.DeviceState.Record]);
            obj.refreshEnableState_();

            if obj.IsLocked_
                obj.setStatus('A session is running; editing is locked.', ...
                    'Stop the session to edit this program.');
            else
                obj.setStatus('Session stopped; editing unlocked.');
            end
        end

        function onLiveTick_(obj)
            % onLiveTick_(obj)
            % Poll the board's current state and highlight it on the diagram.
            if isempty(obj.Figure) || ~isvalid(obj.Figure) || isempty(obj.Interface)
                return
            end

            try
                idx = obj.Interface.get_parameter('StateIndex', silenceParameterNotFound = true);
                if isnumeric(idx) && isscalar(idx) && idx >= 1
                    obj.HStates.LiveState = idx;
                    obj.drawDiagram();
                end
            catch ME
                vprintf(3, 'teensy.TrialDesigner: live poll failed: %s', ME.message);
            end
        end

        function refreshEnableState_(obj)
            % refreshEnableState_(obj)
            % Enable or disable every mutating control from IsLocked_.
            if obj.IsLocked_
                state = 'off';
            else
                state = 'on';
            end

            for group = {obj.HChannels, obj.HStates, obj.HVariables}
                obj.setEnableIfPresent_(group{1}, state);
            end
        end

        function setEnableIfPresent_(~, handles, state)
            % setEnableIfPresent_(obj, handles, state)
            % Set Enable on every button in a handle struct that has one.
            names = fieldnames(handles);
            for i = 1:numel(names)
                h = handles.(names{i});
                if ~isscalar(h) || ~isgraphics(h) || ~isvalid(h)
                    continue
                end
                if isprop(h, 'Enable') && ~isa(h, 'matlab.ui.container.Tab')
                    h.Enable = state;
                end
            end
        end

        function pushRecent_(obj, filename)
            % pushRecent_(obj, filename)
            % Remember a file at the top of the recent list.
            recent = getappdata(0, obj.APPDATA_RECENT);
            if ~iscell(recent)
                recent = {};
            end
            recent(strcmp(recent, filename)) = [];
            recent = [{filename}, recent];
            setappdata(0, obj.APPDATA_RECENT, recent(1:min(8, numel(recent))));
        end
    end
end


function localFinish_(dlg, accepted)
% localFinish_(dlg, accepted)
% Record a modal dialog's result and release the uiwait.
%
% The dialog is left alive so the caller can read its controls; the caller's
% onCleanup deletes it.
if isvalid(dlg)
    dlg.UserData = accepted;
    uiresume(dlg);
end
end


function localSafeDelete_(dlg)
% localSafeDelete_(dlg)
% Delete a dialog that may already be gone.
if ~isempty(dlg) && isvalid(dlg)
    delete(dlg);
end
end
