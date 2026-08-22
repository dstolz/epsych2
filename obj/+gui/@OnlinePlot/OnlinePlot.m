classdef OnlinePlot < gui.PopOut
    % OnlinePlot: Real-time multi-trace plotting for behavioral hardware.
    %
    %   obj = gui.OnlinePlot(RUNTIME, source, hax, BoxID)
    %   obj = gui.OnlinePlot(..., PreferenceTag=tag)
    %
    %   Plots hardware activity for a single experimental box on a timer with
    %   pause, context menus, time window, and trial-locked plotting. Two data
    %   sources are supported, selected by the `source` input:
    %
    %   * Parameter mode - source is an array of hw.Parameter objects or
    %     parameter name(s). Each parameter is polled every tick and plotted
    %     as its own trace. Omit source (or pass []) to choose parameters
    %     from a list dialog.
    %
    %   * Bitmask-bank mode - source is the name(s) of a bitmask bank
    %     published by the RPvds macros (a '~BMid-<bank>' parameter plus one
    %     '~BM-<bank>#<bit>^<label>' parameter per bit). The bank parameter
    %     is read once per tick and its bits are decoded into one trace per
    %     labeled bit, which is much faster than polling many parameters.
    %     (This mode replaces the former gui.OnlinePlotBM class.)
    %
    %   Reads are BATCHED PER INTERFACE, not issued per trace.
    %   hw.Parameter.get.Value costs an `isprop` plus an `IsConnected` probe
    %   before the value read, and on hw.TDT_RPcox that probe is itself a
    %   GetStatus COM call per module -- so an N-trace plot paid 2N round trips
    %   a tick where N+1 would do. Every backend but hw.Software and
    %   hw.VlcRecorder accepts a whole hw.Parameter array in one get_parameter
    %   call (hw.Teensy and hw.Bpod serve the batch from a single snapshot), so
    %   build_read_plan_ groups traces by owning interface and issues one call
    %   each. A group whose backend rejects the batch is demoted to
    %   per-parameter reads for the rest of the session rather than throwing.
    %
    %   WHICH TRACES, IN WHAT ORDER, AND HOW THEY LOOK are all settable two
    %   ways -- from code, through setWatched/setTraceOrder and the aesthetic
    %   properties, and by the operator, through the right-click menu (Select
    %   Traces..., Reorder Traces..., line width, palette, per-trace colour).
    %   Both paths land on the same setters, so nothing the menu does is
    %   unreachable from a script.
    %
    %   The operator's choices PERSIST across sessions under a preference key
    %   scoped to the hosting figure (or an explicit PreferenceTag), the same
    %   scheme gui.ParameterScatter uses. Two rules keep a remembered layout
    %   from fighting the paradigm that built the plot:
    %
    %     * the saved ORDER is always re-applied, matched by trace NAME --
    %       names it does not know are left where they are, and names that
    %       have gone are dropped, so an edited protocol degrades rather than
    %       throwing;
    %     * the saved SELECTION is re-applied only when the operator chose it
    %       by hand (Select Traces...). A `source` passed to the constructor
    %       is what a paradigm's build() asked for, and a stale saved list
    %       must not silently override it.
    %
    %   It is a gui.PopOut adopter, so any instance opens a second, fully
    %   independent view of the same box in its own window -- with its own
    %   trace selection, order and styling under its own preference key.
    %
    % Documentation: documentation/gui/gui_OnlinePlot.md
    % See also gui.PopOut, gui.BehaviorGUI, gui.ParameterScatter

    properties
        hax            (1,1)   % Axes handle for plotting
        watchedParams  (1,:)   % Array of hw.Parameter objects being plotted (parameter mode)
        trialParam             % Parameter for trial-based (triggered) plotting; empty disables
        lineWidth      (:,1) double {mustBePositive,mustBeFinite} % Line width per plot
        lineColors     (:,3) double {mustBeNonnegative,mustBeLessThanOrEqual(lineColors,1)} % Line RGB colors per plot
        yPositions     (:,1) double {mustBeFinite}   % Y offsets for each trace
        timeWindow     (1,2) duration = seconds([-10 3]); % Time axis window
        setZeroToNan   (1,1) logical = true;         % Replace 0s with NaN for visibility
        stayOnTop      (1,1) logical = false;        % Keep window always on top
        paused         (1,1) logical = false;        % If true, pause updating
        trialLocked    (1,1) logical = false;        % If true, plot is trial-locked
        trialMarker    (1,1) logical = true;         % Draw a marker line at each trial onset
        redrawPeriod   (1,1) double {mustBeNonnegative,mustBeFinite} = 0.1; % Minimum seconds between redraws; 0 draws on every tick
        maxTrialMarkers (1,1) double {mustBeInteger,mustBePositive} = 32; % Trial markers retained on the axes; the pool is built at setup, so a change takes effect on the next run
        showGrid       (1,1) logical = true;         % Draw the time grid
        palette        (1,:) char = 'Okabe-Ito';     % Named default trace palette; see PALETTES
    end

    properties (SetAccess = private)
        figH        (1,1)  % Main figure handle
        figName     (1,:)  char % Name for figure window
        lineH       (:,1)  matlab.graphics.primitive.Line % Handles to plot lines
        nowLine     (1,1)  matlab.graphics.primitive.Line
        N           (1,:)  double % Number of plotted traces
        startTime   (1,1) double % Session start time (serial date number from `now`)
        BoxID       (1,1) {mustBePositive,mustBeInteger} = 1;
        BM          % Struct array of bitmask banks (bitmask-bank mode); empty otherwise
        trialNumParam      % Optional parameter holding the current trial number (for markers)
    end

    properties (SetAccess = immutable)
        RUNTIME            % epsych.Runtime (assigned at construction)
    end

    properties (SetAccess = private, Hidden)
        h_timer       (1,1)      % Update h_timer object
        Buffers     (:,:) single   % Plot data buffer [N, time]
        BufferIdx   (1,1) double = 1   % Next circular-buffer slot to write
        Time        (:,1) double  % Buffer for time values (elapsed seconds since startTime)
        nFilled     (1,1) double = 0   % Number of valid samples written so far (saturates at capacity_)
        writeCount  (1,1) double = 0   % Monotonic update() tick count, never wraps
        prevTrigValue (1,1) double = nan % Last trialParam value seen; enables O(1) edge detection
        lastOnsetTime (1,1) double = nan % Elapsed-seconds timestamp of the last detected trial onset
        lastOnsetWriteCount (1,1) double = nan % writeCount recorded at the last detected onset
        pendingMarkerTime (1,1) double = nan % Onset awaiting a trial marker draw
        lastPlotTime (1,1) double = -inf % Elapsed-seconds timestamp of the last actual redraw
        periodNom   (1,1) double = 0.1  % Cached nominal timer period (seconds), used to size the plot window read
        hl_mode               % Listener for mode changes
        capacity_   (1,1) double = 1000 % Ring length, sized from timeWindow and the timer period
        startTic_   (1,1) uint64 = uint64(0) % Monotonic reference for elapsed seconds
        readGroups_ (1,:) struct = struct('Parent',{},'Params',{},'Rows',{},'Batched',{}) % One batched read per interface
        localParams_ (1,:)      % Parameters that must be read one at a time through .Value
        localRows_  (1,:) double % Their positions in the raw read vector
        nRead_      (1,1) double = 0 % Length of the raw read vector (traces, or banks in bitmask mode)
        bitSrc_     (:,1) double % Trace -> raw read index (identity in parameter mode)
        bitNum_     (:,1) double % Trace -> 1-based bit position (bitmask mode only)
        planDirty_  (1,1) logical = true % Read plan needs rebuilding before the next sample
        readWarned_ (1,:) cell = {} % Read failures already logged, so a dead device cannot flood the log
        markerLine_ (:,1) = gobjects(0,1) % Recycled trial-onset marker lines
        markerText_ (:,1) = gobjects(0,1) % Recycled trial-number labels
        markerIdx_  (1,1) double = 0 % Monotonic marker counter; slot is mod(markerIdx_,maxTrialMarkers)+1
        ownsFigure_ (1,1) logical = false % False when embedded in a host GUI's axes
        allParams_  (1,:)       % Every parameter resolved from a name source, so Select Traces... can re-widen
        BMFull_     % Bank definitions before bit selection; obj.BM is the selected subset
        PreferenceTag_ (1,:) char = '' % Explicit preference key; else the hosting figure's
        selectionByOperator_ (1,1) logical = false % The trace list was chosen by hand, so it outranks the constructor source
        pendingOrder_ (1,:) cell = {} % Saved trace order awaiting names it can match
        ContextMenuH_ % The right-click menu, kept for check-mark refreshes
        suspendSave_ (1,1) logical = false % True while restoring, so loading does not re-save what it read
    end

    properties (Constant, Access = private)
        % Okabe-Ito, the standard colorblind-safe qualitative set. `lines` puts
        % blue beside cyan and red beside orange, which on 10 px state traces is
        % the one distinction an operator has to make at a glance.
        PALETTE = [ 0.000 0.447 0.698     % blue
                    0.902 0.624 0.000     % orange
                    0.000 0.620 0.451     % bluish green
                    0.800 0.475 0.655     % reddish purple
                    0.337 0.706 0.914     % sky blue
                    0.835 0.369 0.000     % vermillion
                    0.749 0.706 0.106     % yellow (darkened for white ground)
                    0.350 0.350 0.350 ];  % grey

        PREF_GROUP  = 'epsych2_gui_OnlinePlot' % getpref/setpref group for saved layouts
        PALETTES    = {'Okabe-Ito','Lines','Parula','Turbo','Grayscale'} % Offered on the menu
        LINE_WIDTHS = [2 4 6 8 10 14 18]  % Offered on the menu
        REDRAW_RATES = [2 5 10 20]        % Hz, offered on the menu
    end

    methods
        function obj = OnlinePlot(RUNTIME,source,hax,BoxID,options)
            % Constructor: initializes online plot for the chosen source and axes.
            %
            % The three positional inputs are unchanged; PreferenceTag is a
            % trailing name-value, so every existing call site still compiles.
            arguments
                RUNTIME
                source = []
                hax = []
                BoxID = []
                options.PreferenceTag {mustBeTextScalar} = ''
            end
            obj.RUNTIME = RUNTIME;
            if isempty(BoxID), BoxID = 1; end
            obj.BoxID = BoxID;
            obj.PreferenceTag_ = char(options.PreferenceTag);

            obj.resolve_source(source);
            if isempty(obj.BM) && isempty(obj.watchedParams)
                delete(obj); return; % selection cancelled or bank not found
            end

            if isempty(hax)
                obj.setup_figure;
                obj.ownsFigure_ = true;
            else
                obj.hax = hax;
            end
            disableDefaultInteractivity(obj.hax);
            obj.style_axes;

            obj.PopOutLabel = sprintf('Online Plot | Box %d',BoxID);
            obj.PopOutSize = [900 max(240, min(760, 120 + 34*obj.N))];

            % Preferences come AFTER the axes exists (the key is scoped by the
            % hosting figure) and BEFORE the menu is built, so the check marks
            % are drawn against the restored values rather than the defaults.
            obj.loadPreferences_(~isempty(source));
            obj.buildContextMenu_;

            % > _TrigState~<BoxID> is contained in the standard epsych RPvds
            % macros and drives trial-onset detection for trial-locked mode.
            obj.trialParam = obj.RUNTIME.find_parameter(sprintf('_TrigState~%d',BoxID), ...
                includeInvisible=true,silenceParameterNotFound=true);
            obj.trialNumParam = obj.RUNTIME.find_parameter(sprintf('_TrialNum~%d',BoxID), ...
                includeInvisible=true,silenceParameterNotFound=true);

            % gui.GenericTimer ADOPTS an existing timer of the same name, so
            % a name fixed by BoxID alone makes two plots on one box share a
            % timer -- and the first one torn down deletes it under the
            % second, which then throws on its next property write. That was
            % survivable while this was one window per box; it is not now the
            % component can be embedded, and placed twice, from
            % gui.BehaviorBuilder.
            tname = sprintf('epsych_gui_OnlinePlot~%d',BoxID);
            existing = timerfindall;
            if ~isempty(existing)
                tname = matlab.lang.makeUniqueStrings(tname, {existing.Name});
            end
            obj.h_timer = gui.GenericTimer(obj.figH,tname);
            obj.h_timer.Timer.StartFcn = @obj.setup_plot;
            obj.h_timer.Timer.TimerFcn = @obj.update;
            obj.h_timer.Timer.ErrorFcn = @obj.error;
            if isempty(obj.BM)
                obj.h_timer.Timer.Period = 0.1;
            else
                % bank reads are cheap; sample faster so brief bit pulses register
                obj.h_timer.Timer.Period = 0.05;
            end
            obj.h_timer.Timer.start;

            % RUNTIME.Interfaces, not the RUNTIME.HW this used to read: the
            % property was renamed and nothing here followed, so constructing
            % an OnlinePlot against a current runtime threw. With no interfaces
            % at all (a GUI opened against an empty runtime, epsych.SelfTest
            % check I6) there is nothing whose mode could change, and the plot
            % still draws.
            %
            % ONE LISTENER PER INTERFACE, not one over the array: hw.Interface
            % is matlab.mixin.Heterogeneous and `listener` is not sealed, so a
            % rig running two different backends -- the ordinary case once a
            % pump or a recorder joins the TDT device -- threw on construction.
            % Indexing the array yields the concrete class, which dispatches.
            HW = RUNTIME.Interfaces;
            L = event.listener.empty(1,0);
            for i = 1:numel(HW)
                L(end+1) = listener(HW(i),'mode','PostSet',@obj.mode_change); %#ok<AGROW>
            end
            obj.hl_mode = L;
        end

        function delete(obj)
            % Destructor: Stops h_timer and cleans up resources.
            try
                stop(obj.h_timer);
                delete(obj.h_timer);
            end

            try
                for i = 1:numel(obj.hl_mode)
                    obj.hl_mode(i).Enabled = false;
                end
                delete(obj.hl_mode);
            end

            % Embedded in a host GUI the axes outlives this object, so the
            % lines, markers and now-line have to go with it or they stay
            % frozen on the host's display.
            try
                delete(obj.lineH(isvalid(obj.lineH)));
                delete(obj.markerLine_(isvalid(obj.markerLine_)));
                delete(obj.markerText_(isvalid(obj.markerText_)));
                if isvalid(obj.nowLine), delete(obj.nowLine); end
            end
        end

        function pause(obj,varargin)
            % Toggle paused state, update menu label.
            obj.paused = ~obj.paused;
            c = obj.get_menu_item('uic_pause');
            if isempty(c), return; end
            if obj.paused
                c.Label = 'Catch up >';
            else
                c.Label = 'Pause ||';
            end
        end

        function c = get.figH(obj)
            % Get the ancestor figure handle from axes.
            c = ancestor(obj.hax,'figure');
        end

        function s = get.figName(obj)
            % Get name string for the figure window.
            s = sprintf('Online Plot | Box %d',obj.BoxID);
        end

        function set.watchedParams(obj,p)
            obj.watchedParams = p;
            obj.planDirty_ = true;
        end

        function set.timeWindow(obj,w)
            obj.timeWindow = w;
            obj.ensure_capacity_;
        end

        function set.yPositions(obj,y)
            % Set Y offsets for each trace, must match number of parameters.
            % EMPTY clears them back to the 1:N default, which is how a trace
            % selection or reorder hands the axis back to the getter.
            assert(isempty(y) || length(y) == obj.N,'epsych:OnlinePlot:set.yPositions', ...
                'Must set all yPositions at once');
            obj.yPositions = y;
        end

        function y = get.yPositions(obj)
            % Return current or default Y offsets.
            if isempty(obj.yPositions)
                y = (1:obj.N)';
            else
                y = obj.yPositions;
                if length(y) < obj.N
                    y = [y; y(end)+(1:obj.N-length(y))'+max(diff(y))];
                else
                    y = y(1:obj.N);
                end
            end
        end

        function w = get.lineWidth(obj)
            % Get or set default line widths for all traces.
            if isempty(obj.lineWidth)
                w = repmat(10,obj.N,1);
            else
                w = obj.lineWidth;
                if length(w) < obj.N
                    w = [w; repmat(10,obj.N-length(w),1)];
                else
                    w = w(1:obj.N);
                end
            end
        end

        function set.lineColors(obj,c)
            obj.lineColors = c;
            obj.apply_lineColors;
        end

        function c = get.lineColors(obj)
            % Get or expand default RGB colors for lines.
            if isempty(obj.lineColors)
                c = obj.paletteColors_(obj.N);
            else
                c = obj.lineColors;
                if size(c,1) < obj.N
                    x = obj.paletteColors_(obj.N);
                    c = [c; x(size(c,1)+1:obj.N,:)];
                else
                    c = c(1:obj.N,:);
                end
            end
        end

        function s = get.N(obj)
            % Number of plotted traces.
            if isempty(obj.BM)
                s = numel(obj.watchedParams);
            else
                s = sum([obj.BM.N]);
            end
        end

        function setTraceColor(obj,trace,rgb)
            % setTraceColor(obj,trace,rgb)
            % Colour one trace, named or indexed. The menu's Trace Colour
            % entries and a script both come through here, and the choice is
            % remembered against the trace's NAME, so it survives a reorder.
            i = obj.traceIndex_(trace);
            if isempty(i), return; end
            c = obj.lineColors; % expand from the palette before editing a row
            c(i,:) = min(max(double(rgb(:)'),0),1);
            obj.setAesthetic_('lineColors',c);
        end

        function setTraceWidth(obj,trace,w)
            % setTraceWidth(obj,trace,w)
            % Line width for one trace, named or indexed. Pass [] for `trace`
            % to set every trace at once.
            v = obj.lineWidth;
            if isempty(trace)
                v(:) = w;
            else
                i = obj.traceIndex_(trace);
                if isempty(i), return; end
                v(i) = w;
            end
            obj.setAesthetic_('lineWidth',v);
        end

        function saveConfiguration(obj)
            % saveConfiguration(obj)
            % Write the current traces, order and appearance to preferences.
            %
            % The operator's own changes save themselves as they are made;
            % this is for a script that set the properties directly and wants
            % that arrangement to be the one restored next session.
            obj.savePreferences_;
        end

        function tf = hasSavedConfiguration(obj)
            % tf = hasSavedConfiguration(obj)
            % True when an arrangement is already stored under this plot's
            % preference key. A caller setting up defaults uses it to keep
            % from overwriting what the operator arranged last session.
            tf = false;
            try
                tf = ispref(obj.PREF_GROUP,obj.preferenceName_);
            catch
            end
        end

        function forgetConfiguration(obj)
            % forgetConfiguration(obj)
            % Discard the saved arrangement for this plot's preference key, so
            % the next plot built under it starts from the paradigm's defaults.
            try
                if ispref(obj.PREF_GROUP,obj.preferenceName_)
                    rmpref(obj.PREF_GROUP,obj.preferenceName_);
                end
            catch ME
                vprintf(2,'gui.OnlinePlot: failed to clear preferences: %s',ME.message)
            end
        end

        function to = last_trial_onset(obj)
            % Elapsed-seconds timestamp (double) of the most recent trial onset.
            % Tracked incrementally in update() (see prevTrigValue/lastOnsetTime)
            % rather than rescanning a buffer every call.
            if isnan(obj.lastOnsetTime) || (obj.writeCount - obj.lastOnsetWriteCount) > obj.capacity_
                to = []; % no onset yet, or onset predates the retained buffer history
            else
                to = obj.lastOnsetTime;
            end
        end

        % Efficient circular buffer, throttled draw, and windowed plotting
        function update(obj,varargin)
            n = obj.N;

            % --- 1. Initialize circular buffers, or resize after a source change ---
            if isempty(obj.Buffers) || size(obj.Buffers,1) ~= n
                obj.reset_buffers_(n);
            end

            cap = obj.capacity_;
            currentRawIdx = obj.BufferIdx;
            nowT = toc(obj.startTic_); % monotonic; `now` was slower and clock-sensitive

            % --- 2. Trial onset detection: O(1) rising-edge check (never skipped) ---
            if ~isempty(obj.trialParam)
                try
                    v = obj.trialParam.Value;
                    if ~isnan(obj.prevTrigValue) && v > obj.prevTrigValue
                        obj.lastOnsetTime = nowT;
                        obj.lastOnsetWriteCount = obj.writeCount;
                        obj.pendingMarkerTime = nowT;
                    end
                    obj.prevTrigValue = v;
                catch
                    vprintf(0,1,'Unable to read the trial parameter; disabling trial-locked plotting')
                    delete(obj.get_menu_item('uic_plotType'));
                    obj.trialParam = [];
                end
            end

            % --- 3. Store trace values and time (zero-to-NaN on the column, not the matrix) ---
            newcol = obj.sample_values;
            if obj.setZeroToNan
                newcol(newcol == 0) = nan;
            end
            obj.Buffers(:, currentRawIdx) = newcol;
            obj.Time(currentRawIdx) = nowT;

            % --- 4. Advance circular buffer pointer (single site) ---
            obj.BufferIdx = mod(currentRawIdx, cap) + 1;
            obj.nFilled = min(obj.nFilled + 1, cap);
            obj.writeCount = obj.writeCount + 1;

            % --- 5. Skip plotting while paused ---
            if obj.paused, return; end

            % --- 6. Throttle redraws, independent of the sampling rate ---
            if (nowT - obj.lastPlotTime) < obj.redrawPeriod, return; end

            % --- 7. Resolve the visible window ONCE. The data cut and the
            %        x-limits are both read off it, so they cannot disagree ---
            winSec = seconds(obj.timeWindow);
            lto = obj.last_trial_onset; % call once per tick
            if obj.trialLocked && ~isempty(obj.trialParam) && ~isempty(lto)
                t0 = lto;
            elseif obj.trialLocked
                t0 = 0;
            else
                t0 = nowT;
            end
            loT = t0 + winSec(1);
            hiT = t0 + winSec(2);

            % --- 8. Only pull the recent samples the visible window actually needs ---
            Nlook = max(1, min([obj.nFilled, cap, ceil(max(0,nowT-loT)/obj.periodNom) + 5]));

            startRaw = currentRawIdx - Nlook + 1;
            if startRaw >= 1
                rawIdx = startRaw:currentRawIdx; % single contiguous piece
            else
                rawIdx = [(cap+startRaw):cap, 1:currentRawIdx]; % one wraparound piece
            end
            % rawIdx walks strictly backward from the write head, so it is
            % always chronologically ascending -- no sort needed.
            plotTime = obj.Time(rawIdx);
            tspan = (plotTime >= loT) & (plotTime <= hiT);
            plotTimeWin = plotTime(tspan);
            plotBuffersWin = obj.Buffers(:, rawIdx(tspan));

            % --- 9. Push every trace in one graphics transaction. The x vector
            %        is shared by reference through the cell, so replicating it
            %        costs nothing, and setting X and Y together avoids the
            %        moment where a Line holds a new X against an old Y --
            %        HG2 truncates the other array to match ---
            if numel(obj.lineH) ~= n, return; end % setup_plot has not run yet
            yPos = obj.yPositions; % hoisted once per tick, not obj.N times
            xd = seconds(plotTimeWin(:)'); % converted once, not once per trace
            yd = num2cell(double(plotBuffersWin) .* yPos, 2);
            set(obj.lineH, {'XData','YData'}, [repmat({xd},n,1), yd]);

            % --- 10. Adjust x-limits ---
            obj.hax.XLim = seconds([loT hiT]);
            if ~isempty(plotTimeWin)
                obj.nowLine.XData = seconds(plotTimeWin(end)).*[1 1];
            end

            % --- 11. Draw a trial marker for any onset seen since the last redraw ---
            if obj.trialMarker && ~isnan(obj.pendingMarkerTime)
                obj.plot_trialMarker(obj.pendingMarkerTime);
                obj.pendingMarkerTime = nan;
            end

            drawnow limitrate

            obj.lastPlotTime = nowT;
        end

        function error(obj,varargin)
            % Handles h_timer errors.
            vprintf(-1,'OnlinePlot closed with error')
            vprintf(-1,varargin{2}.Data) % one record, carrying identifier and stack
        end
    end

    methods (Access = private)
        function src = currentSource_(obj)
            % What this plot would be constructed from today: the parameter
            % handles, or the BANK names in bitmask mode. Bank names rather
            % than bit labels because that is what the constructor resolves;
            % narrowing to the shown bits is setWatched's job afterwards.
            if isempty(obj.BMFull_)
                src = obj.watchedParams;
                return
            end
            src = cell(1,numel(obj.BMFull_));
            for i = 1:numel(obj.BMFull_)
                src{i} = erase(obj.BMFull_(i).Bank.Name,'~BMid-');
            end
        end

        function c = paletteColors_(obj,n)
            % n distinct trace colors from the named palette. Past a palette's
            % base set the colors repeat at stepped lightness, so trace 9 is a
            % visibly paler trace 1 rather than an exact duplicate.
            if n <= 0, c = zeros(0,3); return; end
            switch lower(obj.palette)
                case 'lines',     P = lines(7);
                case 'parula',    P = parula(8);
                case 'turbo',     P = turbo(8);
                case 'grayscale', P = repmat(linspace(0.15,0.7,6)',1,3);
                otherwise,        P = gui.OnlinePlot.PALETTE; % Okabe-Ito
            end
            m = size(P,1);
            c = zeros(n,3);
            for i = 1:n
                f = min(0.55, 0.28*floor((i-1)/m)); % blend toward white per cycle
                c(i,:) = P(mod(i-1,m)+1,:)*(1-f) + f;
            end
            c = min(max(c,0),1);
        end
    end

    methods (Static, Access = private)
        function v = scalarize_(x)
            % One double per trace. A Buffer parameter returns a whole vector
            % and a String parameter a char row; either would derail the column
            % assignment, so anything unplottable becomes NaN.
            if isempty(x) || ~(isnumeric(x) || islogical(x))
                v = nan;
            elseif isscalar(x)
                v = double(x);
            else
                v = double(x(1));
            end
        end
    end

    methods (Access = protected)
        function resolve_source(obj,source)
            % Determine plotting mode and resolve traces from `source`.
            if isa(source,'hw.Parameter')
                obj.watchedParams = source;
                % The pool Select Traces... offers is everything readable, not
                % just what was handed in -- a paradigm naming three signals
                % should not stop the operator adding a fourth.
                obj.allParams_ = obj.readableParameters_(source);
                return
            end

            if isempty(source)
                % Select parameters to plot from a list dialog
                p = obj.readableParameters_(hw.Parameter.empty(1,0));
                if isempty(p)
                    vprintf(0,1,'gui.OnlinePlot: this runtime has no readable parameters to plot')
                    return
                end
                [s,v] = listdlg('PromptString','Select parameters for plot', ...
                    'SelectionMode','multiple','ListString',{p.Name});
                if v == 0, return; end
                obj.watchedParams = p(s);
                obj.allParams_ = p;
                % Chosen at the dialog, so it outranks nothing -- but it IS the
                % operator's list, and Select Traces... must be able to widen
                % back to everything readable.
                obj.selectionByOperator_ = true;
                return
            end

            source = cellstr(source);

            % Bitmask-bank mode when every entry names a published bank
            isBank = false(size(source));
            for i = 1:numel(source)
                p0 = obj.RUNTIME.filter_parameters('Name',sprintf('~BMid-%s',source{i}), ...
                    testFcn=@isequal,includeInvisible=true);
                isBank(i) = ~isempty(p0);
            end

            if ~any(isBank)
                obj.watchedParams = obj.RUNTIME.find_parameter(source,includeInvisible=true);
                obj.allParams_ = obj.readableParameters_(obj.watchedParams);
                return
            end
            assert(all(isBank),'epsych:OnlinePlot:mixedSource', ...
                'Cannot mix bitmask bank names and parameter names in one OnlinePlot');

            % '~BM-<bank>#<bit>^<label>' parameters describe each bit of the bank
            pattern = '#(\d+)\^(.+)';
            for i = 1:numel(source)
                p0 = obj.RUNTIME.filter_parameters('Name',sprintf('~BMid-%s',source{i}), ...
                    testFcn=@isequal,includeInvisible=true);
                p = obj.RUNTIME.filter_parameters('Name',sprintf('~BM-%s',source{i}), ...
                    testFcn=@startsWith,includeInvisible=true);
                if isempty(p)
                    vprintf(0,1,'No bitmask parameters found for bank: %s',source{i});
                    continue
                end

                tokens = regexp({p.Name}, pattern, 'tokens','once');
                n = numel(tokens);
                id = nan(n,1);
                label = cell(n,1);
                for j = 1:n
                    id(j)    = str2double(tokens{j}{1});
                    label{j} = tokens{j}{2};
                end

                obj.BM(end+1).Bank = p0;
                obj.BM(end).Label = label;
                obj.BM(end).Bit = id;
                obj.BM(end).N = n;
            end
            % The full bank definition is kept so a bit hidden by Select
            % Traces... can be brought back without re-reading the protocol.
            obj.BMFull_ = obj.BM;
            obj.planDirty_ = true;
        end

        function build_read_plan_(obj)
            % Group this tick's reads by owning interface.
            %
            % Both modes reduce to the same shape: a raw read vector (one entry
            % per polled parameter -- a trace in parameter mode, a bank in
            % bitmask mode) plus the map from raw entries to plotted traces.
            % Grouping is what makes a tick cost O(interfaces) instead of
            % O(traces); see the class comment.
            if isempty(obj.BM)
                P = obj.watchedParams(:).';
                obj.bitSrc_ = (1:numel(P))';
                obj.bitNum_ = zeros(numel(P),1);
            else
                P = [obj.BM.Bank];
                src = cell(1,numel(obj.BM));
                bit = cell(1,numel(obj.BM));
                for i = 1:numel(obj.BM)
                    src{i} = repmat(i,obj.BM(i).N,1);
                    bit{i} = obj.BM(i).Bit(:) + 1; % bitget positions are 1-based
                end
                obj.bitSrc_ = cat(1,src{:});
                obj.bitNum_ = cat(1,bit{:});
            end

            obj.nRead_ = numel(P);
            obj.readGroups_ = struct('Parent',{},'Params',{},'Rows',{},'Batched',{});
            obj.localParams_ = [];
            obj.localRows_ = [];

            for k = 1:numel(P)
                p = P(k);
                % These read locally inside hw.Parameter.get.Value; routing them
                % through an interface would either recurse (hw.Software) or
                % return the wrong thing (a StimType read gives the device
                % samples derived from the stimulus, not the stimulus object).
                if isequal(p.Access,'Write') || isequal(p.Type,'StimType') ...
                        || isa(p.Parent,'hw.Software') || ~isvalid(p.Parent)
                    obj.localParams_ = [obj.localParams_ p];
                    obj.localRows_(end+1) = k;
                    continue
                end

                g = 0;
                for j = 1:numel(obj.readGroups_)
                    % Class first, and short-circuit: == across two different
                    % handle classes errors, and a rig may mix backends.
                    if strcmp(class(obj.readGroups_(j).Parent),class(p.Parent)) ...
                            && obj.readGroups_(j).Parent == p.Parent
                        g = j; break
                    end
                end
                if g == 0
                    obj.readGroups_(end+1) = struct('Parent',p.Parent, ...
                        'Params',p,'Rows',k,'Batched',true);
                else
                    obj.readGroups_(g).Params(end+1) = p;
                    obj.readGroups_(g).Rows(end+1) = k;
                end
            end

            obj.planDirty_ = false;
        end

        function v = sample_values(obj)
            % One column of trace values for the current tick.
            if obj.planDirty_, obj.build_read_plan_; end

            raw = nan(obj.nRead_,1);

            for k = 1:numel(obj.localRows_)
                try
                    raw(obj.localRows_(k)) = gui.OnlinePlot.scalarize_(obj.localParams_(k).Value);
                catch ME
                    obj.warn_read_(obj.localParams_(k).Name,ME);
                end
            end

            for g = 1:numel(obj.readGroups_)
                G = obj.readGroups_(g);
                if G.Batched
                    try
                        val = G.Parent.get_parameter(G.Params,includeInvisible=true);
                        if ~iscell(val), val = {val}; end
                        for k = 1:numel(G.Rows)
                            raw(G.Rows(k)) = gui.OnlinePlot.scalarize_(val{k});
                        end
                        continue
                    catch ME
                        % A backend that takes one name at a time
                        % (hw.VlcRecorder) or refuses the option: demote the
                        % group for good rather than pay a failing call every
                        % tick.
                        obj.readGroups_(g).Batched = false;
                        vprintf(2,'OnlinePlot: %s cannot batch reads, polling one at a time (%s)', ...
                            class(G.Parent),ME.message);
                    end
                end
                for k = 1:numel(G.Rows)
                    try
                        raw(G.Rows(k)) = gui.OnlinePlot.scalarize_(G.Params(k).Value);
                    catch ME
                        obj.warn_read_(G.Params(k).Name,ME);
                    end
                end
            end

            if isempty(obj.BM)
                v = single(raw);
            else
                src = raw(obj.bitSrc_);
                bad = ~isfinite(src) | src < 0;
                src(bad) = 0;
                v = single(bitget(uint64(floor(src)),obj.bitNum_));
                v(bad) = nan;
            end
            v = v(:);
        end

        function warn_read_(obj,name,ME)
            % Log a failed read once per parameter and message. A rig unplugged
            % mid-session throws on every trace on every tick otherwise.
            key = [name '|' ME.message];
            if any(strcmp(obj.readWarned_,key)), return; end
            obj.readWarned_{end+1} = key;
            vprintf(1,'OnlinePlot: unable to read "%s" (%s)',name,ME.message);
        end

        function ensure_capacity_(obj)
            % Size the ring from the widest window it must hold.
            %
            % The old fixed 1000 samples truncated silently: at the 0.05 s
            % bitmask period that is 50 s of history, so widening the window
            % past it drew a plot that simply stopped part way back.
            p = obj.periodNom;
            if isempty(p) || ~isfinite(p) || p <= 0, return; end
            span = abs(diff(seconds(obj.timeWindow)));
            want = min(200000, max(1000, ceil(1.25*span/p) + 10));
            if want == obj.capacity_, return; end
            obj.capacity_ = want;
            obj.reset_buffers_(obj.N); % a resize cannot preserve the ring phase
        end

        function reset_buffers_(obj,n)
            % (Re)allocate the ring and the incremental trial-onset state.
            if nargin < 2, n = obj.N; end
            obj.Buffers = nan(n, obj.capacity_, 'single');
            obj.Time = nan(obj.capacity_, 1);
            obj.BufferIdx = 1;
            obj.nFilled = 0;
            obj.writeCount = 0;
            obj.prevTrigValue = nan;
            obj.lastOnsetTime = nan;
            obj.lastOnsetWriteCount = nan;
            obj.pendingMarkerTime = nan;
            obj.lastPlotTime = -inf;
        end

        function lbl = trace_labels(obj)
            % Y tick label for each trace.
            if isempty(obj.BM)
                lbl = {obj.watchedParams.Name};
            else
                lbl = cat(1,obj.BM.Label);
            end
        end

        function apply_lineColors(obj)
            % Push (expanded) lineColors onto existing line objects.
            if isempty(obj.lineH), return; end
            c = obj.lineColors;
            for i = 1:min(obj.N,numel(obj.lineH))
                if isvalid(obj.lineH(i))
                    obj.lineH(i).Color = c(i,:);
                end
            end
        end

        function style_axes(obj)
            % Static appearance, applied once. Anything that depends on the
            % trace count is left to setup_plot.
            ax = obj.hax;
            ax.FontSize = 9;
            ax.TickDir = 'out';
            ax.TickLength = [0.004 0.004];
            ax.Box = 'on';
            ax.Layer = 'top'; % grid under the traces, axes lines over them
            ax.XColor = [0.25 0.25 0.25];
            ax.YColor = [0.25 0.25 0.25];
            ax.GridColor = [0 0 0];
            ax.GridAlpha = 0.12;
            ax.MinorGridColor = [0 0 0];
            ax.MinorGridAlpha = 0.06;
            ax.MinorGridLineStyle = '-';
            if isprop(ax,'Toolbar'), ax.Toolbar = []; end
        end

        function setup_plot(obj,varargin)
            % Create/recreate plot lines and initialize plot axes/labels.
            obj.periodNom = obj.h_timer.Timer.Period;
            obj.ensure_capacity_;
            obj.reset_buffers_;
            obj.planDirty_ = true;

            delete(obj.lineH(isvalid(obj.lineH)));
            delete(obj.markerLine_(isvalid(obj.markerLine_)));
            delete(obj.markerText_(isvalid(obj.markerText_)));
            if ~isempty(obj.nowLine) && isvalid(obj.nowLine), delete(obj.nowLine); end
            obj.lineH = matlab.graphics.primitive.Line.empty(0,1);

            n = obj.N;
            yPos = obj.yPositions;
            c = obj.lineColors;
            w = obj.lineWidth;
            for i = 1:n
                obj.lineH(i,1) = line(obj.hax,seconds(0),yPos(i), ...
                    'Color',c(i,:), ...
                    'LineWidth',w(i), ...
                    'LineJoin','round');
            end

            xtickformat(obj.hax,'mm:ss.S');
            obj.applyStyle_; % grid follows showGrid, not a hardcoded 'on'
            obj.hax.YAxis.TickValues = yPos;
            obj.hax.YAxis.TickLabelInterpreter = 'none';
            obj.hax.YAxis.TickLabels = obj.trace_labels;

            % Headroom above the top trace for the trial-number labels, which
            % used to be drawn at N+0.5 -- above the old limit, so invisible.
            lo = min(yPos); hi = max(yPos);
            pad = max(0.5, 0.06*max(1,hi-lo));
            obj.hax.YAxis.Limits = [lo-pad, hi+2.2*pad];

            obj.startTime = now; %#ok<TNOW1> kept as a serial datenum for the record
            obj.startTic_ = tic;

            obj.nowLine = line(obj.hax,seconds([0 0]),[-1e6 1e6], ...
                'Color',[0.35 0.35 0.35],'LineStyle','--','LineWidth',0.75, ...
                AffectAutoLimits="off");

            obj.build_marker_pool_;
        end

        function build_marker_pool_(obj)
            % Trial markers are RECYCLED, not accumulated. One line and one text
            % per onset was an unbounded leak: an hour at 4 s a trial left ~900
            % of each on the axes, every one re-rendered by every drawnow for
            % the rest of the session.
            %
            % The marker is DASHED because it sits on top of the traces and
            % Line.Color silently drops the alpha channel in R2024b -- the gaps
            % are the only way a trace reads through an onset line.
            k = obj.maxTrialMarkers;
            L = gobjects(k,1);
            T = gobjects(k,1);
            yl = obj.hax.YAxis.Limits;
            for i = 1:k
                L(i) = line(obj.hax,seconds([0 0]),[-1e6 1e6], ...
                    'Color',[0.85 0.33 0.33],'LineWidth',1.25,'LineStyle','--', ...
                    'Visible','off',AffectAutoLimits="off");
                T(i) = text(obj.hax,seconds(0),yl(2),'', ...
                    'FontSize',9,'FontWeight','bold','Color',[0.65 0.20 0.20], ...
                    'HorizontalAlignment','center','VerticalAlignment','top', ...
                    'Clipping','on','Visible','off');
            end
            obj.markerLine_ = L; % assign once; a property write revalidates
            obj.markerText_ = T;
            obj.markerIdx_ = 0;
        end

        function plot_trialMarker(obj,t)
            % Mark a trial onset with a vertical line and the trial number,
            % reusing the oldest slot in the pool.
            if isempty(t) || isempty(obj.markerLine_), return; end
            i = mod(obj.markerIdx_,numel(obj.markerLine_)) + 1;
            obj.markerIdx_ = obj.markerIdx_ + 1;

            obj.markerLine_(i).XData = seconds([t t]);
            obj.markerLine_(i).Visible = 'on';

            if isempty(obj.trialNumParam)
                obj.markerText_(i).Visible = 'off';
                return
            end
            try
                tn = obj.trialNumParam.Value - 1;
                yl = obj.hax.YAxis.Limits;
                % Text.Position is plain numeric even on a duration ruler,
                % whose backing units here are seconds -- so `t` goes in as-is.
                % A duration in a Position vector is rejected outright.
                obj.markerText_(i).Position = [t yl(2) 0];
                obj.markerText_(i).String = num2str(tn,'%d');
                obj.markerText_(i).Visible = 'on';
            catch ME
                obj.warn_read_('trial number label',ME);
                obj.markerText_(i).Visible = 'off';
            end
        end

        function setup_figure(obj)
            % Create or reuse a figure/axes for plotting if none supplied.
            f = findobj('type','figure','-and', '-regexp','name',[obj.figName '*']);
            if isempty(f)
                f = figure('Name',obj.figName,'color','w','NumberTitle','off','visible','off');
            end
            clf(f); figure(f);
            % Height follows the trace count: a fixed 175 px was unreadable past
            % three traces and wasteful for one.
            f.Position([3 4]) = [800 max(175, min(700, 80 + 30*obj.N))];
            obj.hax = axes(f);
            obj.hax.PositionConstraint = 'outerposition'; % long names must not clip
            obj.hax.OuterPosition = [0 0 1 1];
            f.Visible = 'on';
        end

        function stay_on_top(obj,varargin)
            % Toggle window always-on-top state and update menu/label.
            obj.stayOnTop = ~obj.stayOnTop;
            c = obj.get_menu_item('uic_stayOnTop');
            if obj.stayOnTop
                c.Label = 'Do not Keep Window on Top';
            else
                c.Label = 'Keep Window on Top';
            end
            % Only rename a window this object owns. Embedded in a behavior GUI
            % the figure belongs to the paradigm, not to one plot on it.
            if obj.ownsFigure_
                if obj.stayOnTop
                    obj.figH.Name = [obj.figName ' - *On Top*'];
                else
                    obj.figH.Name = obj.figName;
                end
            end
            gui.PopOut.setAlwaysOnTop(obj.figH,obj.stayOnTop);
        end

        function plot_type(obj,src,event,toggle)
            % Toggle between trial-locked and free-running plot x-axis.
            if nargin > 1 && isequal(class(src),'logical')
                obj.trialLocked = src;
            elseif nargin == 4 && toggle
                obj.trialLocked = ~obj.trialLocked;
            end
            c = obj.get_menu_item('uic_plotType');
            atw = abs(obj.timeWindow);
            if isempty(obj.trialParam)
                vprintf(0,1,'Unable to set the plot to Trial-Locked mode because the trialParam is empty')
            elseif obj.trialLocked
                obj.timeWindow = [-min(atw) max(atw)];
                c.Label = 'Set Plot to Free-Running';
            else
                obj.timeWindow = [-max(atw) min(atw)];
                c.Label = 'Set Plot to Trial-Locked';
            end
            obj.savePreferences_;
        end

        function update_window(obj,varargin)
            % Adjust time window for plot x-axis.
            gui.PopOut.setAlwaysOnTop(obj.figH,false); % temporarily disable stay-on-top
            restore = onCleanup(@() gui.PopOut.setAlwaysOnTop(obj.figH,obj.stayOnTop));
            r = inputdlg('Adjust time window (seconds)','Online Plot', 1, {sprintf('[%.1f %.1f]',obj.timeWindow2number)});
            if isempty(r), return; end
            r = str2num(char(r)); %#ok<ST2NM>
            if numel(r) ~= 2
                vprintf(0,1,'Must enter 2 values for the time window')
                return
            end
            obj.timeWindow = seconds(sort(r(:))');
            c = obj.get_menu_item('uic_timeWindow');
            c.Label = sprintf('Time Window = [%.1f %.1f] seconds',obj.timeWindow2number);
            obj.savePreferences_;
        end

        function s = timeWindow2number(obj)
            % Numeric seconds for the duration timeWindow. This used to render
            % the duration to char and parse the number back out of it.
            s = seconds(obj.timeWindow);
        end

        function c = get_menu_item(obj,tag)
            % Find context menu item by tag.
            c = gobjects(0);
            cm = obj.hax.ContextMenu;
            if isempty(cm) || ~isvalid(cm), return; end
            C = cm.Children;
            if isempty(C), return; end
            c = C(strcmp({C.Tag},tag));
        end

        function mode_change(obj,src,event)
            % Stop h_timer if hardware mode changes.
            if event.AffectedObject.mode < 2
                stop(obj.h_timer);
            end
        end

        % ------------------------------------------------------------------
        % Operator-facing appearance changes

        function setAesthetic_(obj,prop,val)
            % Apply a menu choice, persist it, and push it onto the live plot.
            % Everything here is an ordinary public property, so a script sets
            % the same thing by assignment and calls applyStyle_ (or simply
            % waits for the next setup_plot).
            if strcmp(prop,'lineWidth') && isscalar(val)
                % The lineWidth getter PADS a short vector with 10s, so a bare
                % scalar would restyle trace 1 and reset every other trace.
                val = repmat(val,max(1,obj.N),1);
            end
            if strcmp(prop,'palette')
                obj.lineColors = zeros(0,3); % fall back to the palette getter
            end
            obj.(prop) = val;
            obj.applyStyle_;
            obj.savePreferences_;
            obj.refreshMenuChecks_;
        end

        function toggleAesthetic_(obj,prop)
            obj.setAesthetic_(prop,~obj.(prop));
        end

        function P = readableParameters_(obj,seed)
            % Every readable parameter the runtime knows, with `seed` first.
            %
            % This is the pool Select Traces... offers and the pool a saved
            % selection is checked against. It has to be wider than whatever
            % the constructor was given, or the operator could never add a
            % trace, and it has to include `seed` because a parameter the
            % paradigm named may be invisible and so absent from the filter.
            % Readable is "not write-only", NOT contains(Access,'Read'): the
            % default Access is 'Any', which reads and writes but does not
            % contain the word, so the old filter offered none of them.
            P = seed;
            try
                more = obj.RUNTIME.all_parameters();
                if ~isempty(more)
                    more = more(~strcmp({more.Access},'Write'));
                end
                if isempty(P)
                    P = more;
                elseif ~isempty(more)
                    P = [P more(~ismember({more.Name},{P.Name}))];
                end
            catch ME
                vprintf(3,'gui.OnlinePlot: could not list readable parameters: %s',ME.message)
            end
        end

        function i = traceIndex_(obj,trace)
            % Resolve a trace given by index or by name. Out of range or
            % unknown returns empty, and every caller treats that as "leave it
            % alone" -- a plot must not throw because a name went stale.
            i = [];
            if isnumeric(trace)
                if trace >= 1 && trace <= obj.N, i = round(trace); end
                return
            end
            k = find(strcmp(obj.traceNames,char(trace)),1);
            if ~isempty(k), i = k; end
        end

        function pickTraceColor_(obj,i)
            % Recolour one trace. uisetcolor returns a scalar 0 on cancel.
            c = obj.lineColors; % materialize the expanded palette first
            if i > size(c,1), return; end
            sel = uisetcolor(c(i,:), sprintf('Colour for %s', obj.traceNames{i}));
            if isscalar(sel), return; end
            c(i,:) = sel;
            obj.setAesthetic_('lineColors',c);
        end

        function resetAppearance_(obj)
            % Back to the shipped look, keeping the trace selection and order.
            obj.lineColors = zeros(0,3);
            obj.lineWidth = zeros(0,1);
            obj.palette = 'Okabe-Ito';
            obj.showGrid = true;
            obj.setZeroToNan = true;
            obj.trialMarker = true;
            obj.redrawPeriod = 0.1;
            obj.applyStyle_;
            obj.savePreferences_;
            obj.refreshMenuChecks_;
        end

        function applyStyle_(obj)
            % Push colour, width and grid onto the existing lines. Cheaper than
            % a setup_plot, and it keeps the buffered history -- restyling must
            % not blank the traces the operator is watching.
            if isempty(obj.hax) || ~isvalid(obj.hax), return; end
            onoff = {'off','on'};
            grid(obj.hax, onoff{obj.showGrid+1}); % grid() takes char, not OnOffSwitchState
            obj.hax.XMinorGrid = onoff{obj.showGrid+1};
            if isempty(obj.lineH), return; end
            c = obj.lineColors;
            w = obj.lineWidth;
            for i = 1:min(obj.N,numel(obj.lineH))
                if ~isvalid(obj.lineH(i)), continue; end
                obj.lineH(i).Color = c(i,:);
                obj.lineH(i).LineWidth = w(i);
            end
        end

        function rebuildTraceColorMenu_(obj)
            % One "Trace Colour" child per trace. Rebuilt whenever the trace
            % list changes, so it can never name a trace that has gone.
            m = obj.get_menu_item('uic_traceColors');
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);
            names = obj.traceNames;
            for i = 1:numel(names)
                uimenu(m,'Text',names{i}, ...
                    'MenuSelectedFcn',@(~,~) obj.pickTraceColor_(i));
            end
        end

        function refreshMenuChecks_(obj)
            % Sync menu check marks with the current property values.
            cm = obj.ContextMenuH_;
            if isempty(cm) || ~isvalid(cm), return; end
            items = findall(cm,'Type','uimenu');
            for k = 1:numel(items)
                t = items(k).Tag;
                if startsWith(t,'aes|')
                    p = strsplit(t,'|');
                    cur = obj.(p{2});
                    if isnumeric(cur), cur = num2str(cur(1),'%g'); end
                    items(k).Checked = matlab.lang.OnOffSwitchState(strcmp(cur,p{3}));
                elseif startsWith(t,'tgl|')
                    p = strsplit(t,'|');
                    items(k).Checked = matlab.lang.OnOffSwitchState(logical(obj.(p{2})));
                end
            end
            c = obj.get_menu_item('uic_timeWindow');
            if ~isempty(c) && isvalid(c)
                c.Label = sprintf('Time Window = [%.1f %.1f] seconds',obj.timeWindow2number);
            end
        end

        function c = popOutHostContainer_(obj)
            % Container this plot was built into, for gui.PopOut preference
            % scoping. It is the axes' parent rather than the figure, so an
            % embedded plot is scoped by the behavior GUI that hosts it.
            c = [];
            if ~isempty(obj.hax) && isvalid(obj.hax), c = obj.hax.Parent; end
        end

        function n = preferenceName_(obj)
            % Preference key scoped to the hosting GUI: explicit tag, else the
            % ancestor figure Tag, else its Name, else the box. Matches how
            % every other component in this toolbox scopes saved settings.
            n = obj.PreferenceTag_;
            if isempty(n)
                try
                    f = ancestor(obj.hax,'figure');
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
            if isempty(n), n = sprintf('Box%d',obj.BoxID); end
            n = matlab.lang.makeValidName(n);
        end
    end

    % Methods held in their own files in this @-folder.
    methods
        setWatched(obj,source)          % replace the plotted traces
        setTraceOrder(obj,order)        % permute the traces bottom-to-top
        names = traceNames(obj)         % current trace labels, bottom-to-top
        selectTraces(obj,varargin)      % operator dialog behind setWatched
        reorderTraces(obj,varargin)     % operator dialog behind setTraceOrder
    end

    methods (Access = protected)
        buildContextMenu_(obj)
        loadPreferences_(obj,hasExplicitSource)
        savePreferences_(obj)
        h = createPopOut_(obj,container)
    end
end
