classdef (Abstract) BoxGUI < handle
    %BOXGUI Base class for custom experiment (BoxFig) GUIs.
    %   gui.BoxGUI owns everything a paradigm GUI needs besides its layout:
    %   single-instance enforcement, figure creation with position
    %   persistence, runtime event listeners, a teardown-guaranteed
    %   component registry, and automatic Parameter_Update wiring.
    %
    %   A subclass implements one required method, build(fig), and may
    %   override the protected hooks createPsych, onNewTrial, onNewData,
    %   onModeChange, and onFirstTrial. The subclass constructor forwards
    %   to this base and satisfies the BoxFig contract used by
    %   epsych.RunExpt: MyGUI(RUNTIME) opens the window.
    %
    %   Minimal subclass:
    %       classdef MyGUI < gui.BoxGUI
    %           methods
    %               function obj = MyGUI(RUNTIME)
    %                   obj@gui.BoxGUI(RUNTIME, Name='My Task');
    %                   if nargout == 0, clear obj; end
    %               end
    %           end
    %           methods (Access = protected)
    %               function build(obj, fig)
    %                   g = uigridlayout(fig, [2 1]);
    %                   obj.addButton(g, 'TrialDelivery');
    %                   obj.addControl(g, 'ITIDur', Text='ITI (s)');
    %                   obj.addUpdateButton(g);
    %               end
    %           end
    %       end
    %
    %   The base guarantees the GUI opens even against a runtime with no
    %   connected interfaces (epsych.SelfTest check I6): addControl and
    %   addButton silently skip parameter names that do not resolve.
    %
    %   NewData listener source: when createPsych returns a psychophysics
    %   object, NewData is taken from Psych.Helper so the psych object has
    %   already processed the trial before onNewData runs; otherwise
    %   NewData comes from RUNTIME.HELPER directly.
    %
    % Documentation: documentation/gui/gui_BoxGUI.md
    % See also gui.Parameter_Control, gui.Parameter_Update,
    % gui.Parameter_Monitor, epsych.RunExpt

    properties (SetAccess = protected)
        RUNTIME                 % epsych.Runtime object
        P (1,1) struct = struct() % Parameters keyed by validName (may be empty pre-hardware)
        Psych                   % psychophysics object from createPsych, or []
        h_figure                % Main uifigure handle
        hButtons (1,1) struct = struct() % addButton controls keyed by validName
        PreferenceTag (1,:) char % Figure Tag and getpref/setpref group
    end

    properties (Access = private)
        Components_ (1,:) cell = {} % registered components, deleted in reverse on teardown
        Deferred_ (1,:) cell = {}   % closures queued until the first NewTrial
        FirstTrialSeen_ (1,1) logical = false
        ButtonCount_ (1,1) double = 0 % rotation index for addButton colors
    end

    properties (Hidden, SetAccess = protected)
        hl_NewTrial             % Listener for NewTrial events
        hl_NewData              % Listener for NewData events
        hl_ModeChange           % Listener for ModeChange events
    end

    methods (Abstract, Access = protected)
        build(obj, fig) % Populate the figure with layout and components.
    end

    methods
        function obj = BoxGUI(RUNTIME, options)
            % obj = BoxGUI(RUNTIME, Name=..., DefaultPosition=..., PreferenceTag=..., Visible=...)
            % Create the figure, call the subclass build method, and wire
            % runtime event listeners.
            %  RUNTIME - epsych.Runtime (may have no interfaces attached).
            arguments
                RUNTIME (1,1)
                options.Name (1,:) char = 'Behavior Box'
                options.DefaultPosition (1,4) double = [100 100 1100 680]
                options.PreferenceTag (1,:) char = ''
                options.Visible (1,1) logical = true
            end

            obj.RUNTIME = RUNTIME;

            obj.PreferenceTag = options.PreferenceTag;
            if isempty(obj.PreferenceTag)
                obj.PreferenceTag = matlab.lang.makeValidName(class(obj));
            end

            obj.closeExistingInstance_();

            % Parameter cache; a synthetic or pre-hardware runtime yields an
            % empty struct and the GUI must still open (SelfTest I6).
            try
                obj.P = RUNTIME.all_parameters(asStruct=true, includeTriggers=true);
            catch ME
                vprintf(2, 'gui.BoxGUI: no parameters available yet (%s)', ME.message)
            end

            try
                obj.Psych = obj.createPsych(RUNTIME);
            catch ME
                vprintf(0,1, ME)
            end

            fig = uifigure( ...
                'Tag',             obj.PreferenceTag, ...
                'Name',            options.Name, ...
                'Visible',         matlab.lang.OnOffSwitchState(options.Visible), ...
                'CloseRequestFcn', @(src,evt) obj.closeGUI(src,evt), ...
                'UserData',        obj);
            fig.Position = gui.BoxGUI.getSavedFigurePosition(obj.PreferenceTag, options.DefaultPosition);
            movegui(fig, 'onscreen');
            obj.h_figure = fig;

            obj.build(fig);

            obj.wireUpdateButtons_();

            H = RUNTIME.HELPER;
            if ~isempty(H) && isvalid(H)
                obj.hl_NewTrial   = listener(H, 'NewTrial',   @obj.dispatchNewTrial_);
                obj.hl_ModeChange = listener(H, 'ModeChange', @obj.dispatchModeChange_);

                newDataSrc = H;
                if ~isempty(obj.Psych) && isvalid(obj.Psych)
                    newDataSrc = obj.Psych.Helper;
                end
                obj.hl_NewData = listener(newDataSrc, 'NewData', @obj.dispatchNewData_);
            end
        end

        function delete(obj)
            % Destructor: tear down listeners, registered components, the
            % psych object, and the figure — in that order.
            vprintf(3, '%s: destructor', class(obj))

            for h = [obj.hl_NewTrial, obj.hl_NewData, obj.hl_ModeChange]
                try
                    h.Enabled = false;
                    delete(h);
                catch
                end
            end

            % Reverse order so late additions (which may depend on earlier
            % components) go first.
            for i = numel(obj.Components_):-1:1
                c = obj.Components_{i};
                try
                    if isobject(c) && isvalid(c)
                        delete(c);
                    end
                catch
                end
            end
            obj.Components_ = {};

            try
                if ~isempty(obj.Psych) && isvalid(obj.Psych)
                    delete(obj.Psych);
                end
            catch
            end

            try
                if ~isempty(obj.h_figure) && isvalid(obj.h_figure)
                    obj.h_figure.CloseRequestFcn = '';
                    delete(obj.h_figure);
                end
            catch
            end
        end

        function closeGUI(obj, src, ~)
            % closeGUI(obj, src, event)
            % Figure CloseRequestFcn: persist position, then delete the
            % object (which deletes the figure). While this GUI's session
            % is still running, first ask what to do — closing silently
            % would leave the operator with a running experiment and no
            % controls for it.
            vprintf(3, '%s: closeGUI', class(obj))

            rx = obj.runningSession_();
            if ~isempty(rx)
                choice = uiconfirm(obj.h_figure, ...
                    ['An experiment is currently running. Closing this window ' ...
                     'leaves the session running without its controls.'], ...
                    'Experiment Running', ...
                    'Options', {'Close GUI', 'Halt Experiment', 'Cancel'}, ...
                    'DefaultOption', 'Cancel', ...
                    'CancelOption', 'Cancel', ...
                    'Icon', 'warning');

                switch choice
                    case 'Cancel'
                        return

                    case 'Halt Experiment'
                        % Stop through RunExpt so the session takes its
                        % normal Stop path (mode broadcast, timer stop,
                        % data save) while this GUI and its listeners are
                        % still alive to see it.
                        vprintf(0, '%s: halting the session at operator request', class(obj))
                        try
                            rx.halt()
                        catch ME
                            vprintf(0,1, ME)
                        end

                    case 'Close GUI'
                        vprintf(0, '%s: window closed; the session continues to run', class(obj))
                end
            end

            try
                gui.BoxGUI.saveFigurePosition(obj.PreferenceTag, src.Position);
            catch
            end
            delete(obj);
            try
                delete(src);
            catch
            end
        end

        function h = addControl(obj, parent, param, options)
            % h = addControl(obj, parent, param, ...)
            % Create a gui.Parameter_Control bound to a parameter and
            % register it for teardown and Parameter_Update watching.
            %  param - hw.Parameter, or a name resolved against obj.P.
            %          Unresolved names return [] without error so one
            %          build method serves protocols with differing
            %          parameter sets (and the pre-hardware SelfTest run).
            arguments
                obj
                parent (1,1)
                param
                options.Type (1,:) char = 'auto'
                % '' lets Parameter_Control pick the binding from Type
                % (Type='range' binds the [Min Max] pair, others bind Value).
                options.BoundProperty (1,:) char = ''
                options.autoCommit (1,1) logical = false
                options.Text (1,:) char = ''
                options.PostUpdateFcn = []
                options.PostUpdateFcnArgs (1,:) cell = {}
                options.EvaluatorFcn = []
                options.EvaluatorArgs (1,:) cell = {}
            end

            p = obj.resolveParameter_(param);
            if isempty(p), h = []; return; end

            % Runtime lets an autoCommit Value edit also land in the trial
            % table (see gui.Parameter_Control.Runtime); settings controls
            % want that, unlike addButton's self-clearing session toggles.
            h = gui.Parameter_Control(parent, p, ...
                Type=options.Type, ...
                BoundProperty=options.BoundProperty, ...
                autoCommit=options.autoCommit, ...
                Runtime=obj.RUNTIME);

            if ~isempty(options.Text)
                h.Text = options.Text;
            elseif ~isempty(p.Unit)
                h.Text = sprintf('%s (%s)', p.Name, p.Unit);
            end

            if ~isempty(options.PostUpdateFcn)
                h.PostUpdateFcn     = options.PostUpdateFcn;
                h.PostUpdateFcnArgs = options.PostUpdateFcnArgs;
            end
            if ~isempty(options.EvaluatorFcn)
                h.EvaluatorFcn  = options.EvaluatorFcn;
                h.EvaluatorArgs = options.EvaluatorArgs;
            end

            obj.register(h);
        end

        function h = addButton(obj, parent, param, options)
            % h = addButton(obj, parent, param, ...)
            % Create an auto-committing trigger/toggle button. Parameters
            % whose name starts with '~' become toggles; all others are
            % momentary. Buttons rotate through accent colors and are
            % stored in obj.hButtons.(validName).
            arguments
                obj
                parent (1,1)
                param
                options.Type (1,:) char = ''
                options.Text (1,:) char = ''
                options.PostUpdateFcn = []
                options.PostUpdateFcnArgs (1,:) cell = {}
            end

            p = obj.resolveParameter_(param);
            if isempty(p), h = []; return; end

            btnType = options.Type;
            if isempty(btnType)
                if ~isempty(p.Name) && p.Name(1) == '~'
                    btnType = 'toggle';
                else
                    btnType = 'momentary';
                end
            end

            h = gui.Parameter_Control(parent, p, Type=btnType, autoCommit=true);

            if ~isempty(options.Text)
                h.Text = options.Text;
            else
                label = regexprep(p.Name, '^[~!]+', '');
                if ~isempty(p.Unit)
                    label = sprintf('%s (%s)', label, p.Unit);
                end
                h.Text = strtrim(label);
            end

            obj.ButtonCount_ = obj.ButtonCount_ + 1;
            accents = min(lines(7) + 0.3, 1);
            h.colorNormal   = obj.h_figure.Color;
            h.colorOnUpdate = accents(mod(obj.ButtonCount_-1, 7)+1, :);
            try
                set(h.h_uiobj, FontWeight='bold', FontSize=13);
            catch
            end

            if ~isempty(options.PostUpdateFcn)
                h.PostUpdateFcn     = options.PostUpdateFcn;
                h.PostUpdateFcnArgs = options.PostUpdateFcnArgs;
            end

            obj.hButtons.(p.validName) = h;
            obj.register(h);
        end

        function lay = controlColumn(obj, parent, options)
            % lay = controlColumn(obj, parent, Title=..., Row=..., Column=..., Rows=...)
            % Titled panel containing a scrollable fixed-row-height grid,
            % ready for a stack of addControl calls.
            arguments
                obj % method form keeps call sites uniform with add*
                parent (1,1)
                options.Title (1,:) char = ''
                options.Row = []
                options.Column = []
                options.Rows (1,1) double {mustBeInteger,mustBePositive} = 20
                options.RowHeight (1,1) double = 25
            end

            p = uipanel(parent, 'Title', options.Title);
            if ~isempty(options.Row),    p.Layout.Row    = options.Row;    end
            if ~isempty(options.Column), p.Layout.Column = options.Column; end

            lay = uigridlayout(p, [options.Rows, 1]);
            lay.RowHeight  = repmat({options.RowHeight}, 1, options.Rows);
            lay.ColumnWidth = {'1x'};
            lay.RowSpacing = 1;
            lay.Padding    = [2 2 2 2];
            lay.Scrollable = 'on';
        end

        function h = addUpdateButton(obj, parent)
            % h = addUpdateButton(obj, parent)
            % Create a gui.Parameter_Update commit button. Its
            % watchedHandles are filled automatically after build with
            % every registered non-trigger, non-autoCommit control.
            arguments
                obj
                parent (1,1)
            end
            h = gui.Parameter_Update(obj.RUNTIME, parent);
            obj.register(h);
        end

        function h = addMonitor(obj, parent, params, options)
            % h = addMonitor(obj, parent, params, ...)
            % Create a gui.Parameter_Monitor over hw.Parameter objects or
            % resolvable names (unresolved names are skipped). Registered
            % monitors stop polling when the session mode changes to Stop.
            arguments
                obj
                parent (1,1)
                params
                options.pollPeriod (1,1) double = 1
                options.type (1,1) string = "table"
                options.Columns (1,:) string = string.empty(1,0)
                options.PreferenceTag (1,:) char = ''
            end

            resolved = hw.Parameter.empty(1,0);
            if isa(params,'hw.Parameter')
                resolved = params;
            else
                params = cellstr(params);
                for i = 1:numel(params)
                    p = obj.resolveParameter_(params{i});
                    if ~isempty(p), resolved(end+1) = p; end
                end
            end

            args = {'pollPeriod', options.pollPeriod, 'type', options.type};
            if ~isempty(options.Columns), args = [args {'Columns',options.Columns}]; end
            if ~isempty(options.PreferenceTag), args = [args {'PreferenceTag',options.PreferenceTag}]; end

            h = gui.Parameter_Monitor(parent, resolved, args{:});
            obj.register(h);
        end

        function h = addNextTrial(obj, parent, options)
            % h = addNextTrial(obj, parent, ...)
            % Create a gui.NextTrial bound to this GUI's runtime and
            % register it for teardown. See gui.NextTrial for options.
            arguments
                obj
                parent (1,1)
                options.Fields (1,:) string = string.empty(1,0)
                options.Formatters = containers.Map('KeyType','char','ValueType','any')
                options.FontSize (1,1) double = 16
                options.PreferenceTag (1,:) char = ''
            end

            args = {'Fields', options.Fields, 'Formatters', options.Formatters, ...
                'FontSize', options.FontSize};
            if ~isempty(options.PreferenceTag)
                args = [args {'PreferenceTag', options.PreferenceTag}];
            end

            h = gui.NextTrial(obj.RUNTIME, parent, args{:});
            obj.register(h);
        end

        function h = addPerformance(obj, parent, options)
            % h = addPerformance(obj, parent, ...)
            % Create a gui.SessionPerformance summary and register it for
            % teardown. It computes through a psychophysics.SessionMetrics
            % built over this GUI's psychophysics object when there is one
            % (so the trial-type conventions match), and over the runtime
            % otherwise. See gui.SessionPerformance for options.
            arguments
                obj
                parent (1,1)
                options.Metrics (1,:) string = psychophysics.SessionMetrics.defaultMetrics()
                options.TrialWindow = psychophysics.TrialWindow
                options.FontSize (1,1) double = 12
                options.ShowHeader (1,1) logical = true
                options.ShowDetail (1,1) logical = true
                options.PreferenceTag (1,:) char = ''
            end

            source = obj.Psych;
            if isempty(source) || ~isvalid(source)
                source = obj.RUNTIME;
            end

            args = {'Metrics', options.Metrics, 'TrialWindow', options.TrialWindow, ...
                'FontSize', options.FontSize, 'ShowHeader', options.ShowHeader, ...
                'ShowDetail', options.ShowDetail};
            if ~isempty(options.PreferenceTag)
                args = [args {'PreferenceTag', options.PreferenceTag}];
            end

            h = gui.SessionPerformance(source, parent, args{:});
            obj.register(h);
        end

        function comp = register(obj, comp, name)
            % comp = register(obj, comp, name)
            % Add any component (handle object or graphics) to the
            % teardown registry. Registered handle objects are deleted by
            % the destructor even though deleting the figure alone would
            % only remove their graphics, leaving listeners and timers
            % alive.
            arguments
                obj
                comp
                name (1,:) char = '' % reserved for future lookup by name
            end
            obj.Components_{end+1} = comp;
        end

        function defer(obj, fcn)
            % defer(obj, fcn)
            % Queue a closure to run at the first NewTrial, when parameter
            % and trial data exist. If the first trial has already
            % happened, fcn runs immediately.
            arguments
                obj
                fcn (1,1) function_handle
            end
            if obj.FirstTrialSeen_
                try
                    fcn();
                catch ME
                    vprintf(0,1, ME)
                end
            else
                obj.Deferred_{end+1} = fcn;
            end
        end
    end

    methods (Access = protected)

        function p = createPsych(obj, RUNTIME)
            % Override to create a psychophysics object; its Helper then
            % becomes the NewData listener source.
            p = [];
        end

        function onNewTrial(obj, src, event)
        end

        function onNewData(obj, src, event)
        end

        function onModeChange(obj, src, event)
        end

        function onFirstTrial(obj, src, event)
            % Runs once, at the first NewTrial, after deferred closures.
        end
    end

    methods (Access = private)

        function closeExistingInstance_(obj)
            % Only one instance per PreferenceTag: replace an existing
            % window. Detach UserData/CloseRequestFcn before deleting so
            % figure deletion cannot recurse into the old object.
            f = findall(groot, 'Type', 'figure', '-and', 'Tag', obj.PreferenceTag);
            for i = 1:numel(f)
                try
                    gui.BoxGUI.saveFigurePosition(obj.PreferenceTag, f(i).Position);
                    ud = f(i).UserData;
                    f(i).UserData = [];
                    f(i).CloseRequestFcn = '';
                    delete(f(i));
                    if isobject(ud) && isvalid(ud)
                        delete(ud);
                    end
                catch
                end
            end
        end

        function rx = runningSession_(obj)
            % Return the epsych.RunExpt driving this GUI while its session
            % is running, or [] otherwise. The runtime handles must be the
            % same object, so a window left over from an earlier run — or
            % one opened against the synthetic runtime of SelfTest check
            % I6 — never prompts about the session running now.
            rx = [];
            try
                candidate = epsych.SelfTest.findActiveRunExpt();
                if isempty(candidate) || candidate.STATE ~= PRGMSTATE.RUNNING
                    return
                end
                if ~isa(candidate.RUNTIME,'epsych.Runtime') || ~isa(obj.RUNTIME,'epsych.Runtime') ...
                        || candidate.RUNTIME ~= obj.RUNTIME
                    return
                end
                rx = candidate;
            catch ME
                vprintf(2, 'gui.BoxGUI: could not determine session state (%s)', ME.message)
            end
        end

        function p = resolveParameter_(obj, param)
            % Resolve an hw.Parameter or a parameter name against obj.P.
            % Names tolerate trigger prefixes (~/!): both the raw and the
            % stripped forms are tried as validNames.
            if isa(param, 'hw.Parameter')
                p = param;
                return
            end
            p = [];
            name = char(param);
            candidates = unique({matlab.lang.makeValidName(name), ...
                matlab.lang.makeValidName(regexprep(name,'^[~!]+',''))}, 'stable');
            for c = candidates
                if isfield(obj.P, c{1})
                    p = obj.P.(c{1});
                    return
                end
            end
            vprintf(2, 'gui.BoxGUI: parameter "%s" not available; control skipped', name)
        end

        function wireUpdateButtons_(obj)
            % Point every registered Parameter_Update at every registered
            % editable control. Registry-based, so it is order-independent
            % within build and immune to tag-convention drift.
            controls = gui.Parameter_Control.empty(1,0);
            updaters = {};
            for i = 1:numel(obj.Components_)
                c = obj.Components_{i};
                if ~isobject(c) || ~isvalid(c), continue; end
                if isa(c, 'gui.Parameter_Control') && ~c.autoCommit && ~c.Parameter.isTrigger
                    controls(end+1) = c;
                elseif isa(c, 'gui.Parameter_Update')
                    updaters{end+1} = c;
                end
            end
            if isempty(controls), return; end
            for i = 1:numel(updaters)
                updaters{i}.watchedHandles = controls;
            end
        end

        function dispatchNewTrial_(obj, src, event)
            if ~obj.FirstTrialSeen_
                obj.FirstTrialSeen_ = true;
                for i = 1:numel(obj.Deferred_)
                    try
                        obj.Deferred_{i}();
                    catch ME
                        vprintf(0,1, ME)
                    end
                end
                obj.Deferred_ = {};
                try
                    obj.onFirstTrial(src, event);
                catch ME
                    vprintf(0,1, ME)
                end
            end
            try
                obj.onNewTrial(src, event);
            catch ME
                vprintf(0,1, ME)
            end
        end

        function dispatchNewData_(obj, src, event)
            try
                obj.onNewData(src, event);
            catch ME
                vprintf(0,1, ME)
            end
        end

        function dispatchModeChange_(obj, src, event)
            try
                if event.NewMode == hw.DeviceState.Stop
                    for i = 1:numel(obj.Components_)
                        c = obj.Components_{i};
                        if isa(c, 'gui.Parameter_Monitor') && isvalid(c)
                            c.stop();
                        end
                    end
                end
            catch
            end
            try
                obj.onModeChange(src, event);
            catch ME
                vprintf(0,1, ME)
            end
        end
    end

    methods (Static)

        function position = getSavedFigurePosition(prefTag, defaultPosition)
            % Retrieve the last-saved [x y w h] for this PreferenceTag.
            position = getpref(prefTag, 'FigurePosition', defaultPosition);
            if ~isnumeric(position) || numel(position) ~= 4 || any(~isfinite(position))
                position = defaultPosition;
            end
            position = double(reshape(position, 1, []));
        end

        function saveFigurePosition(prefTag, position)
            % Persist figure [x y w h] under this PreferenceTag.
            if ~isnumeric(position) || numel(position) ~= 4 || any(~isfinite(position))
                return
            end
            setpref(prefTag, 'FigurePosition', double(reshape(position, 1, [])));
        end

        function [trigParams, ctrlParams, monitorParams] = classifyParameters(params)
            % Split an hw.Parameter array into trigger-style, writable,
            % and read-only visible groups (the ep_GenericGUI rules:
            % isTrigger or a ~/! name prefix marks a trigger).
            if isempty(params)
                [trigParams, ctrlParams, monitorParams] = deal(hw.Parameter.empty(1,0));
                return
            end

            isTrigArr = logical([params.isTrigger]);
            isVisArr  = logical([params.Visible]);
            accessArr = {params.Access};
            nameArr   = {params.Name};

            isTrigStyle = isTrigArr | cellfun(@(n) ~isempty(n) && ...
                (n(1)=='~' || n(1)=='!'), nameArr);

            isWrite = ismember(accessArr, {'Any', 'Write', 'Read / Write'});
            isRead  = strcmp(accessArr, 'Read');

            trigParams    = params(isTrigStyle & isVisArr);
            ctrlParams    = params(~isTrigStyle & isVisArr & isWrite);
            monitorParams = params(~isTrigStyle & isVisArr & isRead);
        end
    end
end
