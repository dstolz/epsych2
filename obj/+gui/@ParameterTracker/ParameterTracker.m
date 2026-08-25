classdef ParameterTracker < handle
    % gui.ParameterTracker
    % obj = gui.ParameterTracker(parameters)
    % obj = gui.ParameterTracker(parameters, Name=Value)
    % Plot the value of one or more hw.Parameter objects against time, live.
    %
    % Opened from gui.ParameterDebugger ("Track Selected", Ctrl+T), this is the
    % answer to "is that value moving, and when does it move?" -- a question a
    % table of numbers cannot answer. Each tracked parameter becomes one line
    % in its own colour against seconds since tracking started.
    %
    % This window POLLS, which is the one thing gui.ParameterDebugger promises
    % never to do. That is the whole point of it, and it is why polling lives
    % here in a window the operator opened on purpose and can close: reading a
    % parameter at 5 Hz puts traffic on the same bus the experiment is using,
    % so the rate is adjustable and the plot is paused, not silently running,
    % whenever nothing is tracked.
    %
    % Only scalar numeric and boolean parameters can be tracked. A buffer has
    % no single value to plot, a string has no position on an axis, and a
    % write-only parameter cannot be read at all; those are refused at the
    % point of adding rather than drawn as gaps. A read that fails, or that
    % comes back non-scalar, is recorded as NaN -- the line breaks, which is an
    % honest picture of a backend that stopped answering.
    %
    % Properties:
    %   Parameters - hw.Parameter objects being tracked, in plot order
    %   Time       - Sample times, seconds since tracking started
    %   Values     - numel(Parameters)-by-numel(Time) matrix of readings
    %   Rate       - Reads per second
    %   IsRunning  - True while the poll timer is running
    %   H          - Graphics handles
    %
    % Methods:
    %   addParameters    - Track more parameters
    %   removeParameters - Stop tracking some
    %   start / stop     - Run or pause the poll timer
    %   clearData        - Throw away the samples and restart the clock
    %   data             - Everything recorded so far, as a struct
    %
    % Examples:
    %   gui.ParameterTracker(RUNTIME.Interfaces(1).Module(1).Parameters(1))
    %   t = gui.ParameterTracker(P, Rate=10, Available=allParams);
    %   S = t.data;   % S.Time, S.Values, S.Names
    %
    % See also: documentation/gui/gui_ParameterTracker.md,
    %   gui.ParameterDebugger, gui.components.Parameter_Monitor, hw.Parameter

    properties (SetAccess = private)
        Parameters = hw.Parameter.empty(1,0)  % tracked parameters, in plot order
        H = struct()                          % graphics handles
    end

    properties (Dependent)
        Time        % 1-by-N sample times, seconds since tracking started
        Values      % numel(Parameters)-by-N readings, NaN where a read failed
        IsRunning   % true while the poll timer is running
        Rate        % reads per second
    end

    properties (Constant)
        % Types with a single number to plot. Everything else is refused when
        % it is added, so the plot never carries a line that cannot move.
        TRACKABLE_TYPES = {'Float','Integer','Boolean','Undefined'}

        DEFAULT_RATE (1,1) double = 5      % Hz
        MIN_RATE     (1,1) double = 0.1
        MAX_RATE     (1,1) double = 20
    end

    properties (Constant, Access = private)
        FIGURE_TAG (1,:) char = 'EPsychParameterTracker'
        PREF_TAG   (1,:) char = 'epsych2_gui_ParameterTracker'
        DEFAULT_POSITION (1,4) double = [140 140 980 540]

        % Samples kept before the oldest half is dropped. At 5 Hz this is
        % about eleven hours, and dropping half at a time means the shift
        % happens once per five and a half hours rather than once per sample.
        MAX_SAMPLES (1,1) double = 200000

        % Seconds of history the x-axis shows, per entry of the Window list.
        WINDOW_LABELS = {'30 s', '2 min', '10 min', '1 hour', 'All'}
        WINDOW_SECONDS = [30, 120, 600, 3600, Inf]
    end

    properties (Access = private)
        Available_ = hw.Parameter.empty(1,0)  % what the Add list offers
        Labels_ = {}                          % one display name per tracked parameter
        Colors_ = zeros(0,3)                  % one colour per tracked parameter
        Lines_ = gobjects(1,0)                % one line per tracked parameter

        Timer_ = []                           % the poll timer, owned by this object
        T0_ (1,1) uint64 = uint64(0)          % tic reference for the time axis
        Elapsed_ (1,1) double = 0             % seconds accumulated before the last pause

        T_ = zeros(1,0)                       % sample times, preallocated
        Y_ = zeros(0,0)                       % readings, parameters by samples
        N_ (1,1) double = 0                   % samples actually used
        Dropped_ (1,1) double = 0             % samples discarded to the cap

        LastError_ = {}                       % last message logged per parameter
        Rate_ (1,1) double = 5
    end

    methods
        function self = ParameterTracker(parameters, options)
            % obj = gui.ParameterTracker(parameters)
            % obj = gui.ParameterTracker(parameters, Name=Value)
            % Open a live plot of one or more parameters.
            %
            % Parameters:
            %   parameters        - hw.Parameter array to track. Untrackable
            %                       entries are dropped with a message rather
            %                       than refused outright, so a selection that
            %                       happens to include a buffer still opens.
            %   options.Available - hw.Parameter array the Add list offers.
            %                       Defaults to the tracked ones.
            %   options.Rate      - Reads per second (default 5).
            %   options.Start     - Begin polling immediately (default true).
            %   options.Visible   - Show the window (default true).
            %
            % Returns:
            %   self - gui.ParameterTracker instance.
            arguments
                parameters = hw.Parameter.empty(1,0)
                options.Available = hw.Parameter.empty(1,0)
                options.Rate (1,1) double {mustBePositive} = gui.ParameterTracker.DEFAULT_RATE
                options.Start (1,1) logical = true
                options.Visible (1,1) logical = true
            end

            self.Rate_ = min(max(options.Rate, self.MIN_RATE), self.MAX_RATE);
            self.Available_ = options.Available(:)';
            if isempty(self.Available_)
                self.Available_ = parameters(:)';
            end

            self.buildUI(options.Visible);
            self.addParameters(parameters);

            if options.Start
                self.start();
            else
                self.updateControls_();
            end

            if nargout == 0
                clear self
            end
        end

        function delete(self)
            % delete(self)
            % Stop the timer and tear down the window, saving its position.
            %
            % The timer is stopped first and unconditionally: a poll firing
            % into a half-deleted object is the one failure mode a window that
            % owns a timer has, and it would land in the timer's error
            % callback rather than anywhere the operator would look.
            try
                self.stopTimer_();
            catch ME
                vprintf(2, ME);
            end

            try
                if isfield(self.H,'figure') && isgraphics(self.H.figure)
                    gui.BehaviorGUI.saveFigurePosition(self.PREF_TAG, self.H.figure.Position);
                    self.H.figure.UserData = [];
                    self.H.figure.CloseRequestFcn = '';
                    delete(self.H.figure);
                end
            catch ME
                vprintf(2, ME);
            end
        end

        function t = get.Time(self)
            t = self.T_(1:self.N_);
        end

        function y = get.Values(self)
            y = self.Y_(:, 1:self.N_);
        end

        function tf = get.IsRunning(self)
            tf = ~isempty(self.Timer_) && isvalid(self.Timer_) && ...
                strcmp(self.Timer_.Running, 'on');
        end

        function r = get.Rate(self)
            r = self.Rate_;
        end

        function addParameters(self, P)
            % addParameters(self, P)
            % Track more parameters. Anything already tracked, deleted, or not
            % scalar-valued is skipped, and the reason is put on the status
            % line: silently ignoring half a selection is how an operator ends
            % up watching a plot that is missing the parameter they cared
            % about.
            arguments
                self
                P = hw.Parameter.empty(1,0)
            end

            P = P(:)';
            added = 0;
            refused = {};

            for i = 1:numel(P)
                if ~isvalid(P(i)), continue, end
                if ~isempty(self.Parameters) && any(self.Parameters == P(i)), continue, end

                [ok, why] = gui.ParameterTracker.isTrackable(P(i));
                if ~ok
                    refused{end+1} = sprintf('%s (%s)', P(i).Name, why);
                    continue
                end

                self.Parameters(end+1) = P(i);
                self.Labels_{end+1} = gui.ParameterTracker.labelFor(P(i));
                self.LastError_{end+1} = '';
                self.Colors_(end+1,:) = self.nextColor_();

                % Existing samples predate this parameter, so its history is
                % NaN rather than zero: the line starts where tracking of it
                % started, which is the truth about what was measured.
                self.Y_(end+1, :) = nan(1, size(self.Y_, 2));
                added = added + 1;
            end

            if added > 0
                self.rebuildLines_();
            end
            self.updateControls_();
            self.redraw_();

            if ~isempty(refused)
                self.setStatus_(sprintf('Not tracked: %s', strjoin(refused, ', ')));
            elseif added > 0
                self.setStatus_(sprintf('Tracking %d parameter(s).', numel(self.Parameters)));
            end
        end

        function removeParameters(self, which)
            % removeParameters(self, which)
            % Stop tracking, by index into Parameters or by hw.Parameter.
            %
            % The samples of the removed parameter go with it. Keeping them
            % would mean a plot whose data no longer matches its legend, and
            % the recording is the plot -- there is nothing else holding it.
            arguments
                self
                which
            end

            if isa(which, 'hw.Parameter')
                idx = find(ismember(self.Parameters, which));
            else
                idx = which(:)';
            end
            idx = idx(idx >= 1 & idx <= numel(self.Parameters));
            if isempty(idx), return, end

            keep = setdiff(1:numel(self.Parameters), idx);
            self.Parameters = self.Parameters(keep);
            self.Labels_ = self.Labels_(keep);
            self.LastError_ = self.LastError_(keep);
            self.Colors_ = self.Colors_(keep, :);
            self.Y_ = self.Y_(keep, :);

            self.rebuildLines_();
            self.updateControls_();
            self.redraw_();
            self.setStatus_(sprintf('Tracking %d parameter(s).', numel(self.Parameters)));
        end

        function start(self)
            % start(self)
            % Begin (or resume) polling. The clock keeps its elapsed time
            % across a pause, so pausing to look at a trace does not put a
            % discontinuity in the time axis of what follows.
            if isempty(self.Parameters)
                self.setStatus_('Nothing to track yet -- add a parameter first.');
                self.updateControls_();
                return
            end

            if self.IsRunning, return, end

            self.ensureTimer_();
            self.T0_ = tic;
            start(self.Timer_);
            self.updateControls_();
            self.setStatus_(sprintf('Reading %d parameter(s) at %.4g Hz.', ...
                numel(self.Parameters), self.Rate_));
        end

        function stop(self)
            % stop(self)
            % Pause polling, keeping everything recorded so far.
            if ~self.IsRunning, return, end
            self.Elapsed_ = self.now_();
            self.stopTimer_();
            self.updateControls_();
            self.setStatus_(sprintf('Paused at %.1f s, %d sample(s).', self.Elapsed_, self.N_));
        end

        function clearData(self)
            % clearData(self)
            % Throw away every sample and restart the time axis at zero.
            self.T_ = zeros(1,0);
            self.Y_ = zeros(numel(self.Parameters), 0);
            self.N_ = 0;
            self.Dropped_ = 0;
            self.Elapsed_ = 0;
            self.T0_ = tic;
            self.redraw_();
            self.setStatus_('Cleared.');
        end

        function S = data(self)
            % S = data(self)
            % Everything recorded so far: S.Time (1-by-N seconds), S.Values
            % (parameters-by-N), S.Names, S.Rate. NaN marks a sample that
            % could not be read.
            S = struct( ...
                'Time',   self.Time, ...
                'Values', self.Values, ...
                'Names',  {self.Labels_}, ...
                'Rate',   self.Rate_);
        end
    end

    methods (Static)
        function [tf, why] = isTrackable(P)
            % [tf, why] = gui.ParameterTracker.isTrackable(P)
            % Whether a parameter has a single number that can be plotted, and
            % if not, the short reason to put in front of the operator.
            tf = false;
            why = '';

            if ~isa(P,'hw.Parameter') || ~isvalid(P)
                why = 'not a parameter';
                return
            end
            if strcmp(P.Access, 'Write')
                why = 'write-only';
                return
            end
            if ~ismember(P.Type, gui.ParameterTracker.TRACKABLE_TYPES)
                why = lower(P.Type);
                return
            end
            tf = true;
        end

        function txt = labelFor(P)
            % txt = gui.ParameterTracker.labelFor(P)
            % Legend text for a parameter: "Module.Name", falling back to the
            % bare name when the parameter has no module to name it by.
            txt = '';
            if ~isa(P,'hw.Parameter') || ~isvalid(P), return, end
            try
                txt = char(P.FullName);
            catch
                txt = '';
            end
            if isempty(txt)
                txt = char(P.Name);
            end
        end
    end

    % ---- Construction ------------------------------------------------------
    methods (Access = private)
        function buildUI(self, visible)
            % The plot is the window; the strip above it controls the poll and
            % the panel beside it controls what is polled.
            pos = gui.BehaviorGUI.getSavedFigurePosition(self.PREF_TAG, self.DEFAULT_POSITION);

            f = uifigure('Name','EPsych Parameter Tracker', 'Tag', self.FIGURE_TAG, ...
                'Position', pos, ...
                'Visible', matlab.lang.OnOffSwitchState(visible), ...
                'WindowKeyPressFcn', @(~,evt) self.onKeyPress_(evt));
            f.UserData = self;
            f.CloseRequestFcn = @(~,~) delete(self);
            movegui(f, 'onscreen');
            self.H.figure = f;

            g = uigridlayout(f, [3 2]);
            g.RowHeight = {'fit', '1x', 22};
            g.ColumnWidth = {'1x', 240};
            g.Padding = [10 8 10 8];
            g.RowSpacing = 8;

            % ---------- Control strip ---------------------------------------
            gTop = uigridlayout(g, [1 8]);
            gTop.Layout.Row = 1;
            gTop.Layout.Column = [1 2];
            gTop.RowHeight = {24};
            gTop.ColumnWidth = {90, 60, 60, 40, 70, 110, 90, '1x'};
            gTop.ColumnSpacing = 8;
            gTop.Padding = [0 0 0 0];

            self.H.btnRun = uibutton(gTop, 'state', 'Text','Start', 'Value', false, ...
                'Tooltip','Start or pause reading (Space)', ...
                'ValueChangedFcn', @(src,~) self.onRunToggled_(src.Value));
            self.H.btnRun.Layout.Column = 1;

            lbl = uilabel(gTop, 'Text','Rate:', 'HorizontalAlignment','right');
            lbl.Layout.Column = 2;

            self.H.rate = uieditfield(gTop, 'numeric', 'Value', self.Rate_, ...
                'Limits', [self.MIN_RATE self.MAX_RATE], ...
                'ValueDisplayFormat','%.4g', ...
                'Tooltip', ['Reads per second. Every read is bus traffic the ' ...
                            'experiment is also using, so keep it as slow as ' ...
                            'the question allows.'], ...
                'ValueChangedFcn', @(src,~) self.onRateChanged_(src.Value));
            self.H.rate.Layout.Column = 3;

            lbl = uilabel(gTop, 'Text','Hz');
            lbl.Layout.Column = 4;

            lbl = uilabel(gTop, 'Text','Show:', 'HorizontalAlignment','right');
            lbl.Layout.Column = 5;

            self.H.window = uidropdown(gTop, 'Items', self.WINDOW_LABELS, ...
                'Value', self.WINDOW_LABELS{1}, ...
                'Tooltip','How much history the time axis shows.', ...
                'ValueChangedFcn', @(~,~) self.redraw_());
            self.H.window.Layout.Column = 6;

            self.H.btnClear = uibutton(gTop, 'Text','Clear', ...
                'Tooltip','Discard the samples and restart the clock', ...
                'ButtonPushedFcn', @(~,~) self.clearData());
            self.H.btnClear.Layout.Column = 7;

            self.H.count = uilabel(gTop, 'Text','', ...
                'HorizontalAlignment','right', 'FontColor',[0.35 0.38 0.42]);
            self.H.count.Layout.Column = 8;

            % ---------- Plot ------------------------------------------------
            ax = uiaxes(g);
            ax.Layout.Row = 2;
            ax.Layout.Column = 1;
            xlabel(ax, 'Time since tracking started (s)');
            ylabel(ax, 'Value');
            grid(ax, 'on');
            ax.XLim = [0 self.windowSeconds_()];
            self.H.axes = ax;

            cm = uicontextmenu(f);
            uimenu(cm, 'Text','Assign Data to Command Window', ...
                'MenuSelectedFcn', @(~,~) self.assignToBase());
            uimenu(cm, 'Text','Clear', ...
                'MenuSelectedFcn', @(~,~) self.clearData());
            ax.ContextMenu = cm;

            % ---------- Parameter panel --------------------------------------
            p = uipanel(g, 'Title','Tracked');
            p.Layout.Row = 2;
            p.Layout.Column = 2;

            gp = uigridlayout(p, [4 2]);
            gp.RowHeight = {'1x', 24, 'fit', 24};
            gp.ColumnWidth = {'1x', 60};
            gp.Padding = [6 6 6 6];
            gp.RowSpacing = 6;

            self.H.list = uilistbox(gp, 'Items', {}, 'Multiselect','on', ...
                'Tooltip','Select and Remove to stop tracking.');
            self.H.list.Layout.Row = 1;
            self.H.list.Layout.Column = [1 2];

            self.H.btnRemove = uibutton(gp, 'Text','Remove', ...
                'Tooltip','Stop tracking the selected parameters (Delete)', ...
                'ButtonPushedFcn', @(~,~) self.onRemove_());
            self.H.btnRemove.Layout.Row = 2;
            self.H.btnRemove.Layout.Column = [1 2];

            self.H.add = uidropdown(gp, 'Items', {'(nothing to add)'}, ...
                'Tooltip','Scalar parameters this window was given to choose from.');
            self.H.add.Layout.Row = 3;
            self.H.add.Layout.Column = [1 2];

            self.H.btnAdd = uibutton(gp, 'Text','Add', ...
                'ButtonPushedFcn', @(~,~) self.onAdd_());
            self.H.btnAdd.Layout.Row = 4;
            self.H.btnAdd.Layout.Column = [1 2];

            % ---------- Status ------------------------------------------------
            self.H.status = uilabel(g, 'Text','');
            self.H.status.Layout.Row = 3;
            self.H.status.Layout.Column = [1 2];
        end
    end

    % ---- Polling -----------------------------------------------------------
    methods (Access = private)
        function ensureTimer_(self)
            % One timer, made on first use and reused across pauses.
            %
            % ErrorFcn is set because a timer callback that throws stops the
            % timer silently: without it, a plot would simply stop moving with
            % nothing said about why.
            if ~isempty(self.Timer_) && isvalid(self.Timer_)
                self.Timer_.Period = self.period_();
                return
            end

            self.Timer_ = timer( ...
                'Name', 'EPsychParameterTracker', ...
                'ExecutionMode', 'fixedSpacing', ...
                'BusyMode', 'drop', ...
                'Period', self.period_(), ...
                'TimerFcn', @(~,~) self.tick_(), ...
                'ErrorFcn', @(~,evt) self.onTimerError_(evt));
        end

        function stopTimer_(self)
            % Stop and destroy this window's own timer. Nothing else in the
            % session is touched: timerfindall would also find the runtime's.
            if isempty(self.Timer_) || ~isvalid(self.Timer_), return, end
            if strcmp(self.Timer_.Running, 'on')
                stop(self.Timer_);
            end
            delete(self.Timer_);
            self.Timer_ = [];
        end

        function p = period_(self)
            % Timer periods are quantised to milliseconds, so the rate the
            % operator typed and the rate actually delivered can differ; the
            % delivered one is what the samples carry, since every sample is
            % stamped with the clock rather than with its index.
            p = round(1 / self.Rate_, 3);
            p = max(p, 0.001);
        end

        function t = now_(self)
            % Seconds since tracking started, across pauses. While paused the
            % clock stands still, so a plot left alone for ten minutes does not
            % come back with a ten-minute gap drawn through it.
            if ~self.IsRunning || self.T0_ == 0
                t = self.Elapsed_;
                return
            end
            t = self.Elapsed_ + toc(self.T0_);
        end

        function tick_(self)
            % One poll: read every tracked parameter, store, redraw.
            if ~isvalid(self) || isempty(self.Parameters), return, end
            if ~isfield(self.H,'figure') || ~isgraphics(self.H.figure)
                self.stopTimer_();
                return
            end

            t = self.now_();
            v = nan(numel(self.Parameters), 1);
            for i = 1:numel(self.Parameters)
                v(i) = self.readOne_(i);
            end

            % A read can take milliseconds per parameter, which is long enough
            % for the operator to have closed the window meanwhile.
            if ~isvalid(self) || ~isgraphics(self.H.figure), return, end

            self.append_(t, v);
            self.redraw_();
        end

        function v = readOne_(self, i)
            % One reading, as a double, or NaN with the reason logged once.
            %
            % Logging only when the message CHANGES is the difference between
            % a note in the log and five records per second for as long as a
            % disconnected rig stays disconnected.
            v = NaN;
            P = self.Parameters(i);

            if ~isvalid(P)
                self.noteOnce_(i, 'the parameter no longer exists');
                return
            end

            try
                raw = P.Value;
            catch ME
                self.noteOnce_(i, ME.message);
                return
            end

            if (isnumeric(raw) || islogical(raw)) && isscalar(raw)
                v = double(raw);
                self.LastError_{i} = '';
                return
            end

            self.noteOnce_(i, 'value is not a scalar number');
        end

        function noteOnce_(self, i, msg)
            if isequal(self.LastError_{i}, msg), return, end
            self.LastError_{i} = msg;
            vprintf(1, 'gui.ParameterTracker: "%s" not read: %s', self.Labels_{i}, msg);
            self.setStatus_(sprintf('%s: %s', self.Labels_{i}, msg));
        end

        function append_(self, t, v)
            % Store one sample, growing the buffers by doubling.
            %
            % Preallocated rather than appended per sample: at 5 Hz for an
            % hour this is eighteen thousand appends, and growing an array by
            % one element that many times copies it every time.
            if self.N_ >= size(self.Y_, 2)
                oldCap = size(self.Y_, 2);
                newCap = max(1024, 2 * oldCap);
                self.T_(1, newCap) = 0;
                self.Y_ = [self.Y_, nan(size(self.Y_,1), newCap - oldCap)];
            end

            self.N_ = self.N_ + 1;
            self.T_(self.N_) = t;
            self.Y_(:, self.N_) = v;

            if self.N_ >= self.MAX_SAMPLES
                keepFrom = floor(self.N_/2) + 1;
                n = self.N_ - keepFrom + 1;
                self.T_(1:n) = self.T_(keepFrom:self.N_);
                self.Y_(:, 1:n) = self.Y_(:, keepFrom:self.N_);
                self.Dropped_ = self.Dropped_ + keepFrom - 1;
                self.N_ = n;
                vprintf(2, 'gui.ParameterTracker: sample cap reached; dropped the oldest %d', ...
                    keepFrom - 1);
            end
        end

        function onTimerError_(self, evt)
            % A throw inside the timer callback stops the timer, so say so.
            vprintf(0, 1, 'gui.ParameterTracker: polling stopped: %s', ...
                gui.ParameterTracker.errorText_(evt));
            if isvalid(self)
                self.updateControls_();
                self.setStatus_('Polling stopped after an error -- see the log.');
            end
        end
    end

    % ---- Display -----------------------------------------------------------
    methods (Access = private)
        function rebuildLines_(self)
            % One line per tracked parameter, rebuilt whenever the set changes.
            delete(self.Lines_(isgraphics(self.Lines_)));
            self.Lines_ = gobjects(1, numel(self.Parameters));

            ax = self.H.axes;
            washold = ishold(ax);
            hold(ax, 'on');
            for i = 1:numel(self.Parameters)
                self.Lines_(i) = plot(ax, NaN, NaN, ...
                    'Color', self.Colors_(i,:), 'LineWidth', 1.25);
            end
            if ~washold, hold(ax, 'off'); end

            if isempty(self.Parameters)
                legend(ax, 'off');
            else
                legend(ax, self.Lines_, self.Labels_, ...
                    'Location','northeastoutside', 'AutoUpdate','off', ...
                    'Interpreter','none');
            end

            self.H.list.Items = self.Labels_;
        end

        function redraw_(self)
            % Push the samples into the lines and set the time axis.
            if ~isfield(self.H,'axes') || ~isgraphics(self.H.axes), return, end

            n = self.N_;
            for i = 1:numel(self.Lines_)
                if ~isgraphics(self.Lines_(i)), continue, end
                if n == 0
                    set(self.Lines_(i), 'XData', NaN, 'YData', NaN);
                else
                    set(self.Lines_(i), 'XData', self.T_(1:n), 'YData', self.Y_(i, 1:n));
                end
            end

            % The window slides with the newest sample, so the trace runs off
            % the right edge rather than compressing as the session grows.
            span = self.windowSeconds_();
            tNow = 0;
            if n > 0, tNow = self.T_(n); end
            if isinf(span)
                self.H.axes.XLim = [0 max(tNow, 1)];
            else
                self.H.axes.XLim = [max(0, tNow - span), max(span, tNow)];
            end

            self.updateCount_();
        end

        function s = windowSeconds_(self)
            s = self.WINDOW_SECONDS(1);
            if ~isfield(self.H,'window') || ~isgraphics(self.H.window), return, end
            hit = find(strcmp(self.WINDOW_LABELS, self.H.window.Value), 1);
            if ~isempty(hit), s = self.WINDOW_SECONDS(hit); end
        end

        function c = nextColor_(self)
            % Colours are assigned per parameter rather than by position, so
            % removing one line does not recolour the others under the
            % operator while they are watching them.
            palette = lines(7);
            used = self.Colors_;
            for k = 1:size(palette,1)
                if isempty(used) || ~any(all(abs(used - palette(k,:)) < 1e-6, 2))
                    c = palette(k,:);
                    return
                end
            end
            c = palette(mod(size(used,1), size(palette,1)) + 1, :);
        end

        function updateCount_(self)
            if ~isfield(self.H,'count') || ~isgraphics(self.H.count), return, end
            if self.N_ == 0
                self.H.count.Text = '';
                return
            end
            txt = sprintf('%d sample(s)  |  %.1f s', self.N_, self.T_(self.N_));
            if self.Dropped_ > 0
                txt = sprintf('%s  |  %d dropped', txt, self.Dropped_);
            end
            self.H.count.Text = txt;
        end

        function updateControls_(self)
            % One boolean per action, copied to every surface that offers it.
            onoff = @(tf) matlab.lang.OnOffSwitchState(tf);
            running = self.IsRunning;

            self.H.btnRun.Value = running;
            if running
                self.H.btnRun.Text = 'Pause';
            else
                self.H.btnRun.Text = 'Start';
            end
            self.H.btnRun.Enable = onoff(~isempty(self.Parameters));
            self.H.btnRemove.Enable = onoff(~isempty(self.Parameters));

            avail = self.addableLabels_();
            if isempty(avail)
                self.H.add.Items = {'(nothing to add)'};
                self.H.add.Enable = 'off';
                self.H.btnAdd.Enable = 'off';
            else
                self.H.add.Items = avail;
                self.H.add.Enable = 'on';
                self.H.btnAdd.Enable = 'on';
            end
        end

        function labels = addableLabels_(self)
            % What the Add list offers: everything trackable it was given that
            % is not on the plot already.
            labels = {};
            for i = 1:numel(self.Available_)
                P = self.Available_(i);
                if ~isvalid(P), continue, end
                if ~isempty(self.Parameters) && any(self.Parameters == P), continue, end
                if ~gui.ParameterTracker.isTrackable(P), continue, end
                labels{end+1} = gui.ParameterTracker.labelFor(P);
            end
            labels = unique(labels, 'stable');
        end

        function setStatus_(self, msg)
            if isfield(self.H,'status') && isgraphics(self.H.status)
                self.H.status.Text = msg;
            end
        end
    end

    % ---- Callbacks ---------------------------------------------------------
    methods (Access = private)
        function onRunToggled_(self, wantRunning)
            if wantRunning
                self.start();
            else
                self.stop();
            end
        end

        function onRateChanged_(self, value)
            self.Rate_ = min(max(value, self.MIN_RATE), self.MAX_RATE);
            self.H.rate.Value = self.Rate_;

            % A period change needs the timer stopped, so a rate change while
            % running is a stop and a start -- the elapsed clock carries over,
            % so the trace is continuous across it.
            if self.IsRunning
                self.stop();
                self.start();
            end
        end

        function onAdd_(self)
            label = char(self.H.add.Value);
            hit = [];
            for i = 1:numel(self.Available_)
                if ~isvalid(self.Available_(i)), continue, end
                if strcmp(gui.ParameterTracker.labelFor(self.Available_(i)), label)
                    hit = i;
                    break
                end
            end
            if isempty(hit), return, end
            self.addParameters(self.Available_(hit));
        end

        function onRemove_(self)
            sel = string(self.H.list.Value);
            if isempty(sel), return, end
            idx = find(ismember(string(self.Labels_), sel));
            self.removeParameters(idx);
        end

        function onKeyPress_(self, evt)
            switch evt.Key
                case 'space'
                    if self.IsRunning, self.stop(); else, self.start(); end
                case 'delete'
                    self.onRemove_();
                case 'escape'
                    delete(self);
            end
        end
    end

    methods
        function assignToBase(self)
            % assignToBase(self)
            % Put everything recorded into the base workspace as PT, for the
            % analysis the plot is only the first look at.
            S = self.data();
            assignin('base', 'PT', S);
            self.setStatus_(sprintf(['PT assigned in the command window: ' ...
                '%d parameter(s), %d sample(s).'], numel(self.Parameters), self.N_));
        end
    end

    methods (Static, Access = private)
        function txt = errorText_(evt)
            % The message out of a timer ErrorFcn event, whatever shape it
            % arrives in.
            txt = 'unknown error';
            try
                if isfield(evt, 'Data') && isfield(evt.Data, 'message')
                    txt = evt.Data.message;
                elseif isprop(evt, 'Data')
                    txt = char(string(evt.Data.message));
                end
            catch
            end
        end
    end
end
