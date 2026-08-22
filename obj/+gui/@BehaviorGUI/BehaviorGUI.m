classdef (Abstract) BehaviorGUI < handle
    %BEHAVIORGUI Base class for a paradigm's own experiment GUI.
    %   gui.BehaviorGUI owns everything a paradigm GUI needs besides its layout:
    %   single-instance enforcement, figure creation with position
    %   persistence, runtime event listeners, a teardown-guaranteed
    %   component registry, and automatic Parameter_Update wiring.
    %
    %   A subclass implements one required method, build(fig), and may
    %   override the protected hooks createPsych, onNewTrial, onNewData,
    %   onModeChange, and onFirstTrial. The subclass constructor forwards
    %   to this base and satisfies the behavior-GUI contract used by
    %   epsych.RunExpt: MyGUI(RUNTIME) opens the window.
    %
    %   Minimal subclass:
    %       classdef MyGUI < gui.BehaviorGUI
    %           methods
    %               function obj = MyGUI(RUNTIME)
    %                   obj@gui.BehaviorGUI(RUNTIME, Name='My Task');
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
    %   The add* helpers cover every reusable component a paradigm normally
    %   wants, and each one registers what it builds for teardown so the
    %   subclass never has to: controls (addControl, addButton,
    %   controlColumn, addUpdateButton), displays (addMonitor, addNextTrial,
    %   addPerformance, addHistory, addScatter, addPsychPlot,
    %   addStaircasePlot, addSessionClock, addTrialTimer, addModeIndicator),
    %   and operator add-ons (addNotes, addNotesButton, addScreenCapture,
    %   addSyringePump, addSessionGate). A helper whose component needs
    %   something this session does not have -- a parameter that does not
    %   resolve, an analysis that was never built -- returns [] and says so
    %   at debug level rather than throwing, so the GUI still opens against a
    %   runtime with no interfaces (epsych.SelfTest check I6).
    %
    %   Display components that inherit gui.PopOut (the scatter, history,
    %   performance, next-trial, monitor, and plot components) can be opened
    %   in a window of their own from their right-click menu, or from a
    %   button made with addPopOutButton. A pop-out is a separate instance
    %   over the same data, so it never disturbs the embedded one.
    %
    %   addComponentToolbar collects those windows onto one icon toolbar, and
    %   can additionally open components the GUI does not display at all. It
    %   is optional: a GUI that never calls it gets no toolbar.
    %
    %   RestorePopOuts=true makes the GUI remember WHICH of those windows the
    %   operator had open and reopen them the next time it is launched. What
    %   each window shows is not saved here — every component already
    %   remembers its own position, font size, columns, and pinned state
    %   under its pop-out preference key — so this records only the list of
    %   open displays, rewritten whenever one opens or closes rather than at
    %   teardown, which is what makes it survive a MATLAB that never closed
    %   cleanly. A remembered display that this protocol does not have is
    %   skipped and LEFT in the list, so running one paradigm cannot erase
    %   the layout of another.
    %
    %   NewData listener source: when createPsych returns a psychophysics
    %   object, NewData is taken from Psych.Events so the psych object has
    %   already processed the trial before onNewData runs; otherwise
    %   NewData comes from RUNTIME.EVENTS directly.
    %
    % Documentation: documentation/gui/gui_BehaviorGUI.md
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

    properties
        RestorePopOuts (1,1) logical = false % Reopen the displays left open last session
    end

    properties (Dependent, SetAccess = private)
        % True when this GUI was opened over a finished session by
        % epsych.ReviewSession rather than over a running one.
        %
        % Displays need not care: the events, the trial data and the parameter
        % reads are all real, so a component that only shows things works
        % unchanged. This is for the OTHER kind of subclass -- the one that
        % drives the rig, running its own timer, writing parameters and raising
        % x_TrialComplete_* to hand the trial back. That code must stand down in
        % a review, and the base class cannot do it for you: it does not know
        % which of your methods are display and which are contingency.
        %
        % The rule of thumb: guard anything that would still be a mistake if the
        % hardware were switched off.
        %
        %   function onNewTrial(obj, ~, ~)
        %       if obj.ReviewMode, return; end
        %       obj.beginTrial_();
        %   end
        ReviewMode (1,1) logical
    end

    properties (Access = private)
        Components_ (1,:) cell = {} % registered components, deleted in reverse on teardown
        ComponentNames_ (1,:) cell = {} % register names, one per Components_ entry
        ComponentToolbar_ = []      % gui.ComponentToolbar from addComponentToolbar, or []
        Deferred_ (1,:) cell = {}   % closures queued until the first NewTrial
        FirstTrialSeen_ (1,1) logical = false
        ButtonCount_ (1,1) double = 0 % rotation index for addButton colors
        PopOutListeners_ = event.listener.empty(1,0) % PopOutStateChanged, one per poppable component
        RestoringPopOuts_ (1,1) logical = false % suspends recording while windows are reopened
        UnresolvedPopOuts_ (1,:) string = string.empty(1,0) % remembered displays this GUI does not have
        TearingDown_ (1,1) logical = false % set by delete before components go
    end

    properties (Constant, Hidden)
        POPOUT_LAYOUT_PREF = 'OpenPopOuts' % Preference key holding the remembered display list
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
        function obj = BehaviorGUI(RUNTIME, options)
            % obj = BehaviorGUI(RUNTIME, Name=..., DefaultPosition=..., PreferenceTag=..., Visible=..., RestorePopOuts=...)
            % Create the figure, call the subclass build method, and wire
            % runtime event listeners.
            %  RUNTIME        - epsych.Runtime (may have no interfaces attached).
            %  RestorePopOuts - reopen the display windows the operator had
            %                   open when this GUI was last used, each with
            %                   the position, size, font, options and pinned
            %                   state it was left in. Off by default.
            arguments
                RUNTIME (1,1)
                options.Name (1,:) char = 'Behavior Box'
                options.DefaultPosition (1,4) double = [100 100 1100 680]
                options.PreferenceTag (1,:) char = ''
                options.Visible (1,1) logical = true
                options.RestorePopOuts (1,1) logical = false
            end

            obj.RUNTIME        = RUNTIME;
            obj.RestorePopOuts = options.RestorePopOuts;

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
                vprintf(2, 'gui.BehaviorGUI: no parameters available yet (%s)', ME.message)
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
            fig.Position = gui.BehaviorGUI.getSavedFigurePosition(obj.PreferenceTag, options.DefaultPosition);
            movegui(fig, 'onscreen');
            obj.h_figure = fig;

            obj.build(fig);

            obj.wireUpdateButtons_();

            % Auto discovery runs here rather than inside addComponentToolbar
            % because build is normally where the toolbar is asked for, before
            % the components it should list have been registered.
            if ~isempty(obj.ComponentToolbar_) && isvalid(obj.ComponentToolbar_)
                [comps, labels] = obj.popOutComponents_();
                obj.ComponentToolbar_.populateAuto_(comps, labels);
            end

            H = RUNTIME.EVENTS;
            if ~isempty(H) && isvalid(H)
                obj.hl_NewTrial   = listener(H, 'NewTrial',   @obj.dispatchNewTrial_);
                obj.hl_ModeChange = listener(H, 'ModeChange', @obj.dispatchModeChange_);

                newDataSrc = H;
                if ~isempty(obj.Psych) && isvalid(obj.Psych)
                    newDataSrc = obj.Psych.Events;
                end
                obj.hl_NewData = listener(newDataSrc, 'NewData', @obj.dispatchNewData_);
            end

            % Last, so a reopened window finds the GUI wired to the runtime
            % exactly as one opened by hand later in the session would. The
            % listeners are attached whether or not the memory is switched
            % on -- one event.listener per display costs nothing, and it lets
            % a GUI turn RestorePopOuts on mid-session and be obeyed.
            obj.attachPopOutListeners_();
            if obj.RestorePopOuts
                obj.restorePopOutLayout();
            end
        end

        function delete(obj)
            % Destructor: tear down listeners, registered components, the
            % psych object, and the figure — in that order.
            vprintf(3, '%s: destructor', class(obj))

            % FIRST, while every component and window is still intact: the
            % list is normally already current, but a window closed by
            % something that never reached closePopOut is only seen here.
            obj.savePopOutLayout();
            obj.TearingDown_ = true;
            obj.detachPopOutListeners_();

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
            obj.Components_     = {};
            obj.ComponentNames_ = {};

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
                gui.BehaviorGUI.saveFigurePosition(obj.PreferenceTag, src.Position);
            catch
            end
            delete(obj);
            try
                delete(src);
            catch
            end
        end

        function tf = get.ReviewMode(obj)
            % Read through to the runtime rather than cached, so a GUI built
            % against a synthetic runtime (SelfTest check I6) and one built
            % against a review both answer correctly, and neither has to be
            % told which it is.
            tf = false;
            try
                tf = isa(obj.RUNTIME, 'epsych.Runtime') && obj.RUNTIME.ReviewMode;
            catch ME
                vprintf(3, 'gui.BehaviorGUI: could not determine review mode (%s)', ME.message)
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

        function h = addSyringePump(obj, parent, options)
            % h = addSyringePump(obj, parent, ...)
            % Create a gui.SyringePump panel over this session's hw.NE1000
            % and register it for teardown. With no pump in the protocol the
            % panel constructs a standalone interface and offers a port to
            % connect on, so the GUI still opens. Use Sections to show only
            % part of the panel. See gui.SyringePump.
            %
            % Options are deliberately declared without defaults: only what
            % the build method actually passes is forwarded, which is what
            % lets the panel fall back to the operator's own remembered
            % configuration for everything else.
            arguments
                obj
                parent (1,1)
                options.Diameter (1,1) double
                options.Rate (1,1) double
                options.Direction (1,:) char
                options.TTLTrigger (1,1) logical
                options.TriggerMode (1,2) char
                options.RateUnits (1,2) char
                options.VolumeUnits (1,:) char
                options.UpdatePeriod (1,1) double
                options.Port (1,:) char
                options.ApplyOnStart (1,1) logical
                options.Sections (1,:) string
                options.FontSize (1,1) double
                options.PreferenceTag (1,:) char
            end

            args = namedargs2cell(options);
            h = gui.SyringePump(obj.RUNTIME, parent, args{:});
            obj.register(h);
        end

        function h = addNotes(obj, parent, options)
            % h = addNotes(obj, parent, ...)
            % Create a gui.Notes panel -- an entry field and a log of the
            % operator's typed notes -- and register it for teardown.
            %
            % Notes go into this session's store (RUNTIME.NOTES), which means
            % they are saved with the data: the Info variable every saving
            % function writes carries them, and each one is journaled as it is
            % committed, so a crash keeps them. Give the panel a '1x' row and
            % the log fills it. See gui.Notes.
            arguments
                obj
                parent (1,1)
                options.Subject (1,1) double = 0
                options.TimeStamp (1,1) string = "elapsed"
                options.Editable (1,1) logical = false
                options.FontSize (1,1) double = 12
                options.Placeholder (1,:) char = 'Add a note...'
                options.ButtonOnly (1,1) logical = false
                options.Text (1,:) char = 'Notes'
                options.PreferenceTag (1,:) char = ''
            end

            args = {'Subject', options.Subject, 'TimeStamp', options.TimeStamp, ...
                'Editable', options.Editable, 'FontSize', options.FontSize, ...
                'Placeholder', options.Placeholder, 'ButtonOnly', options.ButtonOnly, ...
                'Text', options.Text};
            if ~isempty(options.PreferenceTag)
                args = [args {'PreferenceTag', options.PreferenceTag}];
            end

            h = gui.Notes(obj.RUNTIME, parent, args{:});
            obj.register(h);
        end

        function h = addNotesButton(obj, parent, options)
            % h = addNotesButton(obj, parent, Text=...)
            % Create a single Notes button, for a GUI with no room for a log.
            % Clicking it opens the session notes in a window of their own --
            % the same store the panel form writes to, so the window shows
            % every note the session has and anything typed into it is saved
            % with the data. Clicking again raises that window rather than
            % opening a second one, and it closes with this GUI.
            arguments
                obj
                parent (1,1)
                options.Text (1,:) char = 'Notes'
                options.Subject (1,1) double = 0
                options.TimeStamp (1,1) string = "elapsed"
                options.FontSize (1,1) double = 12
                options.PreferenceTag (1,:) char = ''
            end

            h = obj.addNotes(parent, ButtonOnly = true, Text = options.Text, ...
                Subject = options.Subject, TimeStamp = options.TimeStamp, ...
                FontSize = options.FontSize, PreferenceTag = options.PreferenceTag);
        end

        function h = addScreenCapture(obj, parent, options)
            % h = addScreenCapture(obj, parent, Target=..., Text=..., Tooltip=...)
            % Create a gui.ScreenCapture camera button and register it for
            % teardown. One click copies a picture of the whole window —
            % controls, plots and all — to the system clipboard, for pasting
            % into a notebook entry. See gui.ScreenCapture.
            arguments
                obj
                parent (1,1)
                options.Target = []
                options.Text          (1,:) char = ''
                options.Tooltip       (1,:) char = 'Copy this window to the clipboard'
                options.FontSize      (1,1) double = 12
                options.FlashDuration (1,1) double = 1.5
            end

            if isempty(options.Target)
                options.Target = obj.h_figure;
            end

            args = namedargs2cell(options);
            h = gui.ScreenCapture(parent, args{:});
            obj.register(h);
        end

        function h = addHistory(obj, parent, options)
            % h = addHistory(obj, parent, ...)
            % Create a gui.History per-trial outcome table over this GUI's
            % psychophysics object and register it for teardown.
            %
            % Returns [] when createPsych produced nothing, the way
            % addControl returns [] for a parameter that does not resolve: a
            % GUI must still open against a runtime with no interfaces
            % (epsych.SelfTest check I6). See gui.History for options.
            arguments
                obj
                parent (1,1)
                options.ColumnFormats = string.empty(0,1)
                options.BitColors = string.empty(0,1)
                options.PreferenceTag {mustBeTextScalar} = ''
            end

            h = [];
            if ~obj.hasPsych_('gui.History'), return; end

            args = namedargs2cell(options);
            h = gui.History(obj.Psych, parent, args{:});
            obj.register(h);
        end

        function h = addScatter(obj, parent, options)
            % h = addScatter(obj, parent, ...)
            % Create a gui.ParameterScatter over any two recorded trial
            % parameters and register it for teardown.
            %
            % The source is this GUI's runtime rather than its psych object:
            % the scatter draws whatever the trials recorded, so it works in
            % a paradigm that has no analysis at all. See gui.ParameterScatter.
            arguments
                obj
                parent (1,1)
                options.BoxID (1,:) double = []
                options.XParameter {mustBeTextScalar} = ''
                options.YParameter {mustBeTextScalar} = ''
                options.ColorParameter {mustBeTextScalar} = ''
                options.PreferenceTag {mustBeTextScalar} = ''
            end

            args = namedargs2cell(options);
            h = gui.ParameterScatter(obj.RUNTIME, parent, args{:});
            obj.register(h);
        end

        function h = addPsychPlot(obj, parent)
            % h = addPsychPlot(obj, parent)
            % Create a gui.PsychPlot psychometric curve over this GUI's
            % psychophysics object and register it for teardown. Returns []
            % when there is no psych object.
            %
            % gui.PsychPlot draws into a CLASSIC axes, not a uiaxes, so one
            % is made here inside the container you give: pass a panel or a
            % grid cell rather than an axes of your own.
            arguments
                obj
                parent (1,1)
            end

            h = [];
            if ~obj.hasPsych_('gui.PsychPlot'), return; end

            ax = axes(parent);
            h = gui.PsychPlot(obj.Psych, ax);
            obj.register(h);
        end

        function ax = addStaircasePlot(obj, parent)
            % ax = addStaircasePlot(obj, parent)
            % Plot this GUI's psychophysics.Staircase -- its track, reversals
            % and threshold -- into a new uiaxes inside parent, and return
            % the axes.
            %
            % The staircase draws ITSELF (psychophysics.Staircase.Plot), so
            % there is no component to register: the analysis object owns the
            % listener and the redraw, and it is torn down with the GUI that
            % created it. Returns [] when there is no staircase, or when the
            % psych object is some other analysis.
            arguments
                obj
                parent (1,1)
            end

            ax = [];
            if ~obj.hasPsych_('the staircase plot'), return; end
            if ~ismethod(obj.Psych, 'Plot')
                vprintf(2, '%s: staircase plot skipped; %s cannot plot itself', ...
                    class(obj), class(obj.Psych))
                return
            end

            ax = uiaxes(parent);
            obj.Psych.Plot(ax);
        end

        function h = addSessionClock(obj, parent, options)
            % h = addSessionClock(obj, parent, ...)
            % Create a gui.SessionClock -- time since the last trial, since
            % the first, session duration, wall clock -- wire it to this
            % GUI's runtime, start it, and register it for teardown.
            %
            % The clock builds its own panel inside parent, so in a grid cell
            % use the returned object's PanelH to place it:
            %   c = obj.addSessionClock(g);
            %   c.PanelH.Layout.Row = 1; c.PanelH.Layout.Column = 2;
            % See gui.SessionClock for options.
            arguments
                obj
                parent (1,1)
                options.PreferenceTag (1,:) char = ''
                options.UpdatePeriod (1,1) double {mustBePositive, mustBeFinite} = 1
                options.FontSize (1,1) double {mustBePositive, mustBeFinite} = 12
                options.FontColor (1,3) double {mustBeNonnegative} = [0 0 0]
                options.ShowTimeSinceLastTrial (1,1) logical = true
                options.ShowTimeSinceFirstTrial (1,1) logical = true
                options.ShowSessionDuration (1,1) logical = true
                options.ShowClockTime (1,1) logical = true
            end

            args = namedargs2cell(options);
            h = gui.SessionClock(parent, args{:});
            h.attachRuntime(obj.RUNTIME);
            h.start();
            obj.register(h);
        end

        function h = addTrialTimer(obj, parent, options)
            % h = addTrialTimer(obj, parent, ...)
            % Create a gui.ElapsedTrialTimer -- time since the last completed
            % trial -- wire it to this GUI's runtime and register it for
            % teardown. See gui.ElapsedTrialTimer for options.
            arguments
                obj
                parent (1,1)
                options.UpdatePeriod (1,1) double {mustBePositive, mustBeFinite} = 0.5
                options.Format (1,:) char = 'hms'
                options.FontSize (1,1) double {mustBePositive, mustBeFinite} = 12
                options.FontColor (1,3) double {mustBeNonnegative} = [0 0 0]
                options.FontWeight (1,:) char = 'normal'
                options.Prefix (1,:) char = 'Last trial: '
            end

            args = namedargs2cell(options);
            h = gui.ElapsedTrialTimer(parent, args{:});
            h.attachRuntime(obj.RUNTIME);
            obj.register(h);
        end

        function h = addModeIndicator(obj, parent, options)
            % h = addModeIndicator(obj, parent, FontSize=...)
            % Create a gui.ModeIndicator lamp showing the session's run mode,
            % wire it to this GUI's runtime and register it for teardown.
            arguments
                obj
                parent (1,1)
                options.FontSize (1,1) double = 11
            end

            args = namedargs2cell(options);
            h = gui.ModeIndicator(parent, args{:});
            h.attachRuntime(obj.RUNTIME);
            obj.register(h);
        end

        function h = addSessionGate(obj, parent, options)
            % h = addSessionGate(obj, parent, ...)
            % Create a gui.SessionGate "Begin Experiment" button and register
            % it for teardown. Nothing runs until it is pressed -- but only
            % because something WAITS on it, which is the other half:
            %
            %   function obj = MyGUI(RUNTIME)
            %       obj@gui.BehaviorGUI(RUNTIME, Name='My Task');
            %       obj.waitForSessionGate();   % after the window exists
            %   end
            %
            % The wait cannot happen here: build runs from inside the base
            % constructor, before the figure is shown, so blocking in it
            % would hold the session at a window nobody can click.
            %
            % See gui.SessionGate for options.
            arguments
                obj
                parent (1,1)
                options.Text (1,:) char = 'Begin Experiment'
                options.RunningText (1,:) char = 'Experiment Running'
                options.PreviewText (1,:) char = 'Preview Running'
                options.CompleteText (1,:) char = 'Session Complete'
                options.Tooltip (1,:) char = 'Start the session; no trial runs until this is pressed'
                options.FontSize (1,1) double {mustBePositive, mustBeFinite} = 14
                options.FontWeight (1,:) char {mustBeMember(options.FontWeight,{'normal','bold'})} = 'bold'
                options.BackgroundColor (1,3) double {mustBeNonnegative} = [0.45 0.75 0.45]
            end

            args = namedargs2cell(options);
            h = gui.SessionGate(parent, args{:});
            h.attachRuntime(obj.RUNTIME);
            obj.register(h);
        end

        function tf = waitForSessionGate(obj, timeout)
            % tf = waitForSessionGate(obj, timeout)
            % Hold the session until the operator presses the gate added by
            % addSessionGate, returning whether it opened. Call it from the
            % subclass constructor, after the base constructor has returned.
            %  timeout - seconds to wait. Default Inf.
            %
            % Returns true immediately with no gate in the GUI, so a
            % paradigm can drop the button without touching its constructor.
            %
            % Returns true immediately in ReviewMode as well: the wait exists
            % to hold a STARTING session until the operator is at the box,
            % and a review has no session to hold. Blocking there would hang
            % epsych.ReviewSession inside feval, with a half-built window and
            % no way to reach the button.
            arguments
                obj
                timeout (1,1) double {mustBePositive} = Inf
            end

            tf = true;
            if obj.ReviewMode, return; end

            gates = obj.componentsOfClass_('gui.SessionGate');
            if isempty(gates), return; end
            tf = gates{1}.wait(timeout);
        end

        function h = addPopOutButton(obj, parent, component, options)
            % h = addPopOutButton(obj, parent, component, Text=..., Tooltip=...)
            % Create a button that opens a display in a window of its own,
            % for something an operator only wants to see occasionally.
            %  component - any gui.PopOut component (gui.ParameterScatter,
            %              gui.History, gui.SessionPerformance, gui.NextTrial,
            %              gui.Parameter_Monitor, gui.PsychPlot, a plotted
            %              psychophysics.Staircase, ...). A component that is
            %              not poppable is skipped with a message, matching
            %              addControl's tolerance of missing parameters.
            % The embedded component is left exactly as it is; the button
            % opens its pop-out, or raises the window when one is already up.
            arguments
                obj
                parent (1,1)
                component
                options.Text (1,:) char = 'Pop Out'
                options.Tooltip (1,:) char = 'Open this display in a separate window'
            end

            h = [];
            if isempty(component) || ~isa(component,'gui.PopOut') || ~isvalid(component)
                vprintf(2, 'gui.BehaviorGUI: pop-out button skipped; component is not a gui.PopOut')
                return
            end

            h = uibutton(parent, 'Text', options.Text, ...
                'Tooltip', options.Tooltip, ...
                'ButtonPushedFcn', @(~,~) component.popOut());
            obj.register(h);
        end

        function tb = addComponentToolbar(obj, fig, options)
            % tb = addComponentToolbar(obj, fig, Style=..., Exclude=..., AutoDiscover=...)
            % Add an icon toolbar that opens display components in windows of
            % their own. Optional: a GUI that never calls this has no toolbar.
            %
            % Call it at the TOP of build. Every gui.PopOut component
            % registered anywhere in build gets a tool automatically, because
            % the list is collected after build returns rather than now.
            % Components the GUI does not display are declared on the returned
            % toolbar with addLazyComponent and built on first click:
            %
            %   function build(obj, fig)
            %       tb = obj.addComponentToolbar(fig);
            %       tb.addLazyComponent('Performance', ...
            %           @(c) gui.SessionPerformance(obj.RUNTIME, c), ...
            %           Icon='sessionperformance');
            %       ... the rest of the layout ...
            %   end
            %
            %  Style        - 'push' (default) opens or raises on click;
            %                 'toggle' also shows which windows are open and
            %                 closes one when its pressed tool is clicked.
            %  Exclude      - class or register names to leave off the toolbar.
            %  AutoDiscover - false lists only what addLazyComponent declares.
            arguments
                obj
                fig (1,1) matlab.ui.Figure
                options.Style (1,1) string {mustBeMember(options.Style,["push","toggle"])} = "push"
                options.Exclude (1,:) string = string.empty(1,0)
                options.AutoDiscover (1,1) logical = true
            end

            if ~isempty(obj.ComponentToolbar_) && isvalid(obj.ComponentToolbar_)
                vprintf(2, '%s: component toolbar already added; returning it', class(obj))
                tb = obj.ComponentToolbar_;
                return
            end

            tb = gui.ComponentToolbar(obj, fig, Style=options.Style, ...
                Exclude=options.Exclude, AutoDiscover=options.AutoDiscover);
            obj.ComponentToolbar_ = tb;
            obj.register(tb, 'ComponentToolbar');
        end

        function comp = register(obj, comp, name)
            % comp = register(obj, comp, name)
            % Add any component (handle object or graphics) to the
            % teardown registry. Registered handle objects are deleted by
            % the destructor even though deleting the figure alone would
            % only remove their graphics, leaving listeners and timers
            % alive.
            %  name - what to call this component on a component toolbar.
            %         Left empty, the toolbar spaces out the class name, which
            %         is only ambiguous when one GUI holds two components of
            %         the same class.
            arguments
                obj
                comp
                name (1,:) char = ''
            end
            obj.Components_{end+1}     = comp;
            obj.ComponentNames_{end+1} = name;
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

        function savePopOutLayout(obj)
            % savePopOutLayout(obj)
            % Record which display windows are open right now. Called for you
            % whenever one opens or closes, and once more as the GUI comes
            % apart; call it by hand only after turning RestorePopOuts on
            % with windows already up. Does nothing while RestorePopOuts is
            % off, or while restorePopOutLayout is doing the reopening.
            if ~obj.RestorePopOuts || obj.RestoringPopOuts_, return; end
            ids = obj.openPopOutIdentities_();
            try
                setpref(obj.PreferenceTag, obj.POPOUT_LAYOUT_PREF, cellstr(ids));
                vprintf(3, '%s: remembering %d open display window(s)', class(obj), numel(ids))
            catch ME
                vprintf(2, '%s: could not save the display layout: %s', class(obj), ME.message)
            end
        end

        function n = restorePopOutLayout(obj)
            % n = restorePopOutLayout(obj)
            % Reopen the display windows recorded by the last session and
            % return how many opened. Each comes back in the position, size,
            % font, options and pinned state it was left in, because those
            % belong to the component's own pop-out preference key rather
            % than to the list this reads.
            %
            % A remembered entry the GUI no longer has -- a component
            % renamed, a paradigm changed, a protocol without that parameter
            % -- is skipped with a message and left in the list, so a GUI
            % that opens against a reduced protocol does not erase the
            % layout the full one had.
            n = 0;
            ids = obj.savedPopOutIdentities_();
            if isempty(ids), return; end

            obj.RestoringPopOuts_  = true;
            obj.UnresolvedPopOuts_ = string.empty(1,0);
            try
                [comps, entryIds] = obj.popOutEntries_();
                for k = 1:numel(ids)
                    if startsWith(ids(k), "Toolbar:")
                        n = n + obj.reopenToolbarEntry_(ids(k));
                    else
                        n = n + obj.reopenComponent_(ids(k), comps, entryIds);
                    end
                end
            catch ME
                vprintf(0,1, ME)
            end
            obj.RestoringPopOuts_ = false;

            if n == 0, return; end
            vprintf(1, '%s: reopened %d display window(s) from the last session', class(obj), n)

            % The GUI itself was made first and is now underneath whatever
            % came back; put it in front so the operator sees the controls.
            try
                if obj.h_figure.Visible == "on"
                    figure(obj.h_figure);
                end
            catch
            end
        end

        function forgetPopOutLayout(obj)
            % forgetPopOutLayout(obj)
            % Discard the remembered list, so the next launch opens with no
            % display windows. The windows themselves, and everything each
            % remembers about its own appearance, are left alone.
            try
                if ispref(obj.PreferenceTag, obj.POPOUT_LAYOUT_PREF)
                    rmpref(obj.PreferenceTag, obj.POPOUT_LAYOUT_PREF);
                end
            catch ME
                vprintf(2, '%s: could not clear the display layout: %s', class(obj), ME.message)
            end
        end
    end

    methods (Hidden)

        function notePopOutStateChanged_(obj)
            % notePopOutStateChanged_(obj)
            % A display window opened or closed. gui.ComponentToolbar calls
            % this for the windows it owns; the windows components own are
            % reported by their own PopOutStateChanged event.
            if ~isvalid(obj) || obj.TearingDown_, return; end
            obj.savePopOutLayout();
        end
    end

    methods (Access = protected)

        function p = createPsych(obj, RUNTIME)
            % Override to create a psychophysics object; its Events broadcaster then
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

        function tf = hasPsych_(obj, what)
            % Is there a usable analysis object for a display that needs one?
            % Says so at debug level rather than throwing, because a GUI must
            % still open against a runtime whose parameters never resolved
            % and so produced no psych object (epsych.SelfTest check I6).
            tf = ~isempty(obj.Psych) && isvalid(obj.Psych);
            if ~tf
                vprintf(2, '%s: %s skipped; this GUI has no psychophysics object', ...
                    class(obj), what)
            end
        end

        function c = componentsOfClass_(obj, cls)
            % Registered components of a class, in registration order, as a
            % cell array. The registry holds graphics handles as well as
            % component objects, so the class test has to tolerate both.
            match = cellfun(@(h) isa(h, cls) && isvalid(h), obj.Components_);
            c = obj.Components_(match);
        end

        function closeExistingInstance_(obj)
            % Only one instance per PreferenceTag: replace an existing
            % window. Detach UserData/CloseRequestFcn before deleting so
            % figure deletion cannot recurse into the old object.
            f = findall(groot, 'Type', 'figure', '-and', 'Tag', obj.PreferenceTag);
            for i = 1:numel(f)
                try
                    gui.BehaviorGUI.saveFigurePosition(obj.PreferenceTag, f(i).Position);
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
                vprintf(2, 'gui.BehaviorGUI: could not determine session state (%s)', ME.message)
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
            vprintf(2, 'gui.BehaviorGUI: parameter "%s" not available; control skipped', name)
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

        function [comps, labels] = popOutComponents_(obj)
            % Components that can open a window of their own, in registration
            % order, with the name each should be called on a toolbar.
            % Returned as a cell array: gui.PopOut is a mixin, so two adopters
            % share no concrete class that could hold them in one array.
            comps  = {};
            labels = strings(1,0);
            for i = 1:numel(obj.Components_)
                c = obj.Components_{i};
                if ~isobject(c) || ~isvalid(c) || ~isa(c, 'gui.PopOut'), continue; end
                comps{end+1}  = c;
                labels(end+1) = gui.ComponentToolbar.entryLabel(class(c), obj.ComponentNames_{i});
            end

            % The psych object last: a plotted psychophysics.Staircase is a
            % display like any other, but it is createPsych's return value
            % rather than something build registered, so nothing above finds
            % it. Skipped when a subclass registered it as well.
            p = obj.Psych;
            if isempty(p) || ~isvalid(p) || ~isa(p, 'gui.PopOut'), return; end
            if any(cellfun(@(c) c == p, comps)), return; end
            comps{end+1}  = p;
            labels(end+1) = gui.ComponentToolbar.entryLabel(class(p));
        end

        function [comps, ids] = popOutEntries_(obj)
            % Poppable components with the identity each is remembered under.
            % The identity is the name the component toolbar would give it —
            % its register name, else its class spaced out — made unique the
            % same way, so a GUI holding two of a class still tells them
            % apart. Registration order decides which is which, which is why
            % a paradigm that reorders build should expect the memory to
            % point at the other one; naming both in register() pins it.
            [comps, labels] = obj.popOutComponents_();
            ids = strings(1, numel(comps));
            for i = 1:numel(comps)
                n = sum(labels(1:i) == labels(i));
                if n > 1
                    ids(i) = sprintf('Component:%s %d', labels(i), n);
                else
                    ids(i) = "Component:" + labels(i);
                end
            end
        end

        function ids = openPopOutIdentities_(obj)
            % Identities of every display window open right now. Toolbar
            % entries are asked only about the windows the TOOLBAR owns: an
            % automatic entry's window belongs to its component, which is
            % already counted above and would otherwise be listed twice.
            ids = string.empty(1,0);
            [comps, entryIds] = obj.popOutEntries_();
            for i = 1:numel(comps)
                try
                    if comps{i}.hasPopOut()
                        ids(end+1) = entryIds(i);
                    end
                catch
                end
            end

            tb = obj.ComponentToolbar_;
            if ~isempty(tb) && isvalid(tb)
                try
                    ids = [ids, "Toolbar:" + tb.openLazyNames_()];
                catch ME
                    vprintf(2, '%s: could not list the toolbar windows: %s', class(obj), ME.message)
                end
            end

            % Carried over from the restore: displays this GUI cannot show
            % stay remembered rather than being written out of the list.
            ids = unique([ids, obj.UnresolvedPopOuts_], 'stable');
        end

        function ids = savedPopOutIdentities_(obj)
            % The remembered list, as a string row. Anything that is not a
            % list of text is treated as nothing saved rather than repaired:
            % a preference written by an older or different version of this
            % class is not something to guess at.
            ids = string.empty(1,0);
            try
                if ~ispref(obj.PreferenceTag, obj.POPOUT_LAYOUT_PREF), return; end
                raw = getpref(obj.PreferenceTag, obj.POPOUT_LAYOUT_PREF);
                if isempty(raw), return; end
                if ~iscellstr(raw) && ~isstring(raw)
                    vprintf(2, '%s: ignoring an unreadable saved display layout', class(obj))
                    return
                end
                ids = reshape(string(raw), 1, []);
            catch ME
                vprintf(2, '%s: could not read the saved display layout: %s', class(obj), ME.message)
            end
        end

        function n = reopenComponent_(obj, id, comps, entryIds)
            % Pop out the registered component recorded as id.
            n = 0;
            j = find(entryIds == id, 1);
            if isempty(j)
                obj.noteUnresolved_(id, extractAfter(id, "Component:"), 'this GUI has no such display');
                return
            end
            comps{j}.popOut();
            n = double(comps{j}.hasPopOut());
        end

        function n = reopenToolbarEntry_(obj, id)
            % Open the toolbar's own window for the lazy entry id names.
            n = 0;
            name = extractAfter(id, "Toolbar:");
            tb = obj.ComponentToolbar_;
            if isempty(tb) || ~isvalid(tb) || ~tb.openLazyByName_(name)
                obj.noteUnresolved_(id, name, 'it is no longer on the toolbar');
                return
            end
            n = 1;
        end

        function noteUnresolved_(obj, id, label, why)
            % Set a remembered display aside instead of dropping it. It is
            % written back out with the next save, so a session run against
            % a protocol that has fewer displays does not quietly erase the
            % layout the fuller one had.
            obj.UnresolvedPopOuts_(end+1) = id;
            vprintf(2, '%s: "%s" was open last session but %s; leaving it remembered', ...
                class(obj), label, why)
        end

        function attachPopOutListeners_(obj)
            % One PopOutStateChanged listener per poppable component, so the
            % memory is written the moment a window opens or closes rather
            % than at teardown — which a MATLAB that was killed never reaches.
            obj.detachPopOutListeners_();
            comps = obj.popOutComponents_();
            L = event.listener.empty(1,0);
            for i = 1:numel(comps)
                try
                    L(end+1) = listener(comps{i}, 'PopOutStateChanged', ...
                        @(~,~) obj.notePopOutStateChanged_());
                catch ME
                    vprintf(3, '%s: cannot watch %s for pop-out changes: %s', ...
                        class(obj), class(comps{i}), ME.message)
                end
            end
            obj.PopOutListeners_ = L;
        end

        function detachPopOutListeners_(obj)
            for i = 1:numel(obj.PopOutListeners_)
                try
                    delete(obj.PopOutListeners_(i));
                catch
                end
            end
            obj.PopOutListeners_ = event.listener.empty(1,0);
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
