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
    %   Every reusable component is placed with ONE method:
    %
    %       h = obj.add('gui.components.NextTrial', pnl, FontSize=14);
    %
    %   add registers what it builds for teardown, wires it to the runtime,
    %   the analysis object or the key bindings as the component's own
    %   gui.ComponentSpec says, and returns [] at debug level rather than
    %   throwing when the session cannot support it -- a parameter that does
    %   not resolve, an analysis that was never built -- so the GUI still
    %   opens against a runtime with no interfaces (epsych.SelfTest check
    %   I6). A class from outside this toolbox works the same way with no
    %   registration: its constructor signature is enough.
    %
    %   The short names that survive are sugar over add, kept because they
    %   read better at 68 call sites: addControl and addButton (both
    %   gui.components.Parameter_Control), addUpdateButton, controlColumn.
    %   addStaircasePlot and addPopOutButton are not wrappers -- they build
    %   things that are not components. Nothing per-component lives in this
    %   class any more; see gui.ComponentSpec for how a component declares
    %   what it needs.
    %
    %   Session-record notes are standard for every subclass: the commit
    %   paths of the stock components record what the operator changed into
    %   RUNTIME.NOTES (epsych.SessionNotes) -- a gui.components.Parameter_Update commit,
    %   an autoCommit addControl edit, a gui.components.PhaseSelector phase load or
    %   save each add a trial-stamped entry via epsych.SessionNotes.log.
    %   Because the note store is folded into the Info variable every saving
    %   function writes and journaled per trial, those entries are part of
    %   every subject's data file whether or not the GUI includes a
    %   gui.components.Notes component. Automatic per-trial writes (a staircase
    %   stepping a parameter, a trial selector's dispatch) are deliberately
    %   NOT recorded -- only operator actions are. addButton's session
    %   toggles and triggers record nothing either: they are momentary by
    %   design, and the trial record already carries their effect.
    %
    %   Display components that inherit gui.PopOut (the scatter, history,
    %   performance, next-trial, monitor, and plot components) can be opened
    %   in a window of their own from their right-click menu, or from a
    %   button made with addPopOutButton. A pop-out is a separate instance
    %   over the same data, so it never disturbs the embedded one.
    %
    %   add('gui.components.ComponentToolbar', fig) collects those windows onto one icon toolbar, and
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
    %   Keyboard shortcuts go through obj.Keys, a gui.KeyBindings that owns
    %   this figure's key callbacks:
    %
    %       obj.Keys.bind('leftarrow', @() obj.respondSide(0), ...
    %           Description = 'Respond LEFT');
    %
    %   Never assign fig.WindowKeyPressFcn or WindowKeyReleaseFcn on the main
    %   figure. There is one slot for each, and assigning it takes the keys
    %   away from every component that already asked for one -- which is the
    %   bug this class exists to prevent. Helpers that come with a default
    %   chord (addUpdateButton, and the ScreenCapture and Notes components) take
    %   KeyBinding='none' to drop it, or a chord of your own to change it.
    %   Ctrl+Shift+? and F1 list what is bound.
    %
    %   Two limits worth knowing: a uifigure delivers no window key event
    %   while an edit field has focus (which is also what stops a shortcut
    %   firing mid-note), and a binding is suppressed in a review unless it
    %   was bound with EnableInReview=true.
    %
    %   NewData listener source: when createPsych returns a psychophysics
    %   object, NewData is taken from Psych.Events so the psych object has
    %   already processed the trial before onNewData runs; otherwise
    %   NewData comes from RUNTIME.EVENTS directly.
    %
    % Documentation: documentation/gui/gui_BehaviorGUI.md
    % See also gui.components.Parameter_Control, gui.components.Parameter_Update,
    % gui.components.Parameter_Monitor, epsych.RunExpt

    properties (SetAccess = protected)
        RUNTIME                 % epsych.Runtime object
        P (1,1) struct = struct() % Parameters keyed by validName (may be empty pre-hardware)
        Psych                   % psychophysics object from createPsych, or []
        h_figure                % Main uifigure handle
        PreferenceTag (1,:) char % Figure Tag and getpref/setpref group
        Keys                    % gui.KeyBindings owning this figure's key callbacks
    end

    properties
        RestorePopOuts (1,1) logical = false % Reopen the displays left open last session
    end

    properties (Dependent, SetAccess = private)
        % addButton controls, keyed by parameter validName.
        %
        % Derived from the component registry rather than accumulated, so it
        % cannot drift from what was actually built: a button whose parameter
        % did not resolve was never registered and is simply absent, which is
        % the same answer the accumulated struct used to give.
        hButtons (1,1) struct

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
        Deferred_ (1,:) cell = {}   % closures queued until the first NewTrial
        FirstTrialSeen_ (1,1) logical = false
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
            if strcmp(gui.BehaviorGUI.getSavedFigureWindowState(obj.PreferenceTag), 'maximized')
                try
                    fig.WindowState = 'maximized';
                catch ME
                    vprintf(2, '%s: could not restore the maximized window: %s', ...
                        class(obj), ME.message)
                end
            end
            obj.h_figure = fig;

            % Before build, so build can bind. A figure has one
            % WindowKeyPressFcn slot and components used to take it from one
            % another silently; this object owns it and hands out bindings.
            obj.Keys = gui.KeyBindings(fig);
            obj.Keys.ReviewModeFcn = @() obj.ReviewMode;
            obj.Keys.bind('ctrl+shift+slash', @() obj.Keys.showHelp(), ...
                Description = 'Show this shortcut list', Group = 'Help', ...
                EnableInReview = true);
            obj.Keys.bind('f1', @() obj.Keys.showHelp(), ...
                Description = 'Show this shortcut list', Group = 'Help', ...
                EnableInReview = true);

            obj.build(fig);

            % Again after build: the subclass, or a component that predates
            % gui.KeyBindings, may have assigned the figure's key callback
            % outright in there. This takes the slot back and chains what it
            % found, so both keep working. The stock components no longer
            % claim it -- gui.components.Parameter_Update and gui.components.RegenerateTrial each
            % resolve a KeyBindings with getOrCreate instead.
            obj.Keys.claimFigure();

            obj.wireUpdateButtons_();

            % Auto discovery runs here rather than when the toolbar is added
            % because build is normally where the toolbar is asked for, before
            % the components it should list have been registered.
            tb_ = obj.componentToolbar_();
            if ~isempty(tb_)
                [comps, labels] = obj.popOutComponents_();
                tb_.populateAuto_(comps, labels);
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

            % Likewise the window's own position. closeGUI already saved it
            % on the operator's path out, but a GUI torn down any other way
            % -- delete(obj) from a script, a review session closing down --
            % would otherwise leave the next session opening at whatever
            % rectangle was last written, on whatever monitor that was.
            try
                if ~isempty(obj.h_figure) && isvalid(obj.h_figure)
                    gui.BehaviorGUI.saveFigureLayout(obj.PreferenceTag, obj.h_figure);
                end
            catch
            end
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

            % After the components, since one may unbind on its way out.
            try
                if ~isempty(obj.Keys) && isvalid(obj.Keys)
                    delete(obj.Keys);
                end
            catch
            end

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
                gui.BehaviorGUI.saveFigureLayout(obj.PreferenceTag, src);
            catch
            end
            delete(obj);
            try
                delete(src);
            catch
            end
        end

        function s = get.hButtons(obj)
            % Buttons in registration order, keyed by parameter validName.
            s = struct();
            for c = gui.components.Parameter_Control.buttonsIn(obj)
                try
                    s.(c{1}.Parameter.validName) = c{1};
                catch
                end
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

        function h = add(obj, cls, parent, varargin)
            % h = add(obj, cls, parent, Name=Value, ...)
            % Build a component of class cls into parent, wire it to this
            % GUI, and register it for teardown.
            %
            % cls is a FULLY-QUALIFIED class name. A class that declares a
            % static getComponentSpec is built to that spec; anything else
            % gets one inferred from its constructor signature, so a
            % component from outside this toolbox needs no registration of
            % any kind:
            %
            %   obj.add("mylab.RasterPlot", pnl, Channel=3)
            %
            % Returns [] and says why at debug level when the session cannot
            % support the component -- a parameter that does not resolve, an
            % analysis that was never built -- so a GUI still opens against a
            % runtime with no interfaces (epsych.SelfTest check I6).
            %
            % Options are forwarded VERBATIM: an option you do not name is
            % not passed at all, which is what lets a component fall back to
            % the operator's own saved preference rather than being handed a
            % default nobody chose.
            %
            % Three option names are consumed here and never forwarded:
            %   Variant      - select a non-primary variant of a class that
            %                  declares several (gui.components.Parameter_Control is
            %                  both the Control and the Button)
            %   KeyBinding   - replace, or drop with 'none', the component's
            %                  default keyboard chord
            %   RegisterName - name this instance for the component toolbar
            %                  and the pop-out memory
            %
            % See also gui.ComponentSpec, register
            h = [];
            cls = char(string(cls));

            [opts, ok] = gui.BehaviorGUI.parseOptions_(varargin, cls, class(obj));
            if ~ok, return; end

            [variant, opts] = gui.BehaviorGUI.popOption_(opts, 'Variant', '');
            variant = char(string(variant));

            spec = gui.ComponentSpec.forClass(cls, variant);
            if isempty(spec.className)
                % Level 1, not 2: a typo in a paradigm's build must be visible
                % at default verbosity, or SelfTest passes over a GUI that is
                % quietly missing a display.
                vprintf(1, '%s: no class "%s" on the path; component skipped', class(obj), cls)
                return
            end
            if spec.isAbstract
                % A condition, not a defect: refuse it here rather than
                % letting the constructor throw and logging it as one.
                vprintf(2, '%s: "%s" is abstract and cannot be built; component skipped', ...
                    class(obj), cls)
                return
            end

            % Option names the spec knows are matched case-insensitively,
            % the way the arguments block they end up in would match them.
            % Every consumer below tests exact field names, so without this
            % 'autocommit=false' would sit beside a fixedOptions 'autoCommit'
            % and lose to it -- the opposite of "the caller always wins".
            opts = gui.BehaviorGUI.canonicalizeOptions_(spec, opts);

            [chord, opts]   = gui.BehaviorGUI.popOption_(opts, 'KeyBinding',   spec.keyBinding);
            [regName, opts] = gui.BehaviorGUI.popOption_(opts, 'RegisterName', spec.registerName);
            chord   = char(string(chord));
            regName = char(string(regName));

            % Variant defaults, e.g. addButton's autoCommit. The caller
            % always outranks them.
            fn = fieldnames(spec.fixedOptions);
            for k = 1:numel(fn)
                if ~isfield(opts, fn{k})
                    opts.(fn{k}) = spec.fixedOptions.(fn{k});
                end
            end

            if spec.singleton
                existing = obj.componentsOfClass_(cls);
                if ~isempty(existing)
                    vprintf(2, '%s: %s already added; returning it', class(obj), spec.label)
                    h = existing{1};
                    return
                end
            end

            if ~obj.specPreconditionsMet_(spec, opts), return; end

            [opts, ok] = obj.resolveSpecParameters_(spec, opts);
            if ~ok, return; end

            % Decisions that must be made BEFORE construction, when they
            % depend on a resolved parameter: gui.components.Parameter_Control picks
            % 'toggle' over 'momentary' from a '~'-prefixed name, and its
            % type is immutable once built.
            if ~isempty(spec.preFcn)
                try
                    opts = spec.preFcn(opts, obj, struct('parent', parent, 'spec', spec));
                catch ME
                    vprintf(2, '%s: %s pre-construction step failed (%s)', ...
                        class(obj), spec.label, ME.message)
                end
            end

            canvasH = [];
            if ~strcmp(spec.canvas, 'none')
                try
                    switch spec.canvas
                        case 'axes',   canvasH = axes(parent);
                        case 'uiaxes', canvasH = uiaxes(parent);
                    end
                catch ME
                    vprintf(2, '%s: could not make the %s for %s (%s)', ...
                        class(obj), spec.canvas, spec.label, ME.message)
                    return
                end
            end

            [pos, opts, ok] = obj.buildSpecPositionals_(spec, parent, canvasH, opts);
            if ~ok
                delete(canvasH)
                return
            end

            opts = obj.applySpecInjections_(spec, opts);

            % Options this GUI acts on itself rather than handing to the
            % constructor (gui.components.OnlinePlot's TimeWindow, which is applied
            % after construction and only if nothing was remembered).
            hostOpts = struct();
            for o = spec.hostOptions
                n = char(o);
                if isfield(opts, n)
                    hostOpts.(n) = opts.(n);
                    opts = rmfield(opts, n);
                end
            end

            % Not namedargs2cell: opts holds only what was stated, and an
            % absent field must stay an absent argument.
            f  = fieldnames(opts);
            nv = cell(1, 2*numel(f));
            nv(1:2:end) = f;
            nv(2:2:end) = struct2cell(opts);
            try
                h = feval(cls, pos{:}, nv{:});
            catch ME
                % Louder than a skip: a precondition failing is expected, a
                % constructor throwing is a defect. Never rethrown (I6).
                vprintf(1, '%s: %s could not be created from [%s]', ...
                    class(obj), spec.label, strjoin(f, ' '))
                vprintf(1, 1, ME)
                delete(canvasH)
                h = [];
                return
            end

            % gui.components.OnlinePlot deletes itself when its source dialog is
            % cancelled, so this tests validity, not emptiness alone.
            if isempty(h) || ~isvalid(h)
                vprintf(2, '%s: %s returned nothing usable; skipping', class(obj), spec.label)
                delete(canvasH)
                h = [];
                return
            end

            if spec.attachRuntime
                try
                    h.attachRuntime(obj.RUNTIME);
                catch ME
                    vprintf(2, '%s: %s would not take the runtime (%s)', ...
                        class(obj), spec.label, ME.message)
                end
            end
            if spec.start
                try
                    h.start();
                catch ME
                    vprintf(2, '%s: %s would not start (%s)', class(obj), spec.label, ME.message)
                end
            end
            if ~isempty(spec.postFcn)
                ctx = struct('parent', parent, 'canvas', canvasH, ...
                    'options', opts, 'host', hostOpts, 'spec', spec);
                try
                    spec.postFcn(h, obj, ctx);
                catch ME
                    vprintf(2, '%s: %s post-construction step failed (%s)', ...
                        class(obj), spec.label, ME.message)
                end
            end

            obj.register(h, regName);
            obj.bindSpecKey_(spec, chord, h);
        end

        function c = componentsOfClass(obj, cls)
            % c = componentsOfClass(obj, cls)
            % Registered components of a class, in registration order, as a
            % cell array. Public so a component's own spec helpers can ask
            % what else this GUI already holds.
            c = obj.componentsOfClass_(cls);
        end

        % --- Component helpers ------------------------------------------
        %
        % Every helper below is a thin wrapper over add. They exist because
        % their call sites read better -- addControl(col,'ITIDur') says what
        % it means -- not because they carry any logic of their own. What
        % each component needs is declared by its own getComponentSpec, so
        % ADDING A COMPONENT REQUIRES NO EDIT TO THIS CLASS: call
        % obj.add('pkg.MyComponent', parent, ...) and it works.
        %
        % Three helpers are not wrappers, because they build something that
        % is not a component: controlColumn (layout), addStaircasePlot (the
        % analysis object draws itself into an axes and there is nothing to
        % register) and addPopOutButton (a plain button ABOUT a component).

        function h = addControl(obj, parent, param, varargin)
            % h = addControl(obj, parent, param, ...)
            % Create a gui.components.Parameter_Control bound to a parameter and
            % register it for teardown and Parameter_Update watching.
            %  param - hw.Parameter, or a name resolved against obj.P.
            %          Unresolved names return [] without error so one build
            %          method serves protocols with differing parameter sets
            %          (and the pre-hardware SelfTest run).
            % Options are forwarded to gui.components.Parameter_Control unchanged; see
            % it for Type, BoundProperty, autoCommit, Text, EnabledBy,
            % DisabledBy, PostUpdateFcn and EvaluatorFcn.
            h = obj.add('gui.components.Parameter_Control', parent, 'Parameter', param, varargin{:});
        end

        function h = addButton(obj, parent, param, varargin)
            % h = addButton(obj, parent, param, ...)
            % Create an auto-committing trigger or toggle button. A
            % '~'-prefixed parameter name makes a latching toggle, anything
            % else a momentary press; each button takes the next accent
            % colour. Unresolved names return [] without error.
            %
            % Unlike addControl this passes no Runtime, so a self-clearing
            % session toggle never lands in the trial table.
            h = obj.add('gui.components.Parameter_Control', parent, 'Parameter', param, ...
                'Variant', 'Button', varargin{:});
        end

        function lay = controlColumn(~, parent, varargin)
            % lay = controlColumn(obj, parent, Title=..., Row=..., Column=..., Rows=...)
            % Titled panel containing a scrollable fixed-row-height grid,
            % ready for a stack of addControl calls. Builds layout, not a
            % component, so nothing is registered. See gui.components.controlColumn.
            lay = gui.components.controlColumn(parent, varargin{:});
        end

        function h = addUpdateButton(obj, parent, varargin)
            % h = addUpdateButton(obj, parent, ...)
            % Create a gui.components.Parameter_Update that commits every editable
            % control in this GUI at once. The controls are found from the
            % registry after build returns, so this may be called before
            % them. Ctrl+Enter commits too; KeyBinding='none' drops that.
            h = obj.add('gui.components.Parameter_Update', parent, varargin{:});
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

        function tf = waitForSessionGate(obj, timeout)
            % tf = waitForSessionGate(obj, timeout)
            % Hold the session until the operator presses the gate added by
            % add('gui.components.SessionGate', ...), returning whether it opened. Call it from the
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

            gates = obj.componentsOfClass_('gui.components.SessionGate');
            if isempty(gates), return; end
            tf = gates{1}.wait(timeout);
        end

        function h = addPopOutButton(obj, parent, component, options)
            % h = addPopOutButton(obj, parent, component, Text=..., Tooltip=...)
            % Create a button that opens a display in a window of its own,
            % for something an operator only wants to see occasionally.
            %  component - any gui.PopOut component (gui.components.ParameterScatter,
            %              gui.components.History, gui.components.SessionPerformance, gui.components.NextTrial,
            %              gui.components.Parameter_Monitor, gui.components.PsychPlot, a plotted
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

        function names = componentNames(obj)
            % names = componentNames(obj)
            % Names components were registered under, in registration order,
            % '' where none was given. Hidden: the toolbar reaches these
            % through popOutComponents_, and this is for tests and debugging.
            names = obj.ComponentNames_;
        end

        function notePopOutStateChanged_(obj)
            % notePopOutStateChanged_(obj)
            % A display window opened or closed. gui.components.ComponentToolbar calls
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

        function bindComponentKey_(obj, chord, callback, owner, description)
            % Give a helper's component its default shortcut.
            %
            % 'none' is how a paradigm declines one. A component that was
            % skipped (an unresolved parameter, a missing analysis) gets no
            % binding, and a chord the paradigm has already used for
            % something else is reported rather than thrown: the shortcut is
            % a convenience, and losing it must not stop the GUI opening
            % (epsych.SelfTest check I6).
            if isempty(chord) || strcmpi(chord, 'none'), return; end
            if isempty(owner) || ~isvalid(owner), return; end
            if isempty(obj.Keys) || ~isvalid(obj.Keys), return; end

            try
                obj.Keys.bind(chord, callback, Description = description, Owner = owner);
            catch ME
                vprintf(2, '%s: no %s shortcut (%s)', class(obj), chord, ME.message)
            end
        end

        function [pos, opts, ok] = buildSpecPositionals_(obj, spec, parent, canvasH, opts)
            % Positional arguments named by spec.shape. An arg: token is
            % CONSUMED from opts so it is not also forwarded by name.
            ok  = true;
            tok = spec.shape;
            pos  = cell(1, numel(tok));
            have = true(1, numel(tok));
            for k = 1:numel(tok)
                t = char(tok(k));
                if startsWith(t, 'arg:')
                    name = t(5:end);
                    if isfield(opts, name)
                        pos{k} = opts.(name);
                        opts   = rmfield(opts, name);
                    else
                        [d, hasD] = spec.optionDefault(name);
                        pos{k}  = d;
                        have(k) = hasD;
                    end
                    continue
                end
                switch t
                    case 'parent', pos{k} = parent;
                    case 'figure', pos{k} = obj.h_figure;
                    case 'host',   pos{k} = obj;
                    case 'runtime',pos{k} = obj.RUNTIME;
                    case 'psych',  pos{k} = obj.Psych;
                    case 'keys',   pos{k} = obj.Keys;
                    case 'canvas', pos{k} = canvasH;
                    case 'psychOrRuntime'
                        s = obj.Psych;
                        if isempty(s) || ~isvalid(s), s = obj.RUNTIME; end
                        pos{k} = s;
                    otherwise
                        vprintf(2, '%s: %s declares an unknown positional "%s"; skipping', ...
                            class(obj), spec.label, t)
                        ok = false;
                        pos = {};
                        return
                end
            end
            % Unstated trailing optionals are DROPPED rather than passed as
            % [], so the component sees the nargin a hand-written call gives.
            last = find(have, 1, 'last');
            if isempty(last), last = 0; end
            pos = pos(1:last);
        end

        function opts = applySpecInjections_(obj, spec, opts)
            % Name-values this GUI supplies (KeySource, Runtime, Target),
            % only where the caller did not state them. addButton's
            % deliberate absence of Runtime= is expressed by its spec simply
            % not injecting one.
            fn = fieldnames(spec.inject);
            for k = 1:numel(fn)
                if isfield(opts, fn{k}), continue; end
                switch char(spec.inject.(fn{k}))
                    case 'runtime', opts.(fn{k}) = obj.RUNTIME;
                    case 'keys',    opts.(fn{k}) = obj.Keys;
                    case 'figure',  opts.(fn{k}) = obj.h_figure;
                    case 'host',    opts.(fn{k}) = obj;
                    case 'psych',   opts.(fn{k}) = obj.Psych;
                end
            end
        end

        function tf = specPreconditionsMet_(obj, spec, opts)
            % Everything the session must already have for this component to
            % mean anything. Each failure is a debug-level skip, never a
            % throw (epsych.SelfTest check I6).
            tf = false;
            for r = spec.requires
                switch char(r)
                    case 'psych'
                        if ~obj.hasPsych_(spec.label), return; end
                        if ~isempty(spec.psychTypes) && ~any(arrayfun( ...
                                @(t) isa(obj.Psych, char(t)), spec.psychTypes))
                            vprintf(2, '%s: %s needs a %s analysis; this session has %s', ...
                                class(obj), spec.label, ...
                                strjoin(cellstr(spec.psychTypes), '/'), class(obj.Psych))
                            return
                        end
                    case 'psychPlot'
                        if ~obj.hasPsych_(spec.label), return; end
                        if ~ismethod(obj.Psych, 'Plot')
                            vprintf(2, '%s: %s skipped; %s cannot plot itself', ...
                                class(obj), spec.label, class(obj.Psych))
                            return
                        end
                end
            end
            for o = spec.requiredOptions
                n = char(o);
                if ~isfield(opts, n) || isempty(opts.(n))
                    vprintf(2, ['%s: %s needs %s; skipping rather than opening ' ...
                        'a dialog mid-session'], class(obj), spec.label, n)
                    return
                end
            end
            tf = true;
        end

        function [opts, ok] = resolveSpecParameters_(obj, spec, opts)
            % Turn parameter NAMES into hw.Parameter handles. A miss drops
            % that entry, or kills the component when resolveRequired.
            ok = true;
            for nm = spec.resolve
                n = char(nm);
                if ~isfield(opts, n), continue; end
                raw = opts.(n);
                if isa(raw, 'hw.Parameter'), continue; end
                if ischar(raw) || (isstring(raw) && isscalar(raw))
                    p = obj.resolveParameter_(raw);
                    if isempty(p)
                        if spec.resolveRequired, ok = false; return; end
                        opts = rmfield(opts, n);
                    else
                        opts.(n) = p;
                    end
                    continue
                end

                % A list: resolved ELEMENT BY ELEMENT, because this runs
                % before the try/catch around construction and so must not
                % throw (epsych.SelfTest check I6). cellstr would throw on a
                % cell holding hw.Parameter handles, or a mix of handles and
                % names, or a number -- and a caller passing handles it
                % already holds is the normal case, not an error.
                if isstring(raw)
                    items = cellstr(raw);
                elseif iscell(raw)
                    items = raw;
                else
                    vprintf(2, ['%s: %s option "%s" must name parameters ' ...
                        '(got %s); skipping'], class(obj), spec.label, n, class(raw))
                    if spec.resolveRequired, ok = false; return; end
                    opts = rmfield(opts, n);
                    continue
                end
                res = hw.Parameter.empty(1,0);
                for i = 1:numel(items)
                    it = items{i};
                    if isa(it, 'hw.Parameter')
                        res = [res, it(:)']; %#ok<AGROW>
                    elseif ischar(it) || (isstring(it) && isscalar(it))
                        p = obj.resolveParameter_(it);
                        if ~isempty(p), res(end+1) = p; end %#ok<AGROW>
                    else
                        vprintf(2, '%s: %s ignored a %s in "%s"', ...
                            class(obj), spec.label, class(it), n)
                    end
                end
                if isempty(res) && spec.resolveRequired, ok = false; return; end
                opts.(n) = res;
            end
        end

        function bindSpecKey_(obj, spec, chord, h)
            % Default keyboard chord, if the spec ships one and the caller
            % did not drop it. bindComponentKey_ already honours 'none'.
            if isempty(spec.keyAction)
                if ~isempty(chord) && ~strcmp(chord, spec.keyBinding) && ~strcmpi(chord, 'none')
                    vprintf(2, '%s: %s has no keyboard action, so KeyBinding=%s is ignored', ...
                        class(obj), spec.label, chord)
                end
                return
            end
            if isempty(chord), return; end
            act = spec.keyAction;
            if ischar(act) || isstring(act)
                cb = @() feval(char(act), h);
            else
                cb = @() act(h, obj);
            end
            obj.bindComponentKey_(chord, cb, h, spec.keyDescription);
        end

        function tb = componentToolbar_(obj)
            % tb = componentToolbar_(obj)
            % This GUI's component toolbar, or [].
            %
            % Read from the registry rather than kept in a property of its
            % own: add registers it like anything else, and
            % one source of truth cannot go stale against the other.
            tb = [];
            c = obj.componentsOfClass_('gui.components.ComponentToolbar');
            if isempty(c), return; end
            if isvalid(c{1}), tb = c{1}; end
        end

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
            % isscalar first: register accepts anything, and a handle ARRAY
            % registered by a subclass would make isvalid non-scalar and
            % throw here -- from the base constructor, after build returned.
            match = cellfun(@(h) isscalar(h) && isa(h, cls) && isvalid(h), obj.Components_);
            c = obj.Components_(match);
        end

        function closeExistingInstance_(obj)
            % Only one instance per PreferenceTag: replace an existing
            % window. Detach UserData/CloseRequestFcn before deleting so
            % figure deletion cannot recurse into the old object.
            f = findall(groot, 'Type', 'figure', '-and', 'Tag', obj.PreferenceTag);
            for i = 1:numel(f)
                try
                    gui.BehaviorGUI.saveFigureLayout(obj.PreferenceTag, f(i));
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
            controls = gui.components.Parameter_Control.empty(1,0);
            updaters = {};
            for i = 1:numel(obj.Components_)
                c = obj.Components_{i};
                if ~isobject(c) || ~isvalid(c), continue; end
                if isa(c, 'gui.components.Parameter_Control') && ~c.autoCommit && ~c.Parameter.isTrigger
                    controls(end+1) = c;
                elseif isa(c, 'gui.components.Parameter_Update')
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
                labels(end+1) = gui.components.ComponentToolbar.entryLabel(class(c), obj.ComponentNames_{i});
            end

            % The psych object last: a plotted psychophysics.Staircase is a
            % display like any other, but it is createPsych's return value
            % rather than something build registered, so nothing above finds
            % it. Skipped when a subclass registered it as well.
            p = obj.Psych;
            if isempty(p) || ~isvalid(p) || ~isa(p, 'gui.PopOut'), return; end
            if any(cellfun(@(c) c == p, comps)), return; end
            comps{end+1}  = p;
            labels(end+1) = gui.components.ComponentToolbar.entryLabel(class(p));
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

            tb = obj.componentToolbar_();
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
            tb = obj.componentToolbar_();
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
                        if isa(c, 'gui.components.Parameter_Monitor') && isvalid(c)
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

    methods (Static, Hidden)

        function [opts, ok] = parseOptions_(args, cls, guiCls)
            % Name=Value pairs into a struct holding ONLY what was stated.
            %
            % An arguments block cannot do this: it would fill in defaults,
            % and "not stated" would stop being distinguishable from "stated
            % as the default" -- which is what lets a component fall back to
            % the operator's saved preference. A malformed call is a
            % debug-level skip, not a throw (epsych.SelfTest check I6).
            ok = true;
            opts = struct();
            if mod(numel(args), 2) ~= 0
                vprintf(2, '%s: add(%s, ...) needs Name=Value pairs; component skipped', ...
                    guiCls, cls)
                ok = false;
                return
            end
            for k = 1:2:numel(args)
                n = args{k};
                isName = ischar(n) || (isstring(n) && isscalar(n) && ~ismissing(n));
                if ~isName || ~isvarname(char(n))
                    vprintf(2, ['%s: add(%s, ...) got a non-name where an option ' ...
                        'name belongs; component skipped'], guiCls, cls)
                    ok = false;
                    return
                end
                opts.(char(n)) = args{k+1};   % last wins, as MATLAB does
            end
        end

        function [v, opts] = popOption_(opts, name, default)
            % Take one reserved option out of opts, matched case-insensitively
            % so 'variant' and 'Variant' both count, and never forwarded.
            v = default;
            fn = fieldnames(opts);
            ix = find(strcmpi(fn, name), 1, 'last');   % last wins
            if isempty(ix), return; end
            v = opts.(fn{ix});
            opts = rmfield(opts, fn(strcmpi(fn, name)));
        end

        function opts = canonicalizeOptions_(spec, opts)
            % Rename each stated option to the spelling the spec declares,
            % matched case-insensitively. An option the spec does not know is
            % left exactly as written and forwarded as such. Where a caller
            % stated both spellings, the variant is taken to be the later one
            % and wins, matching MATLAB's own last-wins rule.
            known = string(fieldnames(spec.fixedOptions)');
            known = [known, string(fieldnames(spec.inject)'), spec.hostOptions, ...
                spec.resolve, spec.requiredOptions];
            for t = spec.shape
                if startsWith(t, "arg:"), known(end+1) = extractAfter(t, 4); end %#ok<AGROW>
            end
            if ~isempty(spec.options)
                known = [known, string({spec.options.name})];
            end
            known = unique(known(strlength(known) > 0), 'stable');
            if isempty(known), return; end

            fn = fieldnames(opts);
            for k = 1:numel(fn)
                if any(known == fn{k}), continue; end   % already canonical
                ix = find(strcmpi(known, fn{k}));
                if numel(ix) ~= 1, continue; end        % unknown, or ambiguous
                canonical = char(known(ix));
                opts.(canonical) = opts.(fn{k});
                opts = rmfield(opts, fn{k});
            end
        end
    end

    methods (Static)

        function position = getSavedFigurePosition(prefTag, defaultPosition)
            % Retrieve the last-saved [x y w h] for this PreferenceTag,
            % fitted to the monitor it was last on.
            %
            % The fit is here rather than at each caller so that every
            % restored window is on-screen without a movegui(fig,'onscreen')
            % afterwards -- which is what used to reopen a window left on a
            % secondary monitor on the primary one (see
            % gui.fitPositionToMonitor).
            position = getpref(prefTag, 'FigurePosition', defaultPosition);
            if ~isnumeric(position) || numel(position) ~= 4 || any(~isfinite(position))
                position = defaultPosition;
            end
            position = gui.fitPositionToMonitor(double(reshape(position, 1, [])));
        end

        function saveFigurePosition(prefTag, position)
            % Persist figure [x y w h] under this PreferenceTag.
            if ~isnumeric(position) || numel(position) ~= 4 || any(~isfinite(position))
                return
            end
            setpref(prefTag, 'FigurePosition', double(reshape(position, 1, [])));
        end

        function saveFigureLayout(prefTag, fig)
            % Persist a figure's position AND maximized state.
            %
            % A maximized figure's Position reports the screen-filling
            % bounds, so it is deliberately NOT written: the position on
            % record stays the last normal one, which is what un-maximizing
            % the reopened window should restore. Fullscreen is remembered
            % as maximized, and a minimized window as its normal self --
            % nobody wants a GUI that opens minimized.
            state = 'normal';
            try
                state = char(fig.WindowState);
            catch
            end
            if any(strcmp(state, {'maximized', 'fullscreen'}))
                setpref(prefTag, 'FigureWindowState', 'maximized');
            else
                gui.BehaviorGUI.saveFigurePosition(prefTag, fig.Position);
                setpref(prefTag, 'FigureWindowState', 'normal');
            end
        end

        function state = getSavedFigureWindowState(prefTag)
            % The last-saved window state for this PreferenceTag: 'normal'
            % or 'maximized'. Anything unreadable is 'normal'.
            state = 'normal';
            try
                saved = getpref(prefTag, 'FigureWindowState', 'normal');
                if (ischar(saved) || isstring(saved)) && strcmp(saved, 'maximized')
                    state = 'maximized';
                end
            catch
            end
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
