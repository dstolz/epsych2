classdef MetricsExplorer < handle
    % gui.MetricsExplorer
    % obj = gui.MetricsExplorer()
    % obj = gui.MetricsExplorer(Name=Value)
    % Map one signal-detection metric over the whole hit-rate/false-alarm plane.
    %
    % The question this window answers comes up whenever a session reports a
    % surprising number: what does this metric actually DO between rates of 0
    % and 1? Pick a metric and its value is drawn at every pair of rates, with
    % contour lines at round levels, a heavy black line where the metric takes
    % its neutral value -- chance for a sensitivity index, unbiased for a bias
    % index -- and a readout of every metric at the point clicked.
    %
    % It computes nothing of its own. Every surface and every number in the
    % readout is psychophysics.Metrics, called with the rates on the grid, so
    % this is a picture OF the arithmetic the toolbox runs rather than a second
    % implementation that could drift from it. Adding a metric means adding a
    % catalog entry that names a Metrics method; there is no formula here.
    %
    % Four decisions a reader would otherwise have to re-derive:
    %
    %   The correction for rates of 0 and 1 is a CONTROL, not a default. The
    %   interesting part of this plane is its edges, and z(0)/z(1) are -Inf and
    %   +Inf: which finite number appears there is a scientific choice, so it
    %   is named on the window exactly as psychophysics.Metrics names it at
    %   every call. A' and B'' are defined at 0 and 1 and take no correction at
    %   all (correcting them would only bias them toward chance), so choosing
    %   one greys those controls out and the status line says why, rather than
    %   leaving a setting on screen that the picture is ignoring.
    %
    %   Colour limits are SYMMETRIC about the metric's neutral value, so white
    %   always means chance or no bias and the two poles always mean the same
    %   thing. Only the half-width is adjustable, which is what keeps the
    %   colour scale from ever being centred somewhere that means nothing; when
    %   values run past it the end tick labels say so with a <= or a >=, since
    %   a clipped scale that does not admit it is a lie about the data.
    %
    %   Infinite values (an uncorrected edge, or c' where d' = 0) are LEFT
    %   infinite. They saturate the colour scale, which is what they mean, and
    %   they are dropped only from the contour input, where a level crossing at
    %   infinity is meaningless. NaN renders as the axes background.
    %
    %   The window is a reference, not a session tool: no runtime, no hardware,
    %   no listeners. It is safe to leave open beside a running experiment
    %   because there is nothing for it to poll.
    %
    % Properties (read-only; use the setters):
    %   Metric          - Key of the displayed metric
    %   HitRate         - Probe hit rate
    %   FalseAlarmRate  - Probe false alarm rate
    %   Correction      - "none", "clamp", "halfcell", or "loglinear"
    %   Bounds          - [lo hi] for "clamp"
    %   NSignal, NNoise - Trial counts the N-dependent corrections use
    %   H               - Graphics handles
    %
    % Methods:
    %   setMetric   - Show a different metric
    %   setPoint    - Move the probe to (hit rate, false alarm rate)
    %   values      - Every metric at the probe point, as a struct
    %   surface     - The displayed surface and its rate vectors
    %
    % Static:
    %   catalog      - The metrics this window offers, as a struct array
    %   metric       - One catalog entry by key
    %   citations    - The works the explanations cite, with their DOIs
    %   evaluate     - One metric over any rates, the way this window computes it
    %   formatValue  - One value as readout text
    %   divergingMap - The blue-white-red colormap the map is drawn in
    %   openGuide    - The wiki page for this window, in the system browser
    %
    % Examples:
    %   gui.MetricsExplorer
    %   gui.MetricsExplorer(Metric="criterion", HitRate=0.635, FalseAlarmRate=0.738)
    %   S = gui.MetricsExplorer.evaluate("dprime", 0.8, 0.2, Correction="none");
    %
    % See also: documentation/gui/gui_MetricsExplorer.md, psychophysics.Metrics,
    %   psychophysics.SessionMetrics, gui.components.SessionPerformance,
    %   https://github.com/dstolz/epsych2/wiki/Metrics-Explorer

    properties (SetAccess = private)
        H = struct()    % graphics handles
    end

    properties (Dependent)
        Metric          % key of the displayed metric
        HitRate         % probe hit rate
        FalseAlarmRate  % probe false alarm rate
        Correction      % correction applied to rates of 0 and 1
        Bounds          % [lo hi] used by the "clamp" correction
        NSignal         % signal trials behind the hit rate
        NNoise          % catch trials behind the false alarm rate
    end

    properties (Constant)
        FIGURE_TAG (1,:) char = 'EPsychMetricsExplorer'
        WIKI_URL (1,:) char = 'https://github.com/dstolz/epsych2/wiki/Metrics-Explorer'
    end

    properties (Constant, Access = private)
        PREF_TAG (1,:) char = 'epsych2_gui_MetricsExplorer'
        DEFAULT_POSITION (1,4) double = [110 110 1180 700]

        % Rates per axis. Odd, so 0.5 and every tenth land exactly on a grid
        % point and the map is symmetric about its own centre.
        GRID_N (1,1) double = 201

        CORRECTIONS = {'none','clamp','halfcell','loglinear'}

        LABEL_COLOR (1,3) double = [0.42 0.45 0.50]
        VALUE_COLOR (1,3) double = [0.15 0.17 0.20]
        ACCENT_COLOR (1,3) double = [0.00 0.35 0.62]
    end

    properties (Access = private)
        Metric_ (1,1) string = "dprime"
        HitRate_ (1,1) double = 0.8
        FalseAlarm_ (1,1) double = 0.2
        Correction_ (1,1) string = "clamp"
        Bounds_ (1,2) double = [0.01 0.99]
        NSignal_ (1,1) double = 100
        NNoise_ (1,1) double = 100
        Range_ (1,1) double = 4        % colour half-width about the neutral value
        ShowContours_ (1,1) logical = true

        Fvec_ (1,:) double = []        % false alarm rates, the x grid
        Hvec_ (1,:) double = []        % hit rates, the y grid
        Z_ = []                        % the displayed surface
        Contours_ = gobjects(1,0)      % contour objects, remade on every refresh
        ValueLabels_ = gobjects(1,0)   % one readout label per catalog entry
    end

    methods
        function self = MetricsExplorer(options)
            % obj = gui.MetricsExplorer()
            % obj = gui.MetricsExplorer(Name=Value)
            % Open the window.
            %
            % Parameters:
            %   options.Metric         - Metric key (see catalog). Default "dprime".
            %   options.HitRate        - Probe hit rate. Default 0.8.
            %   options.FalseAlarmRate - Probe false alarm rate. Default 0.2.
            %   options.Correction     - Correction for rates of 0 and 1.
            %   options.Bounds         - [lo hi] for "clamp".
            %   options.NSignal        - Signal trials, for "halfcell"/"loglinear".
            %   options.NNoise         - Catch trials, likewise.
            %   options.Visible        - Show the window. Default true.
            %
            % Returns:
            %   self - gui.MetricsExplorer instance.
            arguments
                options.Metric (1,1) string = "dprime"
                options.HitRate (1,1) double {mustBeInRange(options.HitRate,0,1)} = 0.8
                options.FalseAlarmRate (1,1) double {mustBeInRange(options.FalseAlarmRate,0,1)} = 0.2
                options.Correction (1,1) string {mustBeMember(options.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                options.Bounds (1,2) double {mustBeInRange(options.Bounds,0,1,"exclusive")} = [0.01 0.99]
                options.NSignal (1,1) double {mustBePositive} = 100
                options.NNoise (1,1) double {mustBePositive} = 100
                options.Visible (1,1) logical = true
            end

            % One window at a time, torn down the way gui.ParameterDebugger
            % does it: the position is saved here rather than left to the prior
            % object's destructor, which can only save it while the figure is
            % still a graphics object.
            existing = findall(groot, 'Type','figure', 'Tag', self.FIGURE_TAG);
            for i = 1:numel(existing)
                if ~isgraphics(existing(i)), continue, end
                prior = existing(i).UserData;
                gui.BehaviorGUI.saveFigurePosition(self.PREF_TAG, existing(i).Position);
                existing(i).UserData = [];
                existing(i).CloseRequestFcn = '';
                delete(existing(i));
                if isobject(prior) && isvalid(prior)
                    delete(prior);
                end
            end

            m = gui.MetricsExplorer.metric(options.Metric);   % validates the key
            self.Metric_ = string(m.Key);
            self.Range_ = m.Range;
            self.HitRate_ = options.HitRate;
            self.FalseAlarm_ = options.FalseAlarmRate;
            self.Correction_ = options.Correction;
            self.Bounds_ = sort(options.Bounds);
            self.NSignal_ = options.NSignal;
            self.NNoise_ = options.NNoise;

            self.Fvec_ = linspace(0, 1, self.GRID_N);
            self.Hvec_ = linspace(0, 1, self.GRID_N);

            self.buildUI(options.Visible);
            self.refreshControls_();
            self.refreshSurface_();
            self.refreshExplanation_();

            if nargout == 0
                clear self
            end
        end

        function delete(self)
            % delete(self)
            % Tear down the window, saving its position.
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

        function v = get.Metric(self)
            v = self.Metric_;
        end

        function v = get.HitRate(self)
            v = self.HitRate_;
        end

        function v = get.FalseAlarmRate(self)
            v = self.FalseAlarm_;
        end

        function v = get.Correction(self)
            v = self.Correction_;
        end

        function v = get.Bounds(self)
            v = self.Bounds_;
        end

        function v = get.NSignal(self)
            v = self.NSignal_;
        end

        function v = get.NNoise(self)
            v = self.NNoise_;
        end

        function setMetric(self, key)
            % setMetric(self, key)
            % Show a different metric, by catalog key.
            %
            % The colour half-width goes back to the metric's own default: a
            % range that framed d' has no meaning for A', and carrying it over
            % would silently mis-frame the new map.
            arguments
                self
                key (1,1) string
            end

            m = gui.MetricsExplorer.metric(key);
            self.Metric_ = string(m.Key);
            self.Range_ = m.Range;

            if isgraphics(self.H.metric), self.H.metric.Value = m.Key; end
            if isgraphics(self.H.range),  self.H.range.Value = self.Range_; end

            self.refreshControls_();
            self.refreshSurface_();
            self.refreshExplanation_();
        end

        function setPoint(self, hitRate, falseAlarmRate)
            % setPoint(self, hitRate, falseAlarmRate)
            % Move the probe. Rates outside [0 1] are clamped to the plane the
            % window draws rather than refused: a click lands where it lands,
            % and an arrow key at the edge should stop, not error.
            arguments
                self
                hitRate (1,1) double
                falseAlarmRate (1,1) double
            end

            % A NaN is neither clamped nor drawable, and the rate fields
            % reject it outright, so a point that cannot be resolved leaves
            % the probe where it was. Infinities still clamp to the edge.
            if isnan(hitRate) || isnan(falseAlarmRate), return, end

            self.HitRate_ = min(max(hitRate, 0), 1);
            self.FalseAlarm_ = min(max(falseAlarmRate, 0), 1);

            if isgraphics(self.H.hitRate),    self.H.hitRate.Value = self.HitRate_;      end
            if isgraphics(self.H.falseAlarm), self.H.falseAlarm.Value = self.FalseAlarm_; end

            self.refreshPoint_();
        end

        function S = values(self)
            % S = values(self)
            % Every metric at the probe point.
            %
            % Field names match psychophysics.Metrics.fromCounts, so a number
            % read off this window and the same number out of a session are
            % looked up under one name.
            C = gui.MetricsExplorer.catalog();
            S = struct();
            S.HitRate = self.HitRate_;
            S.FalseAlarmRate = self.FalseAlarm_;
            S.Correction = self.Correction_;
            S.Bounds = self.Bounds_;
            [hc, fc] = psychophysics.Metrics.correctRates(self.HitRate_, self.FalseAlarm_, ...
                Correction=self.Correction_, Bounds=self.Bounds_, ...
                NSignal=self.NSignal_, NNoise=self.NNoise_);
            S.RateCorrected = struct('Hit', hc, 'FalseAlarm', fc);
            for i = 1:numel(C)
                S.(C(i).Field) = self.evaluateWith_(C(i).Key, self.HitRate_, self.FalseAlarm_);
            end
        end

        function [Z, hitRates, falseAlarmRates] = surface(self)
            % [Z, hitRates, falseAlarmRates] = surface(self)
            % The displayed surface, rows indexed by hit rate and columns by
            % false alarm rate -- the orientation imagesc draws it in.
            Z = self.Z_;
            hitRates = self.Hvec_;
            falseAlarmRates = self.Fvec_;
        end

        function assignToBase(self)
            % assignToBase(self)
            % Put the surface and the probe values in the base workspace as
            % METRICS, for the arithmetic the picture is only the first look at.
            S = self.values();
            [S.Surface, S.HitRates, S.FalseAlarmRates] = self.surface();
            S.Metric = self.Metric_;
            assignin('base', 'METRICS', S);
            self.setStatus_('METRICS assigned in the command window.');
        end
    end

    % ---- Construction ------------------------------------------------------
    methods (Access = private)
        function buildUI(self, visible)
            % Two control strips, the map, a readout row, and the explanation
            % beside it: the text is out of the axes because a legend cannot
            % say what a metric means, and it is beside rather than below so
            % the map stays square at the window's default size.
            pos = gui.BehaviorGUI.getSavedFigurePosition(self.PREF_TAG, self.DEFAULT_POSITION);
            C = gui.MetricsExplorer.catalog();

            f = uifigure('Name','EPsych Psychophysics Metrics', 'Tag', self.FIGURE_TAG, ...
                'Position', pos, ...
                'Visible', matlab.lang.OnOffSwitchState(visible), ...
                'WindowKeyPressFcn', @(~,evt) self.onKeyPress_(evt));
            f.UserData = self;
            f.CloseRequestFcn = @(~,~) delete(self);
            self.H.figure = f;

            % The wiki page is the guide; the repository doc is the same text
            % at full length, and the one a rig with no network can still open.
            mHelp = uimenu(f, 'Text','&Help');
            self.H.menuGuide = uimenu(mHelp, 'Text','Metrics Explorer &Guide (Wiki)', ...
                'MenuSelectedFcn', @(~,~) gui.MetricsExplorer.openGuide());
            uimenu(mHelp, 'Text','&Reference Documentation', ...
                'MenuSelectedFcn', @(~,~) openReferenceDoc_());

            g = uigridlayout(f, [5 2]);
            g.RowHeight = {'fit', 'fit', '1x', 62, 'fit'};
            g.ColumnWidth = {'1x', 340};
            g.Padding = [10 8 10 8];
            g.RowSpacing = 8;

            % ---------- Metric strip -----------------------------------------
            gMetric = uigridlayout(g, [1 6]);
            gMetric.Layout.Row = 1;
            gMetric.Layout.Column = 1;
            gMetric.RowHeight = {24};
            gMetric.ColumnWidth = {50, 250, 105, 70, 105, '1x'};
            gMetric.ColumnSpacing = 6;
            gMetric.Padding = [0 0 0 0];

            lbl = uilabel(gMetric, 'Text','Metric:', 'HorizontalAlignment','right');
            place_(lbl, 1, 1);
            self.H.metric = uidropdown(gMetric, 'Items', {C.Label}, 'ItemsData', {C.Key}, ...
                'Value', char(self.Metric_), ...
                'Tooltip','Which signal-detection metric this map shows.', ...
                'ValueChangedFcn', @(src,~) self.setMetric(src.Value));
            place_(self.H.metric, 1, 2);

            self.H.rangeLabel = uilabel(gMetric, 'Text','Colour range +/-:', ...
                'HorizontalAlignment','right');
            place_(self.H.rangeLabel, 1, 3);
            % The floor is 1e-6 rather than "anything above zero": the colour
            % limits are the neutral value plus and minus this, and a range
            % small enough for those two to collide throws from the axes.
            self.H.range = uieditfield(gMetric, 'numeric', 'Value', self.Range_, ...
                'Limits', [1e-6 Inf], ...
                'ValueDisplayFormat','%.4g', ...
                'Tooltip', ['Half-width of the colour scale about the metric''s ' ...
                            'neutral value. Values beyond it saturate, and the ' ...
                            'end tick labels say so.'], ...
                'ValueChangedFcn', @(src,~) self.onRangeChanged_(src.Value));
            place_(self.H.range, 1, 4);

            self.H.contours = uicheckbox(gMetric, 'Text','Contour labels', ...
                'Value', self.ShowContours_, ...
                'Tooltip','Draw labelled contours at round levels.', ...
                'ValueChangedFcn', @(src,~) self.onContoursChanged_(src.Value));
            place_(self.H.contours, 1, 5);

            % ---------- Correction strip -------------------------------------
            gCorr = uigridlayout(g, [1 10]);
            gCorr.Layout.Row = 2;
            gCorr.Layout.Column = 1;
            gCorr.RowHeight = {24};
            gCorr.ColumnWidth = {75, 110, 58, 58, 58, 64, 52, 58, 52, '1x'};
            gCorr.ColumnSpacing = 6;
            gCorr.Padding = [0 0 0 0];

            self.H.correctionLabel = uilabel(gCorr, 'Text','Correction:', ...
                'HorizontalAlignment','right');
            place_(self.H.correctionLabel, 1, 1);
            self.H.correction = uidropdown(gCorr, 'Items', self.CORRECTIONS, ...
                'ItemsData', self.CORRECTIONS, 'Value', char(self.Correction_), ...
                'Tooltip', ['What z() sees at rates of 0 and 1: none (+/-Inf), ' ...
                            'clamp into bounds, half-cell 1/(2N), or log-linear ' ...
                            '(nYes+0.5)/(N+1).'], ...
                'ValueChangedFcn', @(src,~) self.onCorrectionChanged_(src.Value));
            place_(self.H.correction, 1, 2);

            self.H.boundsLabel = uilabel(gCorr, 'Text','Bounds:', ...
                'HorizontalAlignment','right');
            place_(self.H.boundsLabel, 1, 3);
            self.H.boundsLo = uieditfield(gCorr, 'numeric', 'Value', self.Bounds_(1), ...
                'Limits', [0 1], 'LowerLimitInclusive','off', 'UpperLimitInclusive','off', ...
                'ValueDisplayFormat','%.4g', ...
                'Tooltip','Lower bound the "clamp" correction pulls rates up to.', ...
                'ValueChangedFcn', @(~,~) self.onBoundsChanged_());
            place_(self.H.boundsLo, 1, 4);
            self.H.boundsHi = uieditfield(gCorr, 'numeric', 'Value', self.Bounds_(2), ...
                'Limits', [0 1], 'LowerLimitInclusive','off', 'UpperLimitInclusive','off', ...
                'ValueDisplayFormat','%.4g', ...
                'Tooltip','Upper bound the "clamp" correction pulls rates down to.', ...
                'ValueChangedFcn', @(~,~) self.onBoundsChanged_());
            place_(self.H.boundsHi, 1, 5);

            self.H.nSignalLabel = uilabel(gCorr, 'Text','N signal:', ...
                'HorizontalAlignment','right');
            place_(self.H.nSignalLabel, 1, 6);
            self.H.nSignal = uieditfield(gCorr, 'numeric', 'Value', self.NSignal_, ...
                'Limits', [1 Inf], 'RoundFractionalValues','on', ...
                'Tooltip','Signal trials behind the hit rate; the N-dependent corrections need it.', ...
                'ValueChangedFcn', @(src,~) self.onCountChanged_('signal', src.Value));
            place_(self.H.nSignal, 1, 7);
            self.H.nNoiseLabel = uilabel(gCorr, 'Text','N catch:', ...
                'HorizontalAlignment','right');
            place_(self.H.nNoiseLabel, 1, 8);
            self.H.nNoise = uieditfield(gCorr, 'numeric', 'Value', self.NNoise_, ...
                'Limits', [1 Inf], 'RoundFractionalValues','on', ...
                'Tooltip','Catch trials behind the false alarm rate.', ...
                'ValueChangedFcn', @(src,~) self.onCountChanged_('noise', src.Value));
            place_(self.H.nNoise, 1, 9);

            % ---------- Map ---------------------------------------------------
            ax = uiaxes(g);
            ax.Layout.Row = 3;
            ax.Layout.Column = 1;
            self.H.axes = ax;

            % Seeded with a small non-degenerate array rather than the real
            % grid: imagesc picks its own colour limits from the data, and the
            % first thing refreshSurface_ does is set both CData and CLim.
            self.H.image = imagesc(ax, [0 1], [0 1], [0 1; 1 0]);
            self.H.image.ButtonDownFcn = @(~,~) self.onAxesClick_();
            ax.YDir = 'normal';
            hold(ax, 'on');
            ax.XLim = [0 1];
            ax.YLim = [0 1];
            ax.PlotBoxAspectRatio = [1 1 1];
            ax.Box = 'on';
            ax.Layer = 'top';
            ax.TickDir = 'out';
            ax.ButtonDownFcn = @(~,~) self.onAxesClick_();
            xlabel(ax, 'false alarm rate', 'Interpreter','none');
            ylabel(ax, 'hit rate', 'Interpreter','none');
            colormap(ax, gui.MetricsExplorer.divergingMap(256));

            % The crosshair is persistent and moved in place: it is redrawn on
            % every click, and recreating graphics at that rate flickers.
            self.H.vline = line(ax, [NaN NaN], [0 1], 'Color',[0.30 0.30 0.30], ...
                'LineStyle','--', 'LineWidth',0.75, ...
                'PickableParts','none', 'HitTest','off');
            self.H.hline = line(ax, [0 1], [NaN NaN], 'Color',[0.30 0.30 0.30], ...
                'LineStyle','--', 'LineWidth',0.75, ...
                'PickableParts','none', 'HitTest','off');

            self.H.colorbar = colorbar(ax);
            self.H.colorbar.Label.Interpreter = 'none';

            cm = uicontextmenu(f);
            uimenu(cm, 'Text','Assign Surface to Command Window', ...
                'MenuSelectedFcn', @(~,~) self.assignToBase());
            ax.ContextMenu = cm;

            % ---------- Readout ------------------------------------------------
            gRead = uigridlayout(g, [2, numel(C) + 2]);
            gRead.Layout.Row = 4;
            gRead.Layout.Column = 1;
            gRead.RowHeight = {16, 28};
            gRead.ColumnWidth = [{92, 92}, repmat({'1x'}, 1, numel(C))];
            gRead.ColumnSpacing = 6;
            gRead.RowSpacing = 2;
            gRead.Padding = [0 0 0 0];

            % Row 1: the names. Row 2: the numbers. The two rates are edit
            % fields, so a point can be typed exactly instead of clicked at.
            lbl = uilabel(gRead, 'Text','false alarm', 'FontSize',10, ...
                'FontColor',self.LABEL_COLOR);
            place_(lbl, 1, 1);
            lbl = uilabel(gRead, 'Text','hit rate', 'FontSize',10, ...
                'FontColor',self.LABEL_COLOR);
            place_(lbl, 1, 2);
            self.ValueLabels_ = gobjects(1, numel(C));
            for i = 1:numel(C)
                lbl = uilabel(gRead, 'Text', C(i).Symbol, 'FontSize',10, ...
                    'FontColor',self.LABEL_COLOR, 'Tooltip', C(i).Label);
                place_(lbl, 1, i + 2);
            end

            self.H.falseAlarm = uieditfield(gRead, 'numeric', 'Value', self.FalseAlarm_, ...
                'Limits', [0 1], 'ValueDisplayFormat','%.3f', 'FontSize',16, ...
                'Tooltip','False alarm rate of the probe point.', ...
                'ValueChangedFcn', @(src,~) self.setPoint(self.HitRate_, src.Value));
            place_(self.H.falseAlarm, 2, 1);
            self.H.hitRate = uieditfield(gRead, 'numeric', 'Value', self.HitRate_, ...
                'Limits', [0 1], 'ValueDisplayFormat','%.3f', 'FontSize',16, ...
                'Tooltip','Hit rate of the probe point.', ...
                'ValueChangedFcn', @(src,~) self.setPoint(src.Value, self.FalseAlarm_));
            place_(self.H.hitRate, 2, 2);
            for i = 1:numel(C)
                self.ValueLabels_(i) = uilabel(gRead, 'Text','', 'FontSize',16, ...
                    'FontColor', self.VALUE_COLOR, 'Tooltip', C(i).Label);
                place_(self.ValueLabels_(i), 2, i + 2);
            end

            % ---------- Status ---------------------------------------------------
            self.H.status = uilabel(g, 'Text','', 'WordWrap','on', ...
                'FontColor', self.LABEL_COLOR);
            self.H.status.Layout.Row = 5;
            self.H.status.Layout.Column = 1;

            % ---------- Explanation ------------------------------------------------
            % The citations sit under the text rather than in it: a uitextarea
            % cannot hold a link, and a DOI that has to be retyped is one
            % nobody follows. Their grid is rebuilt per metric.
            p = uipanel(g, 'Title','What this metric means');
            p.Layout.Row = [1 5];
            p.Layout.Column = 2;
            gp = uigridlayout(p, [3 1]);
            gp.RowHeight = {'1x', 'fit', 'fit'};
            gp.RowSpacing = 8;
            gp.Padding = [6 6 6 6];
            self.H.explain = uitextarea(gp, 'Editable','off', 'Value', {''}, ...
                'FontSize', 12);
            self.H.explain.Layout.Row = 1;

            self.H.references = uigridlayout(gp, [1 1]);
            self.H.references.Layout.Row = 2;
            self.H.references.Padding = [0 0 0 0];
            self.H.references.RowSpacing = 1;

            self.H.guideLink = uihyperlink(gp, 'Text','Full guide on the EPsych wiki', ...
                'URL', self.WIKI_URL, 'Tooltip', self.WIKI_URL);
            self.H.guideLink.Layout.Row = 3;
        end
    end

    % ---- Refresh -------------------------------------------------------------
    methods (Access = private)
        function refreshSurface_(self)
            % Recompute the map and everything that describes it.
            m = gui.MetricsExplorer.metric(self.Metric_);
            [Fg, Hg] = meshgrid(self.Fvec_, self.Hvec_);
            self.Z_ = self.evaluateWith_(self.Metric_, Hg, Fg);

            ax = self.H.axes;
            self.H.image.CData = self.Z_;

            lim = m.Neutral + self.Range_ * [-1 1];
            ax.CLim = lim;
            title(ax, m.Label, 'Interpreter','none');

            % Contours see a finite surface: a level crossing at infinity is
            % meaningless, and the image already shows those cells saturated.
            Zc = self.Z_;
            Zc(~isfinite(Zc)) = NaN;

            delete(self.Contours_(isgraphics(self.Contours_)));
            self.Contours_ = gobjects(1,0);

            if self.ShowContours_
                levels = m.Neutral + self.Range_ * (-1:0.25:1);
                [~, hThin] = contour(ax, self.Fvec_, self.Hvec_, Zc, levels, ...
                    'LineColor',[0.25 0.25 0.25], 'LineWidth',0.5, ...
                    'ShowText','on', 'LabelSpacing',260, ...
                    'PickableParts','none', 'HitTest','off');
                self.Contours_(end+1) = hThin;
            end

            % The neutral level is the reference the literature draws: chance
            % for a sensitivity index, unbiased for a bias index. It is always
            % shown, and heavier than the rest.
            [~, hNeutral] = contour(ax, self.Fvec_, self.Hvec_, Zc, ...
                [m.Neutral m.Neutral], 'LineColor','k', 'LineWidth',1.8, ...
                'PickableParts','none', 'HitTest','off');
            self.Contours_(end+1) = hNeutral;

            self.refreshColorbar_(m, lim);
            self.refreshPoint_();
        end

        function refreshColorbar_(self, m, lim)
            % Ticks say when the scale is clipped. A saturated colour that does
            % not admit it reads as a measured value.
            cb = self.H.colorbar;
            ticks = linspace(lim(1), lim(2), 9);
            labels = arrayfun(@(t) sprintf('%.4g', t), ticks, 'UniformOutput', false);

            Z = self.Z_;
            if any(Z(:) < lim(1))
                labels{1} = ['<= ' labels{1}];
            end
            if any(Z(:) > lim(2))
                labels{end} = ['>= ' labels{end}];
            end

            % Limits are deliberately not set: a colorbar follows its axes
            % CLim, which was set a moment ago, and pinning both is how a tick
            % list and a limit end up disagreeing after a metric change.
            cb.Ticks = ticks;
            cb.TickLabels = labels;
            cb.Label.String = sprintf('%s   (%s <-> %s)', m.Symbol, m.LowWord, m.HighWord);
        end

        function refreshPoint_(self)
            % Move the crosshair and recompute the readout. Nothing here
            % touches the surface, so clicking is cheap.
            self.H.vline.XData = [self.FalseAlarm_ self.FalseAlarm_];
            self.H.hline.YData = [self.HitRate_ self.HitRate_];

            C = gui.MetricsExplorer.catalog();
            for i = 1:numel(C)
                v = self.evaluateWith_(C(i).Key, self.HitRate_, self.FalseAlarm_);
                self.ValueLabels_(i).Text = gui.MetricsExplorer.formatValue(v);
                if strcmp(C(i).Key, char(self.Metric_))
                    self.ValueLabels_(i).FontWeight = 'bold';
                    self.ValueLabels_(i).FontColor = self.ACCENT_COLOR;
                else
                    self.ValueLabels_(i).FontWeight = 'normal';
                    self.ValueLabels_(i).FontColor = self.VALUE_COLOR;
                end
            end

            self.setStatus_(self.correctionNote_());
        end

        function refreshControls_(self)
            % The correction controls follow the metric and the mode, and
            % their labels grey with them: a live field beside a dead one, or
            % a black label over a grey field, both read as an oversight.
            m = gui.MetricsExplorer.metric(self.Metric_);
            usesCorrection = m.UsesCorrection;
            isClamp = usesCorrection && self.Correction_ == "clamp";
            needsN = usesCorrection && any(self.Correction_ == ["halfcell","loglinear"]);

            setEnable_([self.H.correctionLabel self.H.correction], usesCorrection);
            setEnable_([self.H.boundsLabel self.H.boundsLo self.H.boundsHi], isClamp);
            setEnable_([self.H.nSignalLabel self.H.nSignal ...
                        self.H.nNoiseLabel self.H.nNoise], needsN);
        end

        function refreshExplanation_(self)
            % The text beside the map, assembled from the catalog entry.
            m = gui.MetricsExplorer.metric(self.Metric_);

            txt = {};
            txt{end+1} = m.Label;
            txt{end+1} = '';
            txt{end+1} = ['    ' m.Formula];
            txt{end+1} = '';
            txt{end+1} = m.Summary;
            txt{end+1} = '';
            txt{end+1} = 'Reading the map';
            txt{end+1} = sprintf('  Heavy black line: %s = %g, %s.', ...
                m.Symbol, m.Neutral, m.NeutralMeaning);
            txt{end+1} = sprintf('  Blue: %s.  Red: %s.', m.LowWord, m.HighWord);
            txt{end+1} = ['  ' m.Reading];
            txt{end+1} = '';
            txt{end+1} = 'Rates of 0 and 1';
            if m.UsesCorrection
                txt{end+1} = ['  z(0) and z(1) are -Inf and +Inf, so the edges of ' ...
                    'this map are whatever the correction above makes them.'];
            else
                txt{end+1} = ['  Defined at 0 and 1, so no correction is applied ' ...
                    'and the correction controls are greyed out. Correcting it ' ...
                    'would only bias it toward chance.'];
            end
            if ~isempty(m.Caution)
                txt{end+1} = '';
                txt{end+1} = 'Watch for';
                txt{end+1} = ['  ' m.Caution];
            end

            self.H.explain.Value = txt;
            self.refreshReferences_(m.Citations);
        end

        function refreshReferences_(self, cites)
            % One wrapped line per citation, and under it the DOI as a link
            % when the work has one. The link's text IS the DOI, so the
            % identifier can be read off the window as well as clicked.
            g = self.H.references;
            delete(g.Children);

            n = 1 + numel(cites) + nnz(~cellfun(@isempty, {cites.DOI}));
            g.RowHeight = repmat({'fit'}, 1, n);

            lbl = uilabel(g, 'Text','References', 'FontWeight','bold', ...
                'FontColor', self.LABEL_COLOR);
            place_(lbl, 1, 1);

            row = 1;
            for i = 1:numel(cites)
                row = row + 1;
                lbl = uilabel(g, 'Text', cites(i).Full, 'WordWrap','on', ...
                    'FontSize', 11, 'VerticalAlignment','top');
                place_(lbl, row, 1);
                if isempty(cites(i).DOI), continue, end

                row = row + 1;
                url = gui.MetricsExplorer.doiUrl(cites(i).DOI);
                h = uihyperlink(g, 'Text', ['doi:' cites(i).DOI], 'URL', url, ...
                    'FontSize', 11, 'Tooltip', url, ...
                    'Tag', ['MetricsExplorerDOI_' cites(i).Key]);
                place_(h, row, 1);
            end
        end

        function setStatus_(self, msg)
            if isfield(self.H,'status') && isgraphics(self.H.status)
                self.H.status.Text = msg;
            end
        end

        function txt = correctionNote_(self)
            % What the z-transform actually saw, in words. The first question
            % asked of a surprising d' is which rates went in.
            m = gui.MetricsExplorer.metric(self.Metric_);
            if ~m.UsesCorrection
                txt = sprintf(['%s is defined at rates of 0 and 1, so it takes the ' ...
                    'rates as they are; the correction setting does not apply to it.'], ...
                    m.Symbol);
                return
            end

            if self.Correction_ == "none"
                txt = ['Correction "none": rates of exactly 0 or 1 give z = -Inf ' ...
                       'or +Inf, so the edges of the map saturate the colour scale.'];
                return
            end

            [hc, fc] = psychophysics.Metrics.correctRates(self.HitRate_, self.FalseAlarm_, ...
                Correction=self.Correction_, Bounds=self.Bounds_, ...
                NSignal=self.NSignal_, NNoise=self.NNoise_);

            if isequaln([hc fc], [self.HitRate_ self.FalseAlarm_])
                changed = ' (unchanged at this point)';
            else
                changed = '';
            end
            txt = sprintf('Correction "%s": the z-transform sees H = %.4g, F = %.4g%s.', ...
                self.Correction_, hc, fc, changed);
        end

        function v = evaluateWith_(self, key, hitRate, falseAlarmRate)
            % One chokepoint, so the surface, the readout and values() cannot
            % disagree about how a number was produced.
            v = gui.MetricsExplorer.evaluate(key, hitRate, falseAlarmRate, ...
                Correction=self.Correction_, Bounds=self.Bounds_, ...
                NSignal=self.NSignal_, NNoise=self.NNoise_);
        end
    end

    % ---- Callbacks -----------------------------------------------------------
    methods (Access = private)
        function onAxesClick_(self)
            % uiaxes reports the click through CurrentPoint, which is set for
            % the axes whether the image or the axes background was hit.
            cp = self.H.axes.CurrentPoint;
            self.setPoint(cp(1,2), cp(1,1));
        end

        function onKeyPress_(self, evt)
            % Arrow keys nudge the probe: 0.01, or 0.001 with shift. A uifigure
            % delivers no window key event while an edit field has focus, which
            % is what keeps this from fighting the rate fields.
            step = 0.01;
            if any(strcmp(evt.Modifier, 'shift')), step = 0.001; end
            switch evt.Key
                case 'leftarrow',  self.setPoint(self.HitRate_, self.FalseAlarm_ - step);
                case 'rightarrow', self.setPoint(self.HitRate_, self.FalseAlarm_ + step);
                case 'uparrow',    self.setPoint(self.HitRate_ + step, self.FalseAlarm_);
                case 'downarrow',  self.setPoint(self.HitRate_ - step, self.FalseAlarm_);
            end
        end

        function onRangeChanged_(self, value)
            self.Range_ = value;
            self.refreshSurface_();
        end

        function onContoursChanged_(self, value)
            self.ShowContours_ = value;
            self.refreshSurface_();
        end

        function onCorrectionChanged_(self, value)
            self.Correction_ = string(value);
            self.refreshControls_();
            self.refreshSurface_();
            self.refreshExplanation_();
        end

        function onBoundsChanged_(self)
            % Bounds that cross would make the clamp mean two different things
            % on either side of it, so the entry is refused and put back.
            lo = self.H.boundsLo.Value;
            hi = self.H.boundsHi.Value;
            if lo >= hi
                self.H.boundsLo.Value = self.Bounds_(1);
                self.H.boundsHi.Value = self.Bounds_(2);
                self.setStatus_('The lower bound must be below the upper bound; the entry was put back.');
                return
            end
            self.Bounds_ = [lo hi];
            self.refreshSurface_();
        end

        function onCountChanged_(self, which, value)
            switch which
                case 'signal', self.NSignal_ = value;
                case 'noise',  self.NNoise_ = value;
            end
            self.refreshSurface_();
        end
    end

    % ---- The metrics ----------------------------------------------------------
    methods (Static)
        function C = catalog()
            % C = gui.MetricsExplorer.catalog()
            % The metrics this window offers, in display order.
            %
            % Every entry names a psychophysics.Metrics method rather than
            % carrying a formula, so a metric shown here is the metric a
            % session reports. UsesCorrection says whether the correction for
            % rates of 0 and 1 reaches it at all: A', B'' and the balanced
            % proportion correct are defined at 0 and 1 and are deliberately
            % given the observed rates, exactly as Metrics.fromCounts does.
            %
            % Returns:
            %   C - 1-by-N struct array. Key, Field, Label, Symbol, Fcn,
            %       UsesCorrection, Neutral, NeutralMeaning, Range, LowWord,
            %       HighWord, Formula, Summary, Reading, Caution, Reference,
            %       Citations. Reference is the short in-text form
            %       ("Grier (1971)"); Citations is the matching entries of
            %       gui.MetricsExplorer.citations, DOIs included.
            C = [ ...
                mk_('dprime', 'DPrime', "d' -- sensitivity", "d'", ...
                    @psychophysics.Metrics.dprime, ...
                    'Neutral', 0, 'Range', 4, ...
                    'NeutralMeaning', 'chance, where the hit and false alarm rates are equal', ...
                    'LowWord', 'reversed', 'HighWord', 'sensitive', ...
                    'Formula', "d' = z(H) - z(F)", ...
                    'Summary', ['The distance between the noise and signal-plus-noise ' ...
                        'distributions, in standard deviations of the noise, assuming ' ...
                        'both are Gaussian with equal variance. 0 is chance, 1 a modest ' ...
                        'but real discrimination, 2 a good one. Negative means responding ' ...
                        'opposite to the stimulus.'], ...
                    'Reading', ['The map is antisymmetric about the diagonal: swapping H ' ...
                        'and F flips the sign. It says nothing about willingness to ' ...
                        'respond -- every point along a contour is the same sensitivity ' ...
                        'at a different criterion.'], ...
                    'Caution', ['Above about 4 the number is governed by whichever ' ...
                        'correction was applied rather than by the data: with the ' ...
                        'default clamp of [0.01 0.99] no session can report more than ' ...
                        '4.653, however good the subject.'], ...
                    'References', ["GreenSwets1966", "MacmillanCreelman2005"]), ...
                mk_('criterion', 'Criterion', 'c -- decision criterion', 'c', ...
                    @psychophysics.Metrics.criterion, ...
                    'Neutral', 0, 'Range', 2, ...
                    'NeutralMeaning', 'unbiased, along H = 1 - F', ...
                    'LowWord', 'liberal', 'HighWord', 'conservative', ...
                    'Formula', 'c = -(z(H) + z(F)) / 2', ...
                    'Summary', ['Where the subject placed the decision boundary, in the ' ...
                        'same units as d''. 0 is unbiased; positive is conservative ' ...
                        '(reluctant to respond, both rates low); negative is liberal ' ...
                        '(responding readily, both rates high). This is what ' ...
                        'psychophysics.Detection calls bias and SessionMetrics reports ' ...
                        'as Criterion.'], ...
                    'Reading', ['Contours run parallel to the anti-diagonal, so criterion ' ...
                        'is the position ALONG that diagonal and sensitivity is the ' ...
                        'distance across it: the two are independent axes of the same ' ...
                        'plane.'], ...
                    'Caution', ['c is in units of the noise distribution, so comparing it ' ...
                        'between subjects whose d'' differ compares different rulers. ' ...
                        'c/d'' is the comparable form.'], ...
                    'References', "MacmillanCreelman2005"), ...
                mk_('criterionRelative', 'CriterionRelative', "c' -- relative criterion", "c'", ...
                    @psychophysics.Metrics.criterionRelative, ...
                    'Neutral', 0, 'Range', 2, ...
                    'NeutralMeaning', 'unbiased, along H = 1 - F', ...
                    'LowWord', 'liberal', 'HighWord', 'conservative', ...
                    'Formula', "c' = c / d'", ...
                    'Summary', ['Criterion expressed as a fraction of the subject''s own ' ...
                        'sensitivity, which is what makes bias comparable between ' ...
                        'subjects or sessions whose d'' differ.'], ...
                    'Reading', ['The saturated band along the H = F diagonal is d'' = 0: ' ...
                        'c/0 is infinite, and at H = F with c = 0 it is 0/0. Both are ' ...
                        'reported rather than papered over -- there is no meaningful ' ...
                        'relative criterion where there is no sensitivity.'], ...
                    'Caution', ['Read it only where d'' is comfortably away from 0. Near ' ...
                        'the diagonal a tiny change in either rate swings it wildly.'], ...
                    'References', "MacmillanCreelman2005"), ...
                mk_('lnBeta', 'LnBeta', 'ln(beta) -- likelihood-ratio bias', 'ln B', ...
                    @psychophysics.Metrics.lnBeta, ...
                    'Neutral', 0, 'Range', 4, ...
                    'NeutralMeaning', 'unbiased -- BOTH where c = 0 and where d'' = 0', ...
                    'LowWord', 'liberal', 'HighWord', 'conservative', ...
                    'Formula', 'ln(beta) = (z(F)^2 - z(H)^2) / 2  ==  c * d''', ...
                    'Summary', ['The likelihood ratio at the criterion, in logs: how much ' ...
                        'more probable the evidence at the boundary is under signal than ' ...
                        'under noise. 0 is unbiased, positive conservative. Reported in ' ...
                        'logs because beta itself spans orders of magnitude ' ...
                        '(beta = exp(ln beta)).'], ...
                    'Reading', ['The neutral line has TWO branches, and that is the point: ' ...
                        'ln(beta) = c * d'', so it vanishes both where the subject is ' ...
                        'unbiased and where the subject is at chance.'], ...
                    'Caution', ['Because it is the product, ln(beta) confounds bias with ' ...
                        'sensitivity: a strongly biased subject at chance scores the same ' ...
                        '0 as an unbiased expert. Prefer c when the question is bias.'], ...
                    'References', "MacmillanCreelman2005"), ...
                mk_('aprime', 'APrime', "A' -- nonparametric sensitivity", "A'", ...
                    @psychophysics.Metrics.aprime, ...
                    'UsesCorrection', false, 'Neutral', 0.5, 'Range', 0.5, ...
                    'NeutralMeaning', 'chance, where the hit and false alarm rates are equal', ...
                    'LowWord', 'reversed', 'HighWord', 'sensitive', ...
                    'Formula', "A' = 0.5 + sign(H-F) * ((H-F)^2 + |H-F|) / (4*max(H,F) - 4*H*F)", ...
                    'Summary', ['Sensitivity without assuming a distribution: the area ' ...
                        'under the ROC curve through the single observed point, which ' ...
                        'reads as the proportion correct an equivalent unbiased 2AFC ' ...
                        'task would give. 0.5 is chance, 1 perfect, below 0.5 a reversed ' ...
                        'response mapping.'], ...
                    'Reading', ['Compare it against d'': the same contours, but bounded, ' ...
                        'and with no correction deciding what happens at the corners. ' ...
                        'That is what makes it the safer summary for the small trial ' ...
                        'counts and extreme rates a single session produces.'], ...
                    'Caution', ['Bounded at 1, so it compresses exactly where d'' spreads ' ...
                        'out: two excellent sessions that differ in d'' can both read ' ...
                        '0.99.'], ...
                    'References', "Grier1971"), ...
                mk_('bprimeprime', 'BPrimePrime', "B'' -- nonparametric bias", "B''", ...
                    @psychophysics.Metrics.bprimeprime, ...
                    'UsesCorrection', false, 'Neutral', 0, 'Range', 1, ...
                    'NeutralMeaning', 'no bias', ...
                    'LowWord', 'liberal', 'HighWord', 'conservative', ...
                    'Formula', "B'' = sign(H-F) * (H(1-H) - F(1-F)) / (H(1-H) + F(1-F))", ...
                    'Summary', ['Response bias without assuming a distribution, from -1 ' ...
                        '(extremely liberal) through 0 (no bias) to +1 (extremely ' ...
                        'conservative). It is to criterion what A'' is to d'': defined at ' ...
                        'rates of exactly 0 and 1, so it stays usable at the trial counts ' ...
                        'a single session produces.'], ...
                    'Reading', ['The neutral line has two branches -- H = F and H = 1 - F ' ...
                        '-- because both make the two rates equally far from 0.5. Where ' ...
                        'both rates are 0 or 1 the formula is 0/0 and is reported as 0: ' ...
                        'rates that extreme carry no evidence about bias either way.'], ...
                    'Caution', 'Bounded, so it cannot be averaged as if it were in criterion units.', ...
                    'References', "Grier1971"), ...
                mk_('percentCorrect', 'PercentCorrectBalanced', ...
                    'balanced proportion correct', 'pc', ...
                    @psychophysics.Metrics.percentCorrect, ...
                    'UsesCorrection', false, 'Neutral', 0.5, 'Range', 0.5, ...
                    'NeutralMeaning', 'chance, where the hit and false alarm rates are equal', ...
                    'LowWord', 'reversed', 'HighWord', 'correct', ...
                    'Formula', 'pc = (H + (1 - F)) / 2  ==  0.5 + (H - F)/2', ...
                    'Summary', ['The proportion correct an equal number of signal and ' ...
                        'catch trials would have produced. Prior-free, and a fraction ' ...
                        'rather than a percentage, like every rate in this package.'], ...
                    'Reading', ['Contours are straight and evenly spaced, which is the ' ...
                        'whole difference from d'': proportion correct treats a move from ' ...
                        '0.50 to 0.55 as the same step as 0.90 to 0.95, where d'' does ' ...
                        'not.'], ...
                    'Caution', ['This is NOT the observed proportion correct a session ' ...
                        'reports. With 90 stimulus and 10 catch trials the two differ, ' ...
                        'and the difference is the trial mix, not the subject.'], ...
                    'References', "MacmillanCreelman2005")];
        end

        function m = metric(key)
            % m = gui.MetricsExplorer.metric(key)
            % One catalog entry by key, case-insensitively.
            arguments
                key (1,1) string
            end
            C = gui.MetricsExplorer.catalog();
            idx = find(strcmpi({C.Key}, key), 1);
            if isempty(idx)
                error('gui:MetricsExplorer:UnknownMetric', ...
                    'No metric named "%s". Known metrics: %s.', key, strjoin({C.Key}, ', '));
            end
            m = C(idx);
        end

        function R = citations(keys)
            % R = gui.MetricsExplorer.citations()
            % R = gui.MetricsExplorer.citations(keys)
            % The works the explanations cite, in the order asked for.
            %
            % One table, so a DOI is written down once however many metrics
            % cite the work. DOI is empty for a work that has none (Green &
            % Swets predates them) -- the window then shows the citation
            % without a link rather than inventing one.
            %
            % Parameters:
            %   keys - Citation keys; all of them when omitted.
            %
            % Returns:
            %   R - Struct array. Key, Short (in-text form), Full, DOI.
            arguments
                keys (1,:) string = string.empty(1,0)
            end

            R = [ ...
                cite_('GreenSwets1966', 'Green & Swets (1966)', ...
                    ['Green DM, Swets JA (1966) Signal Detection Theory and ' ...
                     'Psychophysics. New York: Wiley.'], ''), ...
                cite_('MacmillanCreelman2005', 'Macmillan & Creelman (2005)', ...
                    ['Macmillan NA, Creelman CD (2005) Detection Theory: A ' ...
                     'User''s Guide, 2nd ed. Mahwah, NJ: Erlbaum.'], ...
                    '10.4324/9781410611147'), ...
                cite_('Grier1971', 'Grier (1971)', ...
                    ['Grier JB (1971) Nonparametric indexes for sensitivity ' ...
                     'and bias: computing formulas. Psychol Bull 75(6):424-429.'], ...
                    '10.1037/h0031246')];

            % nargin, not isempty: an entry that cites nothing asks for no
            % citations, and must not be handed all of them.
            if nargin == 0, return, end
            [found, idx] = ismember(keys, string({R.Key}));
            if ~all(found)
                error('gui:MetricsExplorer:UnknownCitation', ...
                    'No citation named "%s". Known citations: %s.', ...
                    strjoin(keys(~found), '", "'), strjoin({R.Key}, ', '));
            end
            R = R(idx);
        end

        function url = doiUrl(doi)
            % url = gui.MetricsExplorer.doiUrl(doi)
            % The resolver address for a DOI -- the https form Crossref
            % recommends, which survives a publisher moving the work.
            arguments
                doi (1,:) char
            end
            url = ['https://doi.org/' doi];
        end

        function openGuide()
            % gui.MetricsExplorer.openGuide()
            % Open this window's wiki page in the system browser.
            web(gui.MetricsExplorer.WIKI_URL, '-browser');
        end

        function v = evaluate(key, hitRate, falseAlarmRate, opts)
            % v = gui.MetricsExplorer.evaluate(key, H, F, Name=Value)
            % One metric over any rates, the way this window computes it.
            %
            % Public because it is the whole of the window's arithmetic: a
            % number read off the map can be reproduced at the command line
            % with the same call. Rates broadcast, so a grid goes in and a grid
            % comes out.
            %
            % Parameters:
            %   key                     - Catalog key, e.g. "dprime".
            %   hitRate, falseAlarmRate - Rates; broadcast together.
            %   Correction              - See psychophysics.Metrics.correctRates.
            %   Bounds, NSignal, NNoise - Likewise. A metric that takes no
            %                             correction ignores all four.
            %
            % Returns:
            %   v - The metric, broadcast to the common size of the rates.
            arguments
                key (1,1) string
                hitRate double
                falseAlarmRate double
                opts.Correction (1,1) string {mustBeMember(opts.Correction, ...
                    ["none","clamp","halfcell","loglinear"])} = "clamp"
                opts.Bounds (1,2) double {mustBeInRange(opts.Bounds,0,1,"exclusive")} = [0.01 0.99]
                opts.NSignal double = []
                opts.NNoise double = []
            end

            m = gui.MetricsExplorer.metric(key);
            if m.UsesCorrection
                v = m.Fcn(hitRate, falseAlarmRate, ...
                    'Correction', opts.Correction, 'Bounds', opts.Bounds, ...
                    'NSignal', opts.NSignal, 'NNoise', opts.NNoise);
            else
                v = m.Fcn(hitRate, falseAlarmRate);
            end
        end

        function txt = formatValue(v)
            % txt = gui.MetricsExplorer.formatValue(v)
            % One metric value as readout text. Infinities and NaN are named
            % rather than rounded into a number that was never computed.
            arguments
                v (1,1) double
            end
            if isnan(v)
                txt = 'n/a';
            elseif isinf(v)
                txt = char(string(v));
            elseif v ~= 0 && abs(v) >= 1000
                txt = sprintf('%.4g', v);
            else
                txt = sprintf('%.3f', v);
            end
        end

        function map = divergingMap(n)
            % map = gui.MetricsExplorer.divergingMap(n)
            % Blue-white-red diverging colormap, n-by-3.
            %
            % Diverging because every metric here has a neutral value, and the
            % colour scale is centred on it: white means chance or no bias, and
            % the two poles keep one meaning across metrics. Interpolated from
            % ColorBrewer RdBu, reversed so that low reads blue.
            arguments
                n (1,1) double {mustBePositive} = 256
            end
            anchors = [ ...
                  5  48  97
                 33 102 172
                 67 147 195
                146 197 222
                209 229 240
                247 247 247
                253 219 199
                244 165 130
                214  96  77
                178  24  43
                103   0  31] ./ 255;
            map = interp1(linspace(0,1,size(anchors,1)), anchors, linspace(0,1,n), 'linear');
            map = min(max(map, 0), 1);
        end
    end
end


function place_(component, row, column)
% Put a component in a grid cell. Auto-placement would do the same thing here,
% but only as long as every strip keeps exactly as many children as it has
% columns -- and a strip whose children silently wrap is the sort of thing
% nobody notices until a control is off the window.
component.Layout.Row = row;
component.Layout.Column = column;
end


function setEnable_(handles, tf)
% Enable or disable a row of controls together with its label.
state = matlab.lang.OnOffSwitchState(tf);
for i = 1:numel(handles)
    if isgraphics(handles(i))
        handles(i).Enable = state;
    end
end
end


function m = mk_(key, field, label, symbol, fcn, opts)
% One catalog entry. Positional for what every metric has, named for what
% distinguishes them, so the catalog above reads as a table.
arguments
    key (1,:) char
    field (1,:) char
    label (1,1) string
    symbol (1,1) string
    fcn (1,1) function_handle
    opts.UsesCorrection (1,1) logical = true
    opts.Neutral (1,1) double = 0
    opts.Range (1,1) double = 2
    opts.NeutralMeaning (1,1) string = ""
    opts.LowWord (1,1) string = ""
    opts.HighWord (1,1) string = ""
    opts.Formula (1,1) string = ""
    opts.Summary (1,1) string = ""
    opts.Reading (1,1) string = ""
    opts.Caution (1,1) string = ""
    opts.References (1,:) string = string.empty(1,0)
end

% Keys rather than text, so a DOI lives once in citations() and a typo in a
% key fails here, when the catalog is built, not as a missing link on screen.
cites = gui.MetricsExplorer.citations(opts.References);

m = struct( ...
    'Key', key, ...
    'Field', field, ...
    'Label', char(label), ...
    'Symbol', char(symbol), ...
    'Fcn', fcn, ...
    'UsesCorrection', opts.UsesCorrection, ...
    'Neutral', opts.Neutral, ...
    'Range', opts.Range, ...
    'NeutralMeaning', char(opts.NeutralMeaning), ...
    'LowWord', char(opts.LowWord), ...
    'HighWord', char(opts.HighWord), ...
    'Formula', char(opts.Formula), ...
    'Summary', char(opts.Summary), ...
    'Reading', char(opts.Reading), ...
    'Caution', char(opts.Caution), ...
    'Reference', strjoin({cites.Short}, '; '), ...
    'Citations', {cites});   % braced, or struct() would expand m to one per citation
end


function c = cite_(key, short, full, doi)
% One citations() entry.
c = struct('Key', key, 'Short', short, 'Full', full, 'DOI', doi);
end


function openReferenceDoc_()
% The in-repository reference, for a rig with no network. The wiki page is
% the guide and is what the Help menu offers first; this is the full text.
root = fileparts(which('epsych_startup'));
docFile = fullfile(root, 'documentation', 'gui', 'gui_MetricsExplorer.md');
if isfile(docFile)
    open(docFile);
else
    gui.MetricsExplorer.openGuide();
end
end
