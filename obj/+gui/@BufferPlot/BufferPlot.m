classdef BufferPlot < gui.PopOut
    % BufferPlot: per-trial display of hw.Parameter BUFFER contents.
    %
    %   obj = gui.BufferPlot(source, container)
    %   obj = gui.BufferPlot(source, container, Buffers=["Waveform~1"], SampleRate=24414)
    %
    %   Plots the contents of one or more 'Buffer' parameters, refreshed once
    %   per completed trial. The x axis is BUFFER SAMPLES by default, because
    %   that is the only thing a buffer is guaranteed to know about itself;
    %   naming a SampleRate (a number, or "auto" to take it from the owning
    %   hw.Module) turns it into seconds or milliseconds.
    %
    %   'Coefficient Buffer' parameters are deliberately NOT plottable here.
    %   They hold session-static data (calibration coefficients), so there is
    %   nothing per-trial about one and every redraw would show the same
    %   numbers: they are absent from BUFFER_TYPES, from auto-selection, from
    %   Select Buffers..., and from gui.BehaviorBuilder's dialog. Naming one
    %   explicitly still resolves, and says so at debug level.
    %
    %   Everything about how it looks -- traces, order, colour, width,
    %   palette, layout, how many past trials are drawn -- is settable
    %   BOTH from code and from the axes right-click menu, the two paths
    %   landing on the same setters, so nothing the operator can do is out of
    %   a script's reach.
    %
    %   WHERE THE DATA COMES FROM. ep_TimerFcn_RunTime already reads every
    %   readable parameter at trial completion -- buffers included, since
    %   all_parameters(Access='Read') excludes only write-only ones -- and
    %   stores the result in that trial's DATA record. This component
    %   therefore takes the buffer OUT OF THE TRIAL RECORD rather than
    %   reading the device a second time: a 131072-sample buffer measured 245x
    %   the rest of a protocol (see epsych.SessionSnapshot.capture), and on
    %   hw.TDT_RPcox a second read of it is another multi-megabyte COM
    %   transfer for numbers the runtime is holding already. A buffer the
    %   record does NOT carry -- an invisible one ('_~#%' prefix), which
    %   all_parameters filters out -- falls back to reading the parameter
    %   itself, once per trial.
    %
    %   That is also what makes the component work in three places for free:
    %   live (NewData from the runtime), under epsych.ReviewSession (which
    %   notifies with DATA(1:k), so the last record is the trial being
    %   reviewed and seeking backward redraws), and offline over a saved DATA
    %   struct array. Hardware is never read in ReviewMode: hw.Replay answers
    %   from a snapshot whose buffer CONTENTS were deliberately blanked.
    %
    %   LARGE BUFFERS are decimated to MaxPoints by a min/max ENVELOPE, not
    %   by striding: a stride hides exactly the brief transient a buffer is
    %   usually being watched for. The envelope of each trial is cached by
    %   trial index, so redrawing a history of past trials costs one pass per
    %   trial rather than one per redraw.
    %
    %   Properties (all settable at any time; each redraws immediately):
    %     XAxisUnits    - 'samples' (default), 'seconds', 'milliseconds'
    %     SampleRate    - Hz; 0 (default) means unknown, so units stay samples
    %     Layout        - 'overlay' (default) or 'stacked'
    %     NumTrialsShown- past trials drawn behind the newest one (default 1)
    %     HistoryAlpha  - how faint the oldest of those is (default 0.3)
    %     MaxPoints     - envelope target, Inf to draw every sample
    %     LineWidth, LineColors, Palette, ShowGrid, ShowLegend
    %     YLimMode, YLim, Paused, BoxID
    %
    %   Methods:
    %     setBuffers, bufferNames, availableBuffers, setTraceColor
    %     update, selectBuffers, exportToWorkspace
    %     hasSavedConfiguration, forgetConfiguration
    %
    %   Operator choices persist under a preference key scoped to the hosting
    %   figure (or an explicit PreferenceTag), with the rule gui.OnlinePlot
    %   uses: aesthetics are always restored, but a remembered SELECTION is
    %   restored only when the operator made it by hand -- a Buffers list
    %   passed to the constructor is what the paradigm's build() asked for,
    %   and a saved list from another protocol must not silently replace it.
    %   A SampleRate stated by the constructor likewise always wins over a
    %   saved one: it is a fact about the device, not a preference.
    %
    %   Examples:
    %     % In a behavior GUI's build():
    %     obj.addBufferPlot(g, Buffers="Waveform~1", SampleRate="auto");
    %
    %     % Offline, over a saved session:
    %     S = load('subject_2026-08-25.mat');
    %     gui.BufferPlot([S.data_0001 S.data_0002], uifigure);
    %
    % Documentation: documentation/gui/gui_BufferPlot.md
    % See also gui.OnlinePlot, gui.ParameterScatter, gui.BehaviorGUI, gui.PopOut

    properties (SetObservable)
        XAxisUnits (1,:) char {mustBeMember(XAxisUnits,{'samples','seconds','milliseconds'})} = 'samples'
        SampleRate (1,1) double {mustBeNonnegative,mustBeFinite} = 0 % Hz; 0 = unknown, plot against samples
        Layout     (1,:) char {mustBeMember(Layout,{'overlay','stacked'})} = 'overlay'
        NumTrialsShown (1,1) double {mustBeInteger,mustBePositive} = 1 % newest trial plus this many behind it
        HistoryAlpha (1,1) double {mustBePositive,mustBeLessThanOrEqual(HistoryAlpha,1)} = 0.3
        MaxPoints  (1,1) double {mustBePositive} = 10000 % envelope target; Inf draws every sample
        LineWidth  (1,1) double {mustBePositive,mustBeFinite} = 1
        LineColors (:,3) double {mustBeNonnegative,mustBeLessThanOrEqual(LineColors,1)} % per-trace RGB; short rows fill from Palette
        Palette    (1,:) char = 'Okabe-Ito'
        ShowGrid   (1,1) logical = true
        ShowLegend (1,1) logical = true
        YLimMode   (1,:) char {mustBeMember(YLimMode,{'auto','manual'})} = 'auto'
        YLim       (1,2) double = [0 1]
        Paused     (1,1) logical = false % stop capturing and redrawing; the trial record is unaffected
        BoxID      (1,:) double = []     % restrict NewData updates to these boxes; empty accepts all
    end

    properties (SetAccess = private)
        AxesH                        % Axes hosting the traces
        ContainerH                   % Hosting container supplied at construction
        LegendH = []                 % Legend, in overlay mode
    end

    properties (Access = private)
        % One entry per plotted buffer. Spelled out rather than taken from
        % emptyTrace_ because a property default is evaluated while the class
        % is still loading, where a static of that same class is not callable.
        Traces_ = struct('Name',{},'ValidName',{},'Param',{},'Fs',{}, ...
            'FromData',{},'Ring',{},'Cache',{})
        DATA_ = []                   % Cached per-trial data struct array
        Source_ = []                 % Construction source, reused to build a pop-out
        Runtime_ = []                % epsych.Runtime, when there is one
        ContextMenuH_ = []           % Right-click menu
        PreferenceTag_ char = ''     % Optional explicit preference key
        Suspend_ (1,1) logical = false % True while building or restoring: no redraw, no save
        SelectionByOperator_ (1,1) logical = false % Selection was made by hand, so it outranks the constructor's
        CacheStamp_ (1,1) double = NaN % MaxPoints the envelope caches were built with
        RedrawListener_ = event.listener.empty % PostSet on the display properties
        hl_NewData = event.listener.empty      % Trial completion
        Counter_ (1,1) double = 0    % Fallback trial key for hardware-read buffers
        ColorOverride_ = [] % Hand-picked colours by buffer name; a containers.Map built per instance in the constructor, never as a property default (one handle would be shared by every plot)
        PaletteStamp_ (1,:) char = ''  % Palette the current LineColors were derived from
    end

    properties (Constant, Access = private)
        PREF_GROUP = 'epsych2_gui_BufferPlot'
        BUFFER_TYPES = {'Buffer'}    % Plottable parameter types; 'Coefficient Buffer' is session-static and excluded
        MAX_AUTO = 4                 % Auto-selection stops here rather than filling the axes
        PALETTES = {'Okabe-Ito','Lines','Parula','Turbo','Grayscale'}
        LINE_WIDTHS = [0.5 1 1.5 2 3]
        TRIALS_SHOWN = [1 2 3 5 10]
        POINT_CAPS = [2000 5000 10000 25000 50000 Inf]
        UNSET_MODULE_FS = 1          % hw.Module.Fs cannot represent "unset"; 1 is what that means

        % Okabe-Ito, the colorblind-safe qualitative set gui.OnlinePlot uses.
        PALETTE = [ 0.000 0.447 0.698
                    0.902 0.624 0.000
                    0.000 0.620 0.451
                    0.800 0.475 0.655
                    0.337 0.706 0.914
                    0.835 0.369 0.000
                    0.749 0.706 0.106
                    0.350 0.350 0.350 ];
    end

    methods
        function obj = BufferPlot(source, container, options)
            % obj = gui.BufferPlot(source, container, ...)
            % Build the plot, resolve its buffers, and attach the trial listener.
            %
            % Parameters:
            %   source - epsych.Runtime, a psychophysics object, or a DATA
            %       struct array for offline use. Empty builds an empty plot.
            %   container - figure, panel, tab, or layout host. Empty makes a
            %       uifigure.
            %   options.Buffers - buffer parameter name(s), or hw.Parameter
            %       handles. Omitted, every 'Buffer' parameter the source
            %       declares is taken (up to MAX_AUTO of them), which is what
            %       keeps this usable from a generated build() with nothing
            %       configured.
            %   options.SampleRate - Hz, or "auto"/"module" to read it from
            %       the owning hw.Module. Stating one also switches the
            %       default units to seconds -- naming a rate is what asking
            %       for a time axis looks like.
            %   options.PreferenceTag - key for saved settings; defaults to
            %       the hosting figure's Tag (or Name).
            %   options.BoxID - restrict NewData updates to these boxes.
            %
            % The remaining options are first-session defaults for the
            % aesthetics of the same name: a setting restored from a previous
            % session wins over them. They carry NO defaults here, so "not
            % stated" stays distinguishable from "stated as the default".
            %
            % Returns:
            %   obj - gui.BufferPlot object.
            arguments
                source = []
                container = []
                options.Buffers = {}
                options.SampleRate = []
                options.PreferenceTag {mustBeTextScalar} = ''
                options.BoxID (1,:) double = []
                options.XAxisUnits {mustBeTextScalar}
                options.Layout {mustBeTextScalar}
                options.NumTrialsShown (1,1) double
                options.MaxPoints (1,1) double
                options.LineWidth (1,1) double
                options.Palette {mustBeTextScalar}
                options.ShowGrid (1,1) logical
                options.ShowLegend (1,1) logical
                options.HistoryAlpha (1,1) double
            end

            if isempty(container)
                container = uifigure('Name','Buffer Plot');
            end
            obj.ContainerH = container;
            obj.ColorOverride_ = containers.Map('KeyType','char','ValueType','any');
            obj.PreferenceTag_ = char(options.PreferenceTag);
            obj.BoxID = options.BoxID;
            obj.PopOutLabel = 'Buffer Plot';
            obj.PopOutSize = [820 520];

            obj.Suspend_ = true;
            obj.build_(container);
            obj.attachSource_(source);

            % Aesthetics the caller asked for, before preferences: a saved
            % setting is the operator's later answer to the same question.
            for f = {'XAxisUnits','Layout','NumTrialsShown','MaxPoints', ...
                     'LineWidth','Palette','ShowGrid','ShowLegend','HistoryAlpha'}
                if isfield(options,f{1}), obj.(f{1}) = options.(f{1}); end
            end

            named = obj.namesFromSelection_(options.Buffers);
            if isempty(named)
                named = obj.autoSelect_();
            end
            obj.setBuffers(named);

            % SampleRate LAST of the constructor's inputs and outside the
            % preference override below: a rate the caller states is a fact
            % about the device, not a preference the operator may overrule.
            hasRate = obj.applySampleRateOption_(options.SampleRate);
            if hasRate && obj.SampleRate > 0 && ~isfield(options,'XAxisUnits')
                obj.XAxisUnits = 'seconds';
            end

            obj.loadPreferences_(~isempty(named), hasRate);
            obj.buildContextMenu_;

            obj.Suspend_ = false;
            obj.RedrawListener_ = addlistener(obj, ...
                {'XAxisUnits','SampleRate','Layout','NumTrialsShown','HistoryAlpha', ...
                 'MaxPoints','LineWidth','LineColors','Palette','ShowGrid', ...
                 'ShowLegend','YLimMode','YLim','Paused'}, ...
                'PostSet', @(~,~) obj.onDisplayPropertyChanged_);
            obj.update;
        end

        function delete(obj)
            % delete(obj)
            % Release the trial listener, the property listener, and the menu.
            delete(obj.RedrawListener_(isvalid(obj.RedrawListener_)));
            obj.RedrawListener_ = event.listener.empty;
            delete(obj.hl_NewData(isvalid(obj.hl_NewData)));
            obj.hl_NewData = event.listener.empty;
            if ~isempty(obj.ContextMenuH_) && isvalid(obj.ContextMenuH_)
                delete(obj.ContextMenuH_);
            end
        end

        function update(obj)
            % update(obj)
            % Capture the newest trial and redraw. Called for every NewData
            % event, and safe to call by hand at any time.
            if obj.Suspend_ || obj.Paused, return; end
            obj.captureTrial_;
            obj.redraw_;
        end

        function setBuffers(obj, names)
            % setBuffers(obj, names)
            % Choose which buffers are plotted, in the order given.
            %
            % names may be parameter names (char/string/cellstr), hw.Parameter
            % handles, or DATA field names when the source is a saved session.
            % A name that resolves to nothing is skipped with a debug-level
            % message, the tolerance every add* helper in gui.BehaviorGUI has,
            % so an edited protocol degrades instead of throwing.
            %
            % Per-trace colours are matched by NAME, so a colour the operator
            % picked follows its buffer through a reselection.
            names = obj.namesFromSelection_(names);

            T = gui.BufferPlot.emptyTrace_;
            for k = 1:numel(names)
                t = obj.resolveTrace_(names{k});
                if isempty(t)
                    vprintf(2,'gui.BufferPlot: "%s" is not a buffer this session offers', names{k})
                    continue
                end
                T(end+1) = t;
            end
            obj.Traces_ = T;
            obj.applyColors_;
            obj.rebuildTraceColorMenu_;
            if obj.Suspend_, return; end
            obj.update;
        end

        function n = bufferNames(obj)
            % n = bufferNames(obj)
            % Cellstr of the buffers currently plotted, in plot order.
            n = {};
            if ~isempty(obj.Traces_), n = {obj.Traces_.Name}; end
        end

        function n = availableBuffers(obj)
            % n = availableBuffers(obj)
            % Every buffer this source can offer: the 'Buffer' parameters the
            % runtime knows (invisible ones included -- a paradigm may well
            % want to plot one), or, offline, the DATA fields holding a
            % numeric vector. Coefficient buffers are not among them; see the
            % class comment.
            n = {};
            try
                if ~isempty(obj.Runtime_)
                    P = obj.Runtime_.all_parameters(includeInvisible=true, ...
                        includeTriggers=false, Access='Read');
                    if ~isempty(P)
                        P = P(ismember({P.Type}, obj.BUFFER_TYPES));
                        n = {P.Name};
                    end
                end
                D = obj.currentData_;
                if ~isempty(D)
                    % A record carries a coefficient buffer like any other
                    % readable parameter, so the DATA sweep has to be told
                    % which fields to leave alone. Offline, with no runtime
                    % to ask, one is indistinguishable from a plain buffer
                    % and is offered.
                    skip = obj.excludedNames_;
                    f = fieldnames(D);
                    for k = 1:numel(f)
                        if ismember(f{k}, skip), continue; end
                        v = D(end).(f{k});
                        if (isnumeric(v) || islogical(v)) && numel(v) > 1
                            n{end+1} = f{k};
                        end
                    end
                end
            catch ME
                vprintf(2,'gui.BufferPlot: buffer list unavailable: %s', ME.message)
            end
            n = unique([n, obj.bufferNames], 'stable');
        end

        function setTraceColor(obj, target, rgb)
            % setTraceColor(obj, target, rgb)
            % Colour one trace, by plot index or by buffer name. The colour is
            % remembered against the NAME, so it survives a reorder.
            arguments
                obj
                target
                rgb (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(rgb,1)}
            end
            k = obj.traceIndex_(target);
            if isempty(k), return; end
            names = obj.bufferNames;
            obj.ColorOverride_(names{k}) = rgb;
            obj.applyColors_;
        end

        function selectBuffers(obj)
            % selectBuffers(obj)
            % Ask the operator which buffers to plot, then apply the answer.
            %
            % Choosing here marks the selection as the OPERATOR'S, which is
            % what makes it outrank the constructor's list the next time this
            % plot is built. Cancelling changes nothing.
            choices = obj.availableBuffers;
            if isempty(choices)
                vprintf(0,1,'gui.BufferPlot: no buffer parameters are available to plot')
                return
            end
            current = obj.bufferNames;
            [~,pre] = ismember(current, choices);
            pre = pre(pre > 0);
            if isempty(pre), pre = 1; end % listdlg refuses an empty InitialValue

            % listdlg is modal, so a pinned window would sit over it.
            fig = ancestor(obj.AxesH,'figure');
            wasTop = gui.PopOut.isAlwaysOnTop(fig);
            gui.PopOut.setAlwaysOnTop(fig,false);
            restore = onCleanup(@() gui.PopOut.setAlwaysOnTop(fig,wasTop));

            [sel,ok] = listdlg('PromptString','Select buffers to plot', ...
                'SelectionMode','multiple', ...
                'ListString',choices, ...
                'InitialValue',pre, ...
                'ListSize',[300 320], ...
                'Name','Buffer Plot');
            if ok == 0, return; end

            % Selection answers WHICH, not WHERE: keep the order already on
            % the axes and put anything new below it.
            picked = choices(sel);
            kept = current(ismember(current,picked));
            obj.setBuffers([kept, picked(~ismember(picked,current))]);
            obj.SelectionByOperator_ = true;
            obj.savePreferences_;
        end

        function s = exportToWorkspace(obj, varName)
            % s = exportToWorkspace(obj, varName)
            % Copy the newest trial's buffers to a base-workspace struct, one
            % field per buffer, at FULL resolution -- what is on the axes is
            % an envelope, and nobody wants to measure one of those.
            arguments
                obj
                varName {mustBeTextScalar} = 'epsych_buffers'
            end
            s = struct();
            for k = 1:numel(obj.Traces_)
                v = obj.rawValue_(k, obj.newestKey_);
                s.(matlab.lang.makeValidName(obj.Traces_(k).Name)) = v;
            end
            if ~isempty(varName)
                assignin('base', char(varName), s);
                vprintf(1,'gui.BufferPlot: %d buffer(s) copied to base workspace as "%s"', ...
                    numel(obj.Traces_), char(varName))
            end
        end

        function tf = hasSavedConfiguration(obj)
            % tf = hasSavedConfiguration(obj)
            % True when settings are already stored under this plot's key. A
            % caller applying defaults uses it to avoid overwriting what the
            % operator arranged last session.
            tf = false;
            try
                tf = ispref(obj.PREF_GROUP, obj.preferenceName_);
            catch
            end
        end

        function forgetConfiguration(obj)
            % forgetConfiguration(obj)
            % Discard the saved settings for this plot's key.
            try
                if ispref(obj.PREF_GROUP, obj.preferenceName_)
                    rmpref(obj.PREF_GROUP, obj.preferenceName_);
                end
            catch ME
                vprintf(2,'gui.BufferPlot: failed to clear preferences: %s', ME.message)
            end
        end
    end

    methods (Access = protected)
        function h = createPopOut_(obj, container)
            % h = createPopOut_(obj, container)
            % A second buffer plot over the same source, in its own window.
            %
            % Fully independent: its own selection, aesthetics and preference
            % key, so nothing done in it reaches the plot it came from. It
            % opens showing what the host shows unless it has been opened
            % before, in which case its own saved arrangement wins -- or
            % reopening the window would undo what was arranged in it.
            tag = obj.popOutPreferenceTag_();
            hasSaved = ispref(obj.PREF_GROUP, tag);

            h = gui.BufferPlot(obj.Source_, container, ...
                Buffers = obj.bufferNames, ...
                BoxID = obj.BoxID, ...
                PreferenceTag = tag);
            if isempty(h) || ~isvalid(h), h = []; return; end
            if hasSaved, return; end

            for f = {'XAxisUnits','SampleRate','Layout','NumTrialsShown', ...
                     'HistoryAlpha','MaxPoints','LineWidth','Palette', ...
                     'ShowGrid','ShowLegend','YLimMode','YLim'}
                h.(f{1}) = obj.(f{1});
            end
            % The colour OVERRIDES, not the derived matrix: copying only
            % LineColors would leave the pop-out's own palette free to
            % overwrite a colour the operator picked here.
            ks = obj.ColorOverride_.keys;
            for i = 1:numel(ks)
                h.ColorOverride_(ks{i}) = obj.ColorOverride_(ks{i});
            end
            h.applyColors_;
            h.savePreferences_;
            h.refreshMenuChecks_;
            h.update;
        end

        function c = popOutHostContainer_(obj)
            % Container this plot was built into, for gui.PopOut preference
            % scoping: the pop-out is keyed by the GUI that hosts the original.
            c = obj.ContainerH;
        end
    end

    methods (Access = private)
        function build_(obj, container)
            % Axes filling the container. uiaxes, not axes: every behavior GUI
            % figure is a uifigure and this component draws nothing a uiaxes
            % cannot (unlike gui.OnlinePlot, which needs a duration ruler).
            try
                g = uigridlayout(container,[1 1]);
                g.Padding = [2 2 2 2];
                obj.AxesH = uiaxes(g);
            catch
                % Legacy figure or panel hosting.
                obj.AxesH = axes('Parent',container);
            end
            box(obj.AxesH,'on');
            obj.AxesH.NextPlot = 'add';
        end

        function attachSource_(obj, source)
            % Resolve the data source and attach the NewData listener.
            obj.Source_ = source; % kept so a pop-out can attach to the same source
            if isempty(source)
                return
            elseif isstruct(source)
                obj.DATA_ = source; % offline data; no listener
            elseif isa(source,'epsych.Runtime') || (isobject(source) && isprop(source,'EVENTS'))
                obj.Runtime_ = source;
                obj.hl_NewData = listener(source.EVENTS,'NewData',@obj.onNewData);
                try
                    obj.DATA_ = source.TRIALS(1).DATA;
                catch
                    % No trial data yet; the first NewData event brings some.
                end
            elseif epsych.EventHub.valid_psych_obj(source)
                obj.Runtime_ = source.RUNTIME;
                obj.hl_NewData = listener(source.Events,'NewData',@obj.onNewData);
                obj.DATA_ = source.DATA;
            else
                error('gui:BufferPlot:InvalidSource', ...
                    'source must be an epsych.Runtime, a psychophysics object, or a DATA struct array');
            end
        end

        function onNewData(obj, ~, event)
            % NewData listener: cache the trial data and refresh.
            try
                if ~isempty(obj.BoxID) && ~isempty(event.BoxID) ...
                        && ~ismember(event.BoxID, obj.BoxID)
                    return
                end
            catch
                % Event without box information; accept it.
            end
            obj.DATA_ = event.Data.DATA;
            obj.update;
        end

        function D = currentData_(obj)
            % Cached DATA with the preallocated-but-empty first trial guard
            % gui.ParameterScatter uses: TRIALS(i).DATA is grown by
            % assignment, so entry 1 exists before any trial completes.
            D = obj.DATA_;
            if ~isempty(D) && isfield(D,'TrialID') && isempty(D(1).TrialID)
                D = D([]);
            end
        end

        function key = newestKey_(obj)
            % Identity of the newest trial, used to key the envelope caches.
            % The runtime's own TrialIndex when there is one; otherwise a
            % counter, which is all a hardware-read buffer can be keyed by.
            key = obj.Counter_;
            D = obj.currentData_;
            if isempty(D), return; end
            if isfield(D,'TrialIndex') && ~isempty(D(end).TrialIndex)
                key = double(D(end).TrialIndex);
            else
                key = numel(D);
            end
        end

        function captureTrial_(obj)
            % Take this trial's value for every trace.
            %
            % A buffer the trial RECORD carries needs nothing done: seriesFor_
            % reads it straight back out of DATA, which is what lets a review
            % seek backward and a MaxPoints change re-decimate. Only a buffer
            % the record does not carry -- an invisible parameter, which
            % all_parameters filters out of the per-trial read -- is read from
            % the device here and kept.
            obj.Counter_ = obj.Counter_ + 1;
            D = obj.currentData_;
            key = obj.newestKey_;

            for k = 1:numel(obj.Traces_)
                inRecord = false;
                if ~isempty(D)
                    inRecord = ~isempty(gui.BufferPlot.recordValue_(D(end), obj.Traces_(k).ValidName));
                end
                obj.Traces_(k).FromData = inRecord;
                if inRecord, continue; end

                v = obj.readParameter_(k);
                if isempty(v), continue; end
                r = obj.Traces_(k).Ring;
                r{end+1} = struct('Key',key,'Raw',v);
                if numel(r) > obj.NumTrialsShown
                    r = r(end-obj.NumTrialsShown+1:end);
                end
                obj.Traces_(k).Ring = r;
            end
        end

        function v = readParameter_(obj, k)
            % Read one buffer off its device. The fallback path only -- see
            % captureTrial_ -- and never in a review, where hw.Replay answers
            % from a snapshot whose buffer contents were deliberately blanked.
            v = [];
            T = obj.Traces_(k);
            if isempty(T.Param) || ~isvalid(T.Param{1}), return; end
            if ~isempty(obj.Runtime_) && isprop(obj.Runtime_,'ReviewMode') && obj.Runtime_.ReviewMode
                return
            end
            p = T.Param{1};
            if strcmp(p.Access,'Write'), return; end
            try
                v = p.Value;
            catch ME
                vprintf(2,'gui.BufferPlot: "%s" could not be read: %s', T.Name, ME.message)
                return
            end
            if ~(isnumeric(v) || islogical(v)) || numel(v) < 2
                v = [];
                return
            end
            v = double(v(:));
        end

        function v = rawValue_(obj, k, key)
            % Full-resolution values for trace k at the trial keyed by `key`.
            v = [];
            T = obj.Traces_(k);
            if T.FromData
                D = obj.currentData_;
                if isempty(D), return; end
                j = numel(D);
                if isfield(D,'TrialIndex')
                    idx = find(arrayfun(@(r) isequal(double(r.TrialIndex),key), D), 1, 'last');
                    if ~isempty(idx), j = idx; end
                end
                v = gui.BufferPlot.recordValue_(D(j), T.ValidName);
                return
            end
            for j = numel(T.Ring):-1:1
                if T.Ring{j}.Key == key, v = T.Ring{j}.Raw; return; end
            end
        end

        function S = seriesFor_(obj, k)
            % Envelopes for trace k, oldest first, newest last. At most
            % NumTrialsShown of them.
            S = struct('XI',{},'Y',{},'Key',{});
            T = obj.Traces_(k);
            if T.FromData
                D = obj.currentData_;
                if isempty(D), return; end
                first = max(1, numel(D) - obj.NumTrialsShown + 1);
                for j = first:numel(D)
                    v = gui.BufferPlot.recordValue_(D(j), T.ValidName);
                    if isempty(v), continue; end
                    key = j;
                    if isfield(D,'TrialIndex') && ~isempty(D(j).TrialIndex)
                        key = double(D(j).TrialIndex);
                    end
                    [xi,y] = obj.cachedEnvelope_(k, key, v);
                    S(end+1) = struct('XI',xi,'Y',y,'Key',key);
                end
            else
                r = T.Ring;
                for j = max(1,numel(r)-obj.NumTrialsShown+1):numel(r)
                    [xi,y] = obj.cachedEnvelope_(k, r{j}.Key, r{j}.Raw);
                    S(end+1) = struct('XI',xi,'Y',y,'Key',r{j}.Key);
                end
            end
        end

        function [xi,y] = cachedEnvelope_(obj, k, key, v)
            % Envelope for one trial's buffer, computed once and kept.
            % Decimating a 131072-sample buffer is cheap next to reading it,
            % but not cheap enough to repeat for every trace on every redraw
            % once a history of past trials is being drawn.
            C = obj.Traces_(k).Cache;
            if ~isempty(C)
                hit = find([C.Key] == key, 1);
                if ~isempty(hit)
                    xi = C(hit).XI; y = C(hit).Y;
                    return
                end
            end
            [xi,y] = gui.BufferPlot.envelope_(v, obj.MaxPoints);
            C(end+1) = struct('Key',key,'XI',xi,'Y',y);
            if numel(C) > 2*obj.NumTrialsShown
                C = C(end-2*obj.NumTrialsShown+1:end);
            end
            obj.Traces_(k).Cache = C;
        end

        function clearCaches_(obj)
            % Drop every envelope: MaxPoints changed, so they are all stale.
            for k = 1:numel(obj.Traces_)
                obj.Traces_(k).Cache = struct('Key',{},'XI',{},'Y',{});
            end
        end

        function fs = effectiveFs_(obj, k)
            % Sample rate for trace k: the one set on the plot, else whatever
            % the owning hw.Module reported when the interface connected.
            fs = obj.SampleRate;
            if fs > 0, return; end
            fs = 0;
            if k <= numel(obj.Traces_) && obj.Traces_(k).Fs > obj.UNSET_MODULE_FS
                fs = obj.Traces_(k).Fs;
            end
        end

        function x = xValues_(obj, xi, k)
            % Sample indices converted to the current x units. Asking for time
            % with no sample rate anywhere falls back to samples rather than
            % inventing a rate.
            fs = obj.effectiveFs_(k);
            if strcmp(obj.XAxisUnits,'samples') || fs <= 0
                x = xi;
                return
            end
            x = (xi - 1) / fs;
            if strcmp(obj.XAxisUnits,'milliseconds'), x = x * 1000; end
        end

        function lbl = xLabel_(obj)
            fs = 0;
            for k = 1:numel(obj.Traces_)
                fs = max(fs, obj.effectiveFs_(k));
            end
            if strcmp(obj.XAxisUnits,'samples') || fs <= 0
                lbl = 'Samples';
            elseif strcmp(obj.XAxisUnits,'milliseconds')
                lbl = 'Time (ms)';
            else
                lbl = 'Time (s)';
            end
        end
    end

    methods (Access = private)
        function redraw_(obj)
            % Draw every trace, oldest trial first so the newest sits on top.
            if obj.Suspend_ || isempty(obj.AxesH) || ~isvalid(obj.AxesH), return; end
            ax = obj.AxesH;
            if ~isempty(obj.LegendH) && isvalid(obj.LegendH), delete(obj.LegendH); end
            obj.LegendH = [];
            cla(ax);

            n = numel(obj.Traces_);
            if n == 0
                text(ax, 0.5, 0.5, 'No buffers selected', 'Units','normalized', ...
                    'HorizontalAlignment','center', 'Color',[0.5 0.5 0.5]);
                title(ax,''); xlabel(ax,''); ylabel(ax,'');
                return
            end

            S = cell(1,n);
            for k = 1:n, S{k} = obj.seriesFor_(k); end

            offsets = obj.stackOffsets_(S);
            colors = obj.LineColors;
            for k = size(colors,1)+1:n
                colors(k,:) = obj.paletteColor_(k); % a raw LineColors assignment may be short
            end
            bg = [1 1 1];
            if isnumeric(ax.Color) && numel(ax.Color) == 3, bg = ax.Color; end

            lh = gobjects(1,n);
            for k = 1:n
                m = numel(S{k});
                for j = 1:m
                    a = 1;
                    if j < m
                        % Alpha ramps from HistoryAlpha (oldest) up to just
                        % under the newest trace, which stays fully opaque.
                        a = obj.HistoryAlpha + (0.9 - obj.HistoryAlpha) * (j-1) / max(1,m-1);
                    end
                    % Blended toward the axes background rather than drawn
                    % with an RGBA Color: alpha on a Line is not something
                    % every supported release renders the same way, and a
                    % blend reads identically on any of them.
                    col = a * colors(k,:) + (1-a) * bg;
                    h = line(ax, obj.xValues_(S{k}(j).XI,k), S{k}(j).Y + offsets(k), ...
                        'Color', col, 'LineWidth', obj.LineWidth);
                    if j == m, lh(k) = h; end
                end
            end

            if obj.ShowGrid, grid(ax,'on'); else, grid(ax,'off'); end
            xlabel(ax, obj.xLabel_);

            if strcmp(obj.Layout,'stacked')
                [ticks,order] = sort(offsets);
                ax.YTick = ticks;
                ax.YTickLabel = obj.shortNames_(order);
                ylabel(ax,'');
            else
                ax.YTickMode = 'auto';
                ax.YTickLabelMode = 'auto';
                ylabel(ax,'Buffer value');
                drawn = find(isgraphics(lh));
                if obj.ShowLegend && ~isempty(drawn)
                    obj.LegendH = legend(ax, lh(drawn), obj.shortNames_(drawn), ...
                        'Location','best','Interpreter','none');
                end
            end

            if strcmp(obj.YLimMode,'manual') && obj.YLim(2) > obj.YLim(1)
                ax.YLim = obj.YLim;
            else
                ax.YLimMode = 'auto';
            end

            title(ax, obj.titleText_(S), 'Interpreter','none');
        end

        function t = titleText_(obj, S)
            % "Trial 42", plus what is standing in the way of it changing.
            key = [];
            for k = 1:numel(S)
                if ~isempty(S{k}), key = S{k}(end).Key; end
            end
            if isempty(key)
                t = 'Waiting for the first trial';
            else
                t = sprintf('Trial %d', key);
            end
            if obj.Paused, t = [t '  (paused)']; end
        end

        function offsets = stackOffsets_(obj, S)
            % Vertical offsets for 'stacked': one common spacing, taken from
            % the widest newest trace, so traces keep their relative scale.
            n = numel(S);
            offsets = zeros(1,n);
            if strcmp(obj.Layout,'overlay'), return; end
            spacing = 0;
            for k = 1:n
                if isempty(S{k}), continue; end
                y = S{k}(end).Y;
                y = y(isfinite(y));
                if isempty(y), continue; end
                spacing = max(spacing, max(y) - min(y));
            end
            if spacing <= 0, spacing = 1; end
            spacing = spacing * 1.15;
            offsets = -(0:n-1) * spacing; % first trace on top, as listed
        end

        function names = shortNames_(obj, idx)
            names = obj.bufferNames;
            names = names(idx);
        end

        function onDisplayPropertyChanged_(obj)
            % One PostSet handler for every display property: redraw, refresh
            % the menu ticks, and drop the envelope caches if the decimation
            % target moved. Programmatic changes do NOT persist -- only the
            % menu saves, which is what keeps a paradigm's build() from
            % overwriting the operator's arrangement.
            if obj.Suspend_, return; end
            if ~isequaln(obj.CacheStamp_, obj.MaxPoints)
                obj.clearCaches_;
                obj.CacheStamp_ = obj.MaxPoints;
            end
            if ~strcmp(obj.PaletteStamp_, obj.Palette)
                obj.applyColors_; % re-enters here once, with the stamp settled
                return
            end
            obj.redraw_;
            obj.refreshMenuChecks_;
        end

        % -----------------------------------------------------------------
        % Buffer resolution
        % -----------------------------------------------------------------
        function names = namesFromSelection_(~, sel)
            % Normalize whatever a caller passed -- names, hw.Parameter
            % handles, string array -- to a row cellstr of names.
            names = {};
            if isempty(sel), return; end
            if isa(sel,'hw.Parameter')
                names = {sel.Name};
                return
            end
            names = cellstr(sel);
            names = names(:)';
        end

        function t = resolveTrace_(obj, name)
            % One trace for `name`: the hw.Parameter behind it when the
            % session has one (for the sample rate and the fallback read),
            % and the DATA field name it is recorded under either way.
            t = gui.BufferPlot.emptyTrace_;
            name = char(name);
            p = {};
            fs = 0;
            if ~isempty(obj.Runtime_)
                P = obj.Runtime_.find_parameter(name, ...
                    includeInvisible=true, silenceParameterNotFound=true);
                if ~isempty(P)
                    p = {P(1)};
                    if ~ismember(P(1).Type, obj.BUFFER_TYPES)
                        % Named anyway, since an array parameter of another
                        % type still plots; a 'Coefficient Buffer' named by
                        % hand is the one case worth saying out loud.
                        vprintf(2,'gui.BufferPlot: "%s" is a %s parameter, not a buffer', ...
                            name, P(1).Type)
                    end
                    try
                        fs = P(1).Module.Fs;
                    catch
                        % A parameter with no module keeps fs = 0.
                    end
                end
            end
            if isempty(p)
                % No parameter of that name: only a DATA field can back it,
                % which is the offline case and a renamed protocol.
                D = obj.currentData_;
                if isempty(D) || ~isfield(D, matlab.lang.makeValidName(name))
                    t = gui.BufferPlot.emptyTrace_;
                    return
                end
            end
            t(1).Name = name;
            t(1).ValidName = matlab.lang.makeValidName(name);
            t(1).Param = p;
            t(1).Fs = fs;
            t(1).FromData = true;
            t(1).Ring = {};
            t(1).Cache = struct('Key',{},'XI',{},'Y',{});
        end

        function names = excludedNames_(obj)
            % DATA field names that are not plottable buffers -- today, the
            % session's 'Coefficient Buffer' parameters.
            names = {};
            if isempty(obj.Runtime_), return; end
            try
                P = obj.Runtime_.all_parameters(includeInvisible=true, ...
                    includeTriggers=false, Access='Read');
                if ~isempty(P)
                    P = P(~ismember({P.Type}, obj.BUFFER_TYPES));
                    names = {P.validName};
                end
            catch ME
                vprintf(2,'gui.BufferPlot: parameter types unavailable: %s', ME.message)
            end
        end

        function names = autoSelect_(obj)
            % Every 'Buffer' parameter the session declares, capped so an
            % unconfigured plot cannot fill itself with a dozen traces.
            names = {};
            try
                if ~isempty(obj.Runtime_)
                    P = obj.Runtime_.all_parameters(includeInvisible=false, ...
                        includeTriggers=false, Access='Read');
                    if ~isempty(P)
                        names = {P(ismember({P.Type}, obj.BUFFER_TYPES)).Name};
                    end
                elseif ~isempty(obj.currentData_)
                    names = obj.availableBuffers;
                end
            catch ME
                vprintf(2,'gui.BufferPlot: auto-selection failed: %s', ME.message)
            end
            if numel(names) > obj.MAX_AUTO
                vprintf(2,'gui.BufferPlot: %d buffers available; plotting the first %d', ...
                    numel(names), obj.MAX_AUTO)
                names = names(1:obj.MAX_AUTO);
            end
        end

        function tf = applySampleRateOption_(obj, rate)
            % Apply a SampleRate the caller stated. "auto"/"module" takes it
            % from the owning hw.Module, which is where a TDT device's real
            % rate has been since connect() read it off the hardware.
            tf = false;
            if isempty(rate), return; end
            if isnumeric(rate)
                obj.SampleRate = double(rate);
                tf = true;
                return
            end
            if ~ismember(lower(char(rate)), {'auto','module'})
                vprintf(0,1,'gui.BufferPlot: SampleRate must be a number, "auto", or "module"')
                return
            end
            fs = 0;
            for k = 1:numel(obj.Traces_)
                if obj.Traces_(k).Fs > obj.UNSET_MODULE_FS
                    fs = obj.Traces_(k).Fs;
                    break
                end
            end
            if fs <= 0
                vprintf(2,'gui.BufferPlot: no module reported a sample rate; plotting samples')
                return
            end
            obj.SampleRate = fs;
            tf = true;
            vprintf(2,'gui.BufferPlot: sample rate taken from the module: %g Hz', fs)
        end

        function k = traceIndex_(obj, target)
            % Plot index for a trace named by position or by buffer name.
            k = [];
            if isnumeric(target)
                if target >= 1 && target <= numel(obj.Traces_), k = target; end
                return
            end
            k = find(strcmp(obj.bufferNames, char(target)), 1);
        end

        function applyColors_(obj)
            % Rebuild LineColors: the palette, with the operator's hand-picked
            % colours laid over it BY NAME. Keeping the overrides in a map of
            % their own is what lets a colour follow its buffer through a
            % reselection while a palette change still reaches everything
            % nobody has coloured.
            names = obj.bufferNames;
            c = zeros(numel(names),3);
            for k = 1:numel(names)
                if isKey(obj.ColorOverride_, names{k})
                    c(k,:) = obj.ColorOverride_(names{k});
                else
                    c(k,:) = obj.paletteColor_(k);
                end
            end
            obj.PaletteStamp_ = obj.Palette;
            obj.LineColors = c; % PostSet redraws
        end

        function c = paletteColor_(obj, k)
            M = obj.paletteMatrix_(max(k,8));
            c = M(mod(k-1, size(M,1)) + 1, :);
        end

        function M = paletteMatrix_(obj, n)
            switch lower(obj.Palette)
                case 'lines',     M = lines(n);
                case 'parula',    M = parula(n);
                case 'turbo',     M = turbo(n);
                case 'grayscale', M = repmat(linspace(0, 0.7, n)', 1, 3);
                otherwise,        M = obj.PALETTE;
            end
        end
    end

    methods (Access = private)
        % -----------------------------------------------------------------
        % Right-click menu
        % -----------------------------------------------------------------
        function buildContextMenu_(obj)
            % The operator's half of the API. Every item routes through the
            % same public setter a script would call and then through
            % savePreferences_, so nothing the operator can do here is
            % unreachable from code, and nothing they choose is forgotten at
            % the end of the session.
            %
            % Tags follow the two conventions refreshMenuChecks_ reads back:
            %   'aes|<Property>|<value>' - a radio choice among fixed values
            %   'tgl|<Property>'         - a logical toggle
            fig = ancestor(obj.AxesH,'figure');
            if isempty(fig) || ~isvalid(fig), return; end
            try
                cm = uicontextmenu(fig);
                obj.ContextMenuH_ = cm;

                uimenu(cm,'Text','Select Buffers...', ...
                    'MenuSelectedFcn',@(~,~) obj.selectBuffers);

                m = uimenu(cm,'Text','X Axis');
                uimenu(m,'Text','Samples','Tag','aes|XAxisUnits|samples', ...
                    'MenuSelectedFcn',@(~,~) obj.setAesthetic_('XAxisUnits','samples'));
                uimenu(m,'Text','Seconds','Tag','aes|XAxisUnits|seconds', ...
                    'MenuSelectedFcn',@(~,~) obj.setAesthetic_('XAxisUnits','seconds'));
                uimenu(m,'Text','Milliseconds','Tag','aes|XAxisUnits|milliseconds', ...
                    'MenuSelectedFcn',@(~,~) obj.setAesthetic_('XAxisUnits','milliseconds'));
                uimenu(m,'Text','Sample Rate...','Separator','on', ...
                    'MenuSelectedFcn',@(~,~) obj.promptSampleRate_);

                m = uimenu(cm,'Text','Layout');
                uimenu(m,'Text','Overlay','Tag','aes|Layout|overlay', ...
                    'MenuSelectedFcn',@(~,~) obj.setAesthetic_('Layout','overlay'));
                uimenu(m,'Text','Stacked','Tag','aes|Layout|stacked', ...
                    'MenuSelectedFcn',@(~,~) obj.setAesthetic_('Layout','stacked'));

                m = uimenu(cm,'Text','Trials Shown');
                for t = obj.TRIALS_SHOWN
                    uimenu(m,'Text',num2str(t),'Tag',sprintf('aes|NumTrialsShown|%g',t), ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('NumTrialsShown',t));
                end

                m = uimenu(cm,'Text','Line Width','Separator','on');
                for w = obj.LINE_WIDTHS
                    uimenu(m,'Text',num2str(w),'Tag',sprintf('aes|LineWidth|%g',w), ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('LineWidth',w));
                end

                m = uimenu(cm,'Text','Palette');
                for k = 1:numel(obj.PALETTES)
                    p = obj.PALETTES{k};
                    uimenu(m,'Text',p,'Tag',['aes|Palette|' p], ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('Palette',p));
                end

                % One entry per trace, so a single buffer can be recoloured
                % without disturbing the rest. Rebuilt with the trace list.
                uimenu(cm,'Tag','uic_traceColors','Text','Trace Colour');

                m = uimenu(cm,'Text','Resolution');
                for p = obj.POINT_CAPS
                    if isfinite(p)
                        txt = sprintf('%d points',p);
                    else
                        txt = 'Every sample';
                    end
                    uimenu(m,'Text',txt,'Tag',sprintf('aes|MaxPoints|%g',p), ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('MaxPoints',p));
                end

                m = uimenu(cm,'Text','Y Limits');
                uimenu(m,'Text','Auto','Tag','aes|YLimMode|auto', ...
                    'MenuSelectedFcn',@(~,~) obj.setAesthetic_('YLimMode','auto'));
                uimenu(m,'Text','Freeze at current','Tag','uic_freezeY', ...
                    'MenuSelectedFcn',@(~,~) obj.freezeYLimits_);
                uimenu(m,'Text','Set...','Tag','uic_setY', ...
                    'MenuSelectedFcn',@(~,~) obj.promptYLimits_);

                uimenu(cm,'Text','Grid','Separator','on','Tag','tgl|ShowGrid', ...
                    'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('ShowGrid'));
                uimenu(cm,'Text','Legend','Tag','tgl|ShowLegend', ...
                    'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('ShowLegend'));
                uimenu(cm,'Text','Pause','Tag','tgl|Paused', ...
                    'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('Paused'));

                uimenu(cm,'Text','Copy Data to Workspace','Separator','on', ...
                    'MenuSelectedFcn',@(~,~) obj.exportToWorkspace);
                uimenu(cm,'Text','Reset Appearance', ...
                    'MenuSelectedFcn',@(~,~) obj.resetAppearance_);

                obj.addPopOutMenu_(cm);

                obj.AxesH.ContextMenu = cm;
                obj.rebuildTraceColorMenu_;
                obj.refreshMenuChecks_;
            catch ME
                vprintf(3,'gui.BufferPlot: context menu unavailable: %s', ME.message)
            end
        end

        function rebuildTraceColorMenu_(obj)
            % One "Trace Colour" child per plotted buffer.
            cm = obj.ContextMenuH_;
            if isempty(cm) || ~isvalid(cm), return; end
            parent = findall(cm,'Tag','uic_traceColors');
            if isempty(parent), return; end
            delete(allchild(parent));
            names = obj.bufferNames;
            if isempty(names), parent.Enable = 'off'; else, parent.Enable = 'on'; end
            for k = 1:numel(names)
                uimenu(parent,'Text',names{k}, ...
                    'MenuSelectedFcn',@(~,~) obj.pickTraceColor_(k));
            end
        end

        function refreshMenuChecks_(obj)
            % Sync check marks with the current property values.
            cm = obj.ContextMenuH_;
            if isempty(cm) || ~isvalid(cm), return; end
            items = findall(cm,'Type','uimenu');
            for k = 1:numel(items)
                t = items(k).Tag;
                if startsWith(t,'aes|')
                    p = strsplit(t,'|');
                    cur = obj.(p{2});
                    if isnumeric(cur), cur = num2str(cur); end
                    items(k).Checked = strcmp(cur,p{3});
                elseif startsWith(t,'tgl|')
                    p = strsplit(t,'|');
                    items(k).Checked = logical(obj.(p{2}));
                end
            end
        end

        function setAesthetic_(obj, prop, val)
            % Apply a menu choice, persist it, and redraw. The property
            % assignment is what a script does; the save is what makes this
            % the OPERATOR'S choice rather than the paradigm's.
            obj.(prop) = val;
            obj.savePreferences_;
        end

        function toggleAesthetic_(obj, prop)
            obj.setAesthetic_(prop, ~obj.(prop));
        end

        function pickTraceColor_(obj, k)
            names = obj.bufferNames;
            if k > numel(names), return; end
            c = obj.LineColors;
            cur = [0 0 0];
            if k <= size(c,1), cur = c(k,:); end
            picked = uisetcolor(cur, sprintf('Colour for %s', names{k}));
            if isscalar(picked), return; end % cancelled
            obj.setTraceColor(k, picked);
            obj.savePreferences_;
        end

        function promptSampleRate_(obj)
            % Ask for the buffer's sample rate. 0 means "unknown", which puts
            % the axis back to samples -- the honest reading when nothing on
            % the rig has said what the rate is.
            def = num2str(obj.SampleRate);
            answer = inputdlg({'Sample rate (Hz), or 0 to plot samples:'}, ...
                'Buffer Plot', 1, {def});
            if isempty(answer), return; end
            fs = str2double(answer{1});
            if isnan(fs) || fs < 0
                vprintf(0,1,'gui.BufferPlot: "%s" is not a sample rate', answer{1})
                return
            end
            obj.SampleRate = fs;
            if fs > 0 && strcmp(obj.XAxisUnits,'samples')
                obj.XAxisUnits = 'seconds'; % naming a rate is asking for a time axis
            elseif fs == 0
                obj.XAxisUnits = 'samples';
            end
            obj.savePreferences_;
        end

        function freezeYLimits_(obj)
            % Hold the limits the axes is showing right now, so a later trial
            % with a bigger transient cannot rescale everything under it.
            if isempty(obj.AxesH) || ~isvalid(obj.AxesH), return; end
            obj.YLim = obj.AxesH.YLim;
            obj.setAesthetic_('YLimMode','manual');
        end

        function promptYLimits_(obj)
            def = {num2str(obj.YLim(1)), num2str(obj.YLim(2))};
            answer = inputdlg({'Y minimum:','Y maximum:'},'Buffer Plot',1,def);
            if isempty(answer), return; end
            lo = str2double(answer{1});
            hi = str2double(answer{2});
            if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
                vprintf(0,1,'gui.BufferPlot: y limits must be finite and increasing')
                return
            end
            obj.YLim = [lo hi];
            obj.setAesthetic_('YLimMode','manual');
        end

        function resetAppearance_(obj)
            % Back to the class defaults, keeping the buffer selection and the
            % sample rate: those are what the plot IS, not how it looks.
            obj.ColorOverride_ = containers.Map('KeyType','char','ValueType','any');
            obj.Layout = 'overlay';
            obj.NumTrialsShown = 1;
            obj.HistoryAlpha = 0.3;
            obj.MaxPoints = 10000;
            obj.LineWidth = 1;
            obj.Palette = 'Okabe-Ito';
            obj.ShowGrid = true;
            obj.ShowLegend = true;
            obj.YLimMode = 'auto';
            obj.applyColors_;
            obj.savePreferences_;
        end

        % -----------------------------------------------------------------
        % Preferences
        % -----------------------------------------------------------------
        function loadPreferences_(obj, hasExplicitBuffers, hasExplicitRate)
            % Restore what was saved under this plot's key.
            %
            % Two rules decide how far a saved arrangement may reach, the ones
            % gui.OnlinePlot settled on:
            %   * AESTHETICS are always restored -- they are the operator's.
            %   * The SELECTION is restored only when the operator made it by
            %     hand, and a Buffers list given to the constructor is what
            %     the paradigm asked for.
            % The sample rate adds a third: a rate the caller stated always
            % wins, because it is a fact about the device rather than a taste.
            %
            % Nothing here throws, and nothing it does is written back.
            wasSuspended = obj.Suspend_;
            try
                pname = obj.preferenceName_;
                if ~ispref(obj.PREF_GROUP,pname), return; end
                s = getpref(obj.PREF_GROUP,pname);
                if ~isstruct(s), return; end

                obj.Suspend_ = true;

                for f = {'XAxisUnits','Layout','NumTrialsShown','HistoryAlpha', ...
                         'MaxPoints','LineWidth','Palette','ShowGrid','ShowLegend', ...
                         'YLimMode','YLim'}
                    if isfield(s,f{1})
                        try
                            obj.(f{1}) = s.(f{1});
                        catch
                            % A stored value this release no longer accepts is
                            % skipped: one bad field must not cost the rest.
                        end
                    end
                end
                if isfield(s,'SampleRate') && ~hasExplicitRate
                    obj.SampleRate = s.SampleRate;
                end

                if isfield(s,'SelectionByOperator') && s.SelectionByOperator ...
                        && isfield(s,'Buffers') && ~isempty(s.Buffers)
                    obj.SelectionByOperator_ = true;
                    if ~hasExplicitBuffers
                        obj.setBuffers(s.Buffers);
                    end
                end

                if isfield(s,'TraceStyle') && ~isempty(s.TraceStyle)
                    for k = 1:numel(s.TraceStyle)
                        c = s.TraceStyle(k).Color;
                        if numel(c) == 3
                            obj.ColorOverride_(s.TraceStyle(k).Name) = min(max(c(:)',0),1);
                        end
                    end
                end
                obj.applyColors_;

                obj.Suspend_ = wasSuspended;
                vprintf(3,'gui.BufferPlot: restored saved settings "%s"',pname)
            catch ME
                obj.Suspend_ = wasSuspended;
                vprintf(2,'gui.BufferPlot: failed to load preferences: %s', ME.message)
            end
        end

        function savePreferences_(obj)
            % Persist the operator's arrangement. Per-trace colours are stored
            % BY NAME, so a colour follows its buffer through a reselection.
            if obj.Suspend_, return; end
            try
                s = struct();
                s.Version = 1;
                for f = {'XAxisUnits','SampleRate','Layout','NumTrialsShown', ...
                         'HistoryAlpha','MaxPoints','LineWidth','Palette', ...
                         'ShowGrid','ShowLegend','YLimMode','YLim'}
                    s.(f{1}) = obj.(f{1});
                end
                s.Buffers = obj.bufferNames;
                s.SelectionByOperator = obj.SelectionByOperator_;

                style = struct('Name',{},'Color',{});
                names = obj.ColorOverride_.keys;
                for k = 1:numel(names)
                    style(k).Name = names{k};
                    style(k).Color = obj.ColorOverride_(names{k});
                end
                s.TraceStyle = style;

                setpref(obj.PREF_GROUP, obj.preferenceName_, s);
            catch ME
                vprintf(2,'gui.BufferPlot: failed to save preferences: %s', ME.message)
            end
        end

        function n = preferenceName_(obj)
            % Preference key scoped to the hosting GUI: explicit tag, else the
            % ancestor figure Tag, else its Name, else 'default'. The scheme
            % every component in this toolbox uses.
            n = obj.PreferenceTag_;
            if isempty(n)
                try
                    f = ancestor(obj.ContainerH,'figure');
                    if ~isempty(f) && isvalid(f)
                        if ~isempty(f.Tag)
                            n = f.Tag;
                        elseif ~isempty(f.Name)
                            n = f.Name;
                        end
                    end
                catch
                end
            end
            if isempty(n), n = 'default'; end
            n = matlab.lang.makeValidName(n);
        end
    end

    methods (Static, Access = private)
        function t = emptyTrace_()
            % The trace record, in the one field order every assignment to a
            % Traces_ element has to match.
            t = struct('Name',{},'ValidName',{},'Param',{},'Fs',{}, ...
                'FromData',{},'Ring',{},'Cache',{});
        end

        function v = recordValue_(rec, validName)
            % One buffer out of one trial record, or [] when that trial did
            % not carry it. A scalar is not a buffer: the runtime writes NaN
            % for a read that failed, and drawing a single point as a
            % waveform would say the buffer was empty when it was unreadable.
            v = [];
            if ~isstruct(rec) || ~isfield(rec, validName), return; end
            v = rec.(validName);
            if isstruct(v) && isfield(v,'Value'), v = v.Value; end
            if ~(isnumeric(v) || islogical(v)) || numel(v) < 2
                v = [];
                return
            end
            v = double(v(:));
        end

        function [xi,y] = envelope_(v, maxPoints)
            % Min/max envelope decimation of one buffer.
            %
            % Not a stride: dropping 9 samples in 10 hides exactly the brief
            % transient a buffer is usually being watched for, while the
            % envelope keeps every excursion the axes can resolve. Each bin
            % contributes its minimum and its maximum, in the order they
            % occur, so the line never runs backwards in x.
            v = double(v(:));
            n = numel(v);
            xi = (1:n)';
            y = v;
            if ~isfinite(maxPoints) || n <= maxPoints, return; end

            nb = max(1, floor(maxPoints/2));
            edges = round(linspace(1, n+1, nb+1));
            xi = zeros(2*nb,1);
            y = zeros(2*nb,1);
            for k = 1:nb
                a = edges(k);
                b = max(a, edges(k+1)-1);
                seg = v(a:b);
                [mn,imn] = min(seg,[],'omitnan');
                [mx,imx] = max(seg,[],'omitnan');
                if isempty(mn) || isnan(mn)
                    mn = NaN; mx = NaN; imn = 1; imx = 1;
                end
                i1 = a + imn - 1;
                i2 = a + imx - 1;
                if i1 <= i2
                    xi(2*k-1) = i1; y(2*k-1) = mn;
                    xi(2*k)   = i2; y(2*k)   = mx;
                else
                    xi(2*k-1) = i2; y(2*k-1) = mx;
                    xi(2*k)   = i1; y(2*k)   = mn;
                end
            end
        end
    end
end
