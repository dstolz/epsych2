classdef Plot
    % behavior.Plot  The offline analysis figures, drawn into an axes you supply.
    %
    % Every figure the behavior analysis window shows -- and every figure a
    % generated script redraws -- is one static call here, over plain data:
    % a behavior.Aggregate.thresholds table, behavior.Session.analyze
    % results, or a behavior.fit common fit struct. Nothing here reads a
    % file, a preference or a runtime, and nothing creates a figure: the
    % caller hands in an axes (a uiaxes in a uigridlayout, or a classic
    % axes), which is CLEARED and redrawn, and gets back a struct of the
    % graphics it now holds.
    %
    %   T = behavior.Aggregate.thresholds(results, catalog.Sessions);
    %   ax = uiaxes(uigridlayout(uifigure, [1 1]));
    %   H = behavior.Plot.groupComparison(ax, T, "Threshold", ...
    %       GroupBy = behavior.Facet("tag", Index = 1), Kind = "box");
    %   H = behavior.Plot.staircaseOverlay(ax, results, catalog.Sessions, Normalize = "fraction");
    %   H = behavior.Plot.psychometric(ax, results(1).Fit, Unit = "dB");
    %
    % Figures:
    %   thresholdTimeline - a threshold per session against time, a line
    %                       per subject, fitted threshold and QC flags
    %   metricTimeline    - any value column against time (learning curves)
    %   groupComparison   - one value per facet level: box, bar or strip,
    %                       with per-subject medians
    %   subjectLines      - the paired picture: a line per subject through
    %                       its per-level medians, and the group mean
    %   staircaseOverlay  - every result's staircase track on one axes
    %   staircaseStack    - the same tracks, a band per facet level stacked
    %                       top to bottom on one scale
    %   staircaseHeatmap  - a row per facet level, a cell per trial position
    %                       coloured by the level held there; cells with no
    %                       data hatched
    %   psychometric      - a fit: proportions, curve, threshold and CI
    %   reversalHistogram - the values at which a staircase reversed
    %
    % CONVENTIONS every figure keeps:
    %   - Every graphics object carries a Tag "BehaviorPlot:<Role>" (Point,
    %     SubjectLine, SubjectMedian, Fit, QC, Box, Bar, Mean, ErrorBar, CI,
    %     Track, Reversal, Threshold, Band, Reference, ScaleBar, Heatmap,
    %     Missing, Curve, Proportion, Histogram, Median, Message, LegendKey,
    %     Legend, ColorBar, NoData), so a test or the window finds them with
    %     findobj rather than by drawing order.
    %   - Nothing to draw -- an empty table, no results, a column of NaN --
    %     is a centred "No data" text, never an error. NaN values are
    %     skipped, never plotted as zero.
    %   - Colours come from palette(), and a facet level's colour is fixed by
    %     its position in the facet's order(T) over the WHOLE table (before
    %     NaN rows are dropped), so a level keeps its colour from one figure
    %     to the next over the same table. colorsFor is the one place that
    %     rule lives. A figure taking ColorMap (staircaseOverlay) may instead
    %     spread a sequential map over an ordered facet's levels.
    %   - Text is drawn with the 'none' interpreter: subject names and tags
    %     carry underscores, which TeX would turn into subscripts.
    %   - The axes' own Tag, UserData and ContextMenu survive the clear, and
    %     its colour bar is removed; every other axes property is reset,
    %     because a datetime x ruler from one figure would refuse the
    %     numeric x of the next.
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.Aggregate, behavior.Facet, behavior.Stats,
    %   behavior.Session.analyze, behavior.fit.Builtin

    properties (Constant)
        % Colour-blind-safe hues (Paul Tol's "muted" set without its green),
        % none of them an epsych.BitMask outcome colour: the outcome green,
        % red, blue, orange and greys mean Hit, Miss, CorrectReject,
        % FalseAlarm and Abort on every other EPsych display.
        PALETTE_HEX = ["#332288" "#44AA99" "#AA4499" "#DDCC77" ...
            "#882255" "#88CCEE" "#999933" "#CC6677"]
        % Boxes and bars when they are not coloured by level, and subject
        % lines that cross colour levels: the live staircase's slate.
        NEUTRAL = [0.420 0.478 0.561]
        % Summary marks (means, error bars, QC rings): near-black, which no
        % palette entry or outcome colour is.
        INK = [0.15 0.15 0.15]
        TAG_PREFIX = "BehaviorPlot:"
        % How a figure that takes ColorMap colours a facet's levels:
        % "categorical" is palette(); the others are sequential maps sampled
        % over the levels in order, for a facet whose order means something
        % (behavior.Facet.isOrdered). "auto" is the sequential default for an
        % ordered facet and categorical for any other. Sequential maps do
        % not keep palette()'s distance from the outcome hues; an overlay
        % draws no outcome, so nothing on it can be mistaken for one.
        COLOR_MAPS = ["auto" "categorical" "parula" "turbo" "cool" "copper" "winter" "gray"]
        % The sequential map "auto" picks.
        AUTO_SEQUENTIAL = "parula"
        % Above this many levels a gradient is keyed by a colour bar and a
        % categorical legend moves outside the axes.
        MAX_LEGEND_LEVELS = 8
        % The longest colour-bar tick label (see compactLabels_).
        MAX_TICK_CHARS = 8
        % Above this many rows (heatmap) or bands (stack) only every k-th
        % is labelled, so the labels stay legible.
        MAX_ROW_LABELS = 30
        % A heatmap cell with no data: this pale ground under diagonal
        % strokes of HATCH_COLOR, HATCH_SPACING pixels apart. No sequential
        % map reaches the ground (each is cut short of white, see
        % sequential), and the strokes keep it apart from gray's light end.
        MISSING_COLOR = [0.93 0.93 0.93]
        HATCH_COLOR = [0.50 0.50 0.50]
        HATCH_SPACING = 7
        % Every other band of a stack is shaded this, so a band reads as a row.
        BAND_SHADE = [0.955 0.958 0.965]
        % How groupComparison and subjectLines draw each level's spread
        % (resolveSpread): "auto" is the SEM -- the bootstrap CI when ShowCI
        % -- except beside a box, which draws its own quartiles and so gets
        % nothing unless ShowCI; the others name one spread for every kind.
        % "sem", "sd" and "ci" are drawn about the mean, "iqr" (Q1 to Q3)
        % and "range" (min to max) about the median.
        SPREADS = ["auto" "none" "sem" "sd" "ci" "iqr" "range"]
    end

    methods (Static)
        function c = palette(n)
            % c = behavior.Plot.palette(n)
            % n colours, n-by-3 RGB in 0..1. The first numel(PALETTE_HEX)
            % are the base hues; beyond that the hues repeat darker, then
            % lighter, then alternate, so no two of the first 24 are equal.
            arguments
                n (1,1) double {mustBeInteger, mustBeNonnegative}
            end
            base = behavior.Plot.hexToRgb_(behavior.Plot.PALETTE_HEX);
            k = size(base, 1);
            c = zeros(n, 3);
            for i = 1:n
                b = base(mod(i - 1, k) + 1, :);
                cycle = floor((i - 1) / k);
                switch mod(cycle, 3)
                    case 0
                        shade = 1 - 0.15 * floor(cycle / 3);
                        c(i, :) = b * max(shade, 0.4);
                    case 1
                        c(i, :) = b * 0.6;
                    case 2
                        c(i, :) = b + (1 - b) * 0.45;
                end
            end
        end

        function [c, levels, idx, map] = colorsFor(facet, T, options)
            % [c, levels, idx, map] = behavior.Plot.colorsFor(facet, T, ColorMap = "categorical")
            % The colour of each level of a facet over a table: level k (in
            % facet.order(T)) gets palette row k, whatever is later drawn --
            % or, with a sequential ColorMap, the map sampled evenly from the
            % first level to the last, "(none)" in NEUTRAL outside the ramp.
            %
            % Returns:
            %   c      - m-by-3 RGB, one row per level
            %   levels - m-by-1 string, the facet's levels in order
            %   idx    - height(T)-by-1, each row's level position
            %   map    - the map used: "categorical" or a sequential name
            %            ("auto" resolved through resolveColorMap)
            arguments
                facet (1,1) behavior.Facet
                T table
                options.ColorMap (1,1) string {behavior.Plot.mustBeColorMap} = "categorical"
            end
            [levels, idx] = facet.order(T);
            map = behavior.Plot.resolveColorMap(options.ColorMap, facet);
            if map == "categorical"
                c = behavior.Plot.palette(numel(levels));
                return
            end
            c = repmat(behavior.Plot.NEUTRAL, numel(levels), 1);
            ramp = levels ~= behavior.Facet.NONE;
            c(ramp, :) = behavior.Plot.sequential(map, sum(ramp));
        end

        function map = resolveColorMap(map, facet)
            % map = behavior.Plot.resolveColorMap(map, facet)
            % "auto" as the map it stands for: AUTO_SEQUENTIAL for an
            % ordered facet (behavior.Facet.isOrdered), else "categorical".
            % Any other name is returned as it is.
            arguments
                map (1,1) string {behavior.Plot.mustBeColorMap}
                facet (1,1) behavior.Facet
            end
            if map == "auto"
                map = "categorical";
                if facet.isOrdered()
                    map = behavior.Plot.AUTO_SEQUENTIAL;
                end
            end
        end

        function c = sequential(map, n)
            % c = behavior.Plot.sequential(map, n)
            % n colours sampled evenly along a sequential map, n-by-3. Each
            % map is cut where it fades into a white axes (parula's yellow,
            % gray's white), so the last level is as visible as the first.
            arguments
                map (1,1) string {mustBeMember(map, ["parula" "turbo" "cool" "copper" "winter" "gray"])}
                n (1,1) double {mustBeInteger, mustBeNonnegative}
            end
            switch map
                case "parula", span = [0 0.88];
                case "turbo",  span = [0.05 0.95];
                case "copper", span = [0.12 0.9];
                case "gray",   span = [0 0.72];
                otherwise,     span = [0 1];
            end
            if n == 1
                at = mean(span);
            else
                at = linspace(span(1), span(2), n);
            end
            base = feval(char(map), 256);
            c = interp1(linspace(0, 1, 256), base, reshape(at, [], 1));
            c = reshape(c, n, 3);
        end

        function mustBeColorMap(map)
            % behavior.Plot.mustBeColorMap(map)
            % Argument validator: map names a COLOR_MAPS entry.
            if ~ismember(string(map), behavior.Plot.COLOR_MAPS)
                error('behavior:Plot:UnknownColorMap', '"%s" is not a colour map (%s).', ...
                    string(map), strjoin(behavior.Plot.COLOR_MAPS, ", "));
            end
        end

        function spread = resolveSpread(spread, options)
            % spread = behavior.Plot.resolveSpread(spread, Kind = "box", ShowCI = false)
            % The spread a comparison of that kind draws: "auto" as the one
            % it stands for (see SPREADS), any other name as it is.
            arguments
                spread (1,1) string {behavior.Plot.mustBeSpread}
                options.Kind (1,1) string {mustBeMember(options.Kind, ["box" "bar" "strip" "lines"])} = "box"
                options.ShowCI (1,1) logical = false
            end
            if spread ~= "auto", return, end
            if options.ShowCI
                spread = "ci";
            elseif options.Kind == "box"
                spread = "none";
            else
                spread = "sem";
            end
        end

        function mustBeSpread(spread)
            % behavior.Plot.mustBeSpread(spread)
            % Argument validator: spread names a SPREADS entry.
            if ~ismember(string(spread), behavior.Plot.SPREADS)
                error('behavior:Plot:UnknownSpread', '"%s" is not a spread (%s).', ...
                    string(spread), strjoin(behavior.Plot.SPREADS, ", "));
            end
        end

        function txt = spreadLabel(spread)
            % txt = behavior.Plot.spreadLabel(spread)
            % What a menu calls a SPREADS entry.
            arguments
                spread (1,1) string {behavior.Plot.mustBeSpread}
            end
            switch spread
                case "auto",  txt = "Auto";
                case "none",  txt = "None";
                case "sem",   txt = "SEM";
                case "sd",    txt = "SD";
                case "ci",    txt = "Bootstrap CI";
                case "iqr",   txt = "IQR";
                case "range", txt = "Range";
            end
        end

        function txt = colorMapLabel(map)
            % txt = behavior.Plot.colorMapLabel(map)
            % What a menu calls a COLOR_MAPS entry.
            arguments
                map (1,1) string {behavior.Plot.mustBeColorMap}
            end
            switch map
                case "auto",        txt = "Auto";
                case "categorical", txt = "Distinct colours";
                otherwise,          txt = "Gradient: " + upper(extractBefore(map, 2)) + extractAfter(map, 1);
            end
        end

        function H = thresholdTimeline(ax, T, options)
            % H = behavior.Plot.thresholdTimeline(ax, T, Name = Value)
            % One marker per session at its time, a line joining each
            % subject's sessions in time order, markers coloured by a facet.
            %
            % Parameters:
            %   ax      - axes or uiaxes (cleared)
            %   T       - behavior.Aggregate.thresholds table
            %   Value   - column to plot (default "Threshold")
            %   ColorBy - behavior.Facet (default subject)
            %   XAxis   - "date" (Start), "session" (SessionOrdinal) or
            %             "days" (DaysSinceFirst)
            %   ShowFit - the fitted threshold (FitThreshold) as a hollow
            %             diamond beside each session (default true; not
            %             drawn when Value is FitThreshold itself)
            %   ShowQC  - ring the sessions with a QC flag (NumQC > 0)
            %
            % Returns:
            %   H - struct Axes, NoData, Legend, SubjectLine, Point, Fit, QC,
            %       LegendKey
            arguments
                ax (1,1)
                T table
                options.Value (1,1) string = "Threshold"
                options.ColorBy (1,1) behavior.Facet = behavior.Facet("subject")
                options.XAxis (1,1) string {mustBeMember(options.XAxis, ["date" "session" "days"])} = "date"
                options.ShowFit (1,1) logical = true
                options.ShowQC (1,1) logical = true
            end
            H = behavior.Plot.timeline_(ax, T, options.Value, options.ColorBy, options.XAxis, ...
                options.ShowFit && options.Value ~= "FitThreshold", options.ShowQC);
        end

        function H = metricTimeline(ax, T, value, options)
            % H = behavior.Plot.metricTimeline(ax, T, value, Name = Value)
            % Any value column against time -- d', abort rate, trials -- with
            % the timeline's conventions: a learning curve per subject.
            %
            % Parameters:
            %   ax, T   - as thresholdTimeline
            %   value   - a column of T (behavior.Aggregate.valueColumns)
            %   ColorBy - behavior.Facet (default subject)
            %   XAxis   - "date", "session" or "days"
            %
            % Returns:
            %   H - struct Axes, NoData, Legend, SubjectLine, Point, Fit
            %       (empty), QC (empty), LegendKey
            arguments
                ax (1,1)
                T table
                value (1,1) string
                options.ColorBy (1,1) behavior.Facet = behavior.Facet("subject")
                options.XAxis (1,1) string {mustBeMember(options.XAxis, ["date" "session" "days"])} = "date"
            end
            H = behavior.Plot.timeline_(ax, T, value, options.ColorBy, options.XAxis, false, false);
        end

        function H = groupComparison(ax, T, value, options)
            % H = behavior.Plot.groupComparison(ax, T, value, Name = Value)
            % One value per level of a facet, levels along x in the facet's
            % order, with the n per level in the tick labels.
            %
            % Parameters:
            %   ax, T              - axes; behavior.Aggregate.thresholds table
            %   value              - a column of T
            %   GroupBy            - behavior.Facet for x (default none)
            %   ColorBy            - behavior.Facet for the points (default subject)
            %   Kind               - "box" (a boxchart per level), "bar" (a bar
            %                        at the mean) or "strip" (points and a
            %                        mean line)
            %   ShowPoints         - jittered session points (always on for strip)
            %   ShowSubjectMedians - each subject's median per level
            %                        (behavior.Aggregate.bySubject) as a
            %                        larger diamond
            %   ShowMean           - each level's mean (default true): the
            %                        bar of a bar chart, the line of a strip,
            %                        a square beside a box
            %   Spread             - the spread drawn per level, one of
            %                        SPREADS (default "auto": SEM, or the
            %                        bootstrap CI when ShowCI; beside a box,
            %                        nothing unless ShowCI). Drawn beside a
            %                        box, on the level otherwise.
            %   ShowCI             - compute the bootstrap CI on the mean
            %                        (behavior.Stats.describe) into Stats,
            %                        and draw it when Spread is "auto"
            %   ConfidenceLevel    - for the CI (default 0.95)
            %   NumBoot            - bootstrap resamples (default 1000)
            %
            % Returns:
            %   H - struct Axes, NoData, Legend, Box, Bar, Mean, ErrorBar, CI,
            %       Spread, Point, SubjectMedian, LegendKey, SpreadKind (the
            %       spread drawn, "auto" resolved), Stats (the describe table,
            %       or [] when none was needed). The spread is tagged CI for
            %       the bootstrap CI and ErrorBar for every other, with
            %       UserData.Spread naming it; H.Spread is it either way.
            arguments
                ax (1,1)
                T table
                value (1,1) string
                options.GroupBy (1,1) behavior.Facet = behavior.Facet("none")
                options.ColorBy (1,1) behavior.Facet = behavior.Facet("subject")
                options.Kind (1,1) string {mustBeMember(options.Kind, ["box" "bar" "strip"])} = "box"
                options.ShowPoints (1,1) logical = true
                options.ShowSubjectMedians (1,1) logical = true
                options.ShowMean (1,1) logical = true
                options.Spread (1,1) string {behavior.Plot.mustBeSpread} = "auto"
                options.ShowCI (1,1) logical = false
                options.ConfidenceLevel (1,1) double {mustBeInRange(options.ConfidenceLevel, 0, 1, "exclusive")} = 0.95
                options.NumBoot (1,1) double {mustBeInteger, mustBePositive} = 1000
            end
            H = behavior.Plot.prepare_(ax, ["Box" "Bar" "Mean" "ErrorBar" "CI" "Spread" "Point" "SubjectMedian" "LegendKey"]);
            spread = behavior.Plot.resolveSpread(options.Spread, Kind = options.Kind, ShowCI = options.ShowCI);
            H.SpreadKind = spread;
            H.Stats = [];
            if ~behavior.Plot.hasRows_(T)
                H = behavior.Plot.noData_(H);
                return
            end
            behavior.Plot.mustHaveColumn_(T, value);
            y = reshape(double(T.(value)), [], 1);
            ok = isfinite(y);
            if ~any(ok)
                H = behavior.Plot.noData_(H, value + " has no finite value.");
                return
            end

            G = options.GroupBy;
            [levels, gidx] = G.order(T);
            m = numel(levels);
            [cols, clev, cidx] = behavior.Plot.colorsFor(options.ColorBy, T);
            sameFacet = G.toText() == options.ColorBy.toText();
            nPer = accumarray(gidx(ok), 1, [m 1]);
            boxCol = repmat(behavior.Plot.NEUTRAL, m, 1);
            if sameFacet
                boxCol = cols;
            end

            % The mean and the spread, from the one describe table the
            % statistics beside the plot are also read from.
            needSummary = options.ShowMean || spread ~= "none" || options.ShowCI;
            mu = nan(m, 1); center = nan(m, 1); lo = nan(m, 1); hi = nan(m, 1);
            if needSummary
                D = behavior.Stats.describe(T, value, GroupBy = G, BootstrapCI = options.ShowCI || spread == "ci", ...
                    ConfidenceLevel = options.ConfidenceLevel, NumBoot = options.NumBoot);
                H.Stats = D;
                [~, at] = ismember(D.Level, levels);
                mu(at) = D.Mean;
                [center(at), lo(at), hi(at), spreadName] = behavior.Plot.spreadOf_(D, spread, options.ConfidenceLevel);
            end

            switch options.Kind
                case "box"
                    for k = 1:m
                        yk = y(ok & gidx == k);
                        if isempty(yk), continue, end
                        b = boxchart(ax, repmat(k, numel(yk), 1), yk, 'BoxFaceColor', boxCol(k, :), ...
                            'BoxWidth', 0.5, 'Tag', behavior.Plot.tag_("Box"));
                        if options.ShowPoints
                            b.MarkerStyle = 'none';     % the points already show every value
                        else
                            b.MarkerColor = behavior.Plot.INK;
                        end
                        H.Box(end+1) = b;
                    end
                case "bar"
                    for k = 1:m
                        if ~options.ShowMean || ~isfinite(mu(k)), continue, end
                        H.Bar(end+1) = bar(ax, k, mu(k), 0.6, 'FaceColor', behavior.Plot.lighten_(boxCol(k, :), 0.55), ...
                            'EdgeColor', boxCol(k, :), 'LineWidth', 1, 'Tag', behavior.Plot.tag_("Bar"), ...
                            'DisplayName', 'Mean');
                    end
                case "strip"
                    for k = 1:m
                        if ~options.ShowMean || ~isfinite(mu(k)), continue, end
                        H.Mean(end+1) = plot(ax, k + [-0.28 0.28], [mu(k) mu(k)], '-', 'Color', behavior.Plot.INK, ...
                            'LineWidth', 2.5, 'Tag', behavior.Plot.tag_("Mean"), 'DisplayName', 'Mean');
                    end
            end

            % Session points, jittered without touching the random stream.
            if options.ShowPoints || options.Kind == "strip"
                jit = behavior.Plot.jitter_(gidx, ok, 0.32);
                for c = 1:numel(clev)
                    rows = ok & cidx == c;
                    if ~any(rows), continue, end
                    H.Point(end+1) = plot(ax, gidx(rows) + jit(rows), y(rows), 'LineStyle', 'none', ...
                        'Marker', 'o', 'MarkerSize', 5, 'MarkerFaceColor', cols(c, :), ...
                        'MarkerEdgeColor', cols(c, :) * 0.6, 'Tag', behavior.Plot.tag_("Point"), ...
                        'DisplayName', sprintf('%s (n=%d)', clev(c), sum(rows)));
                end
            end

            % A box's mean and the spread, drawn over the points so they stay
            % readable; beside a box, not on its median line.
            xs = 1:m;
            if options.Kind == "box"
                xs = xs + 0.36;
                okM = isfinite(mu);
                if options.ShowMean && any(okM)
                    H.Mean = plot(ax, xs(okM), mu(okM), 'LineStyle', 'none', 'Marker', 's', 'MarkerSize', 6, ...
                        'MarkerFaceColor', behavior.Plot.INK, 'MarkerEdgeColor', behavior.Plot.INK, ...
                        'Tag', behavior.Plot.tag_("Mean"), 'DisplayName', 'Mean');
                end
            end
            if spread ~= "none" && needSummary
                [H.Spread, tagName] = behavior.Plot.spreadBars_(ax, reshape(xs, [], 1), center, lo, hi, ...
                    spread, spreadName, 1.5, 10, "groupComparison");
                if ~isempty(H.Spread)
                    H.(tagName) = H.Spread;
                end
            end

            if options.ShowSubjectMedians
                [H.SubjectMedian, key] = behavior.Plot.subjectMedians_(ax, T, value, G, levels, cols, cidx);
                if ~isempty(key)
                    H.LegendKey(end+1) = key;
                end
            end

            ax.XTick = 1:m;
            ax.XTickLabel = compose("%s (n=%d)", levels, nPer);
            ax.TickLabelInterpreter = 'none';
            xlim(ax, [0.4, m + 0.6]);
            xlabel(ax, G.label(), 'Interpreter', 'none');
            ylabel(ax, behavior.Plot.valueLabel_(T, value), 'Interpreter', 'none');
            meanKey = [H.Bar(1:min(1, end)) H.Mean(1:min(1, end))];   % one entry, whatever the mean is drawn as
            H.Legend = behavior.Plot.legend_(ax, [H.Point meanKey H.Spread H.LegendKey], options.ColorBy.label());
            hold(ax, 'off');
        end

        function H = subjectLines(ax, T, value, options)
            % H = behavior.Plot.subjectLines(ax, T, value, Name = Value)
            % The paired-design picture: x is a facet's levels in order
            % (Pre, Post, ...), one line per subject through its per-level
            % medians, and the mean of those medians per level as a heavier
            % line with its spread (by default the SEM).
            %
            % Parameters:
            %   ax, T           - axes; behavior.Aggregate.thresholds table
            %   value           - a column of T
            %   XAxis           - behavior.Facet for x (default tag:1)
            %   ColorBy         - behavior.Facet for the lines (default
            %                     subject); a subject whose sessions span
            %                     several levels of it is drawn in the
            %                     neutral colour
            %   ShowMean        - the line through the means of the subject
            %                     medians (default true)
            %   Spread          - their spread per level, one of SPREADS
            %                     (default "auto": SEM, or the bootstrap CI
            %                     when ShowCI)
            %   ShowCI          - compute the bootstrap CI into Stats, and
            %                     draw it when Spread is "auto"
            %   ConfidenceLevel - for the CI (default 0.95)
            %   NumBoot         - bootstrap resamples (default 1000)
            %
            % Returns:
            %   H - struct Axes, NoData, Legend, SubjectLine, Mean, ErrorBar,
            %       CI, Spread, SpreadKind, Stats (describe over subjects), as
            %       groupComparison's
            arguments
                ax (1,1)
                T table
                value (1,1) string
                options.XAxis (1,1) behavior.Facet = behavior.Facet("tag", Index = 1)
                options.ColorBy (1,1) behavior.Facet = behavior.Facet("subject")
                options.ShowMean (1,1) logical = true
                options.Spread (1,1) string {behavior.Plot.mustBeSpread} = "auto"
                options.ShowCI (1,1) logical = false
                options.ConfidenceLevel (1,1) double {mustBeInRange(options.ConfidenceLevel, 0, 1, "exclusive")} = 0.95
                options.NumBoot (1,1) double {mustBeInteger, mustBePositive} = 1000
            end
            H = behavior.Plot.prepare_(ax, ["SubjectLine" "Mean" "ErrorBar" "CI" "Spread"]);
            spread = behavior.Plot.resolveSpread(options.Spread, Kind = "lines", ShowCI = options.ShowCI);
            H.SpreadKind = spread;
            H.Stats = [];
            if ~behavior.Plot.hasRows_(T)
                H = behavior.Plot.noData_(H);
                return
            end
            behavior.Plot.mustHaveColumn_(T, value);
            X = options.XAxis;
            S = behavior.Aggregate.bySubject(T, value, GroupBy = X);
            S = S(isfinite(S.Median), :);
            if height(S) == 0
                H = behavior.Plot.noData_(H, value + " has no finite value.");
                return
            end
            [levels, ~] = X.order(T);
            m = numel(levels);
            [cols, clev, cidx] = behavior.Plot.colorsFor(options.ColorBy, T);
            subj = string(T.Subject);

            for s = reshape(behavior.Aggregate.naturalUnique(S.Subject), 1, [])
                rows = S.Subject == s;
                [~, pos] = ismember(S.Level(rows), levels);
                med = S.Median(rows);
                [pos, k] = sort(pos);
                med = med(k);
                c = unique(cidx(subj == s));
                if isscalar(c)
                    col = cols(c, :);
                    name = clev(c);
                    level = c;
                else
                    col = behavior.Plot.NEUTRAL;
                    name = s + " (mixed " + options.ColorBy.label() + ")";
                    level = Inf;
                end
                h = plot(ax, pos, med, '-o', 'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 6, ...
                    'LineWidth', 1.2, 'Tag', behavior.Plot.tag_("SubjectLine"), 'DisplayName', name, ...
                    'UserData', struct('Subject', s, 'Level', level));
                H.SubjectLine(end+1) = h;
            end

            D = behavior.Stats.describe(T, value, GroupBy = X, Unit = "subject", ...
                BootstrapCI = options.ShowCI || spread == "ci", ...
                ConfidenceLevel = options.ConfidenceLevel, NumBoot = options.NumBoot);
            H.Stats = D;
            [~, at] = ismember(D.Level, levels);
            okD = at > 0 & D.N > 0;
            if any(okD)
                Dk = D(okD, :);
                x = reshape(at(okD), [], 1);
                if spread ~= "none"
                    % One subject has no spread: that level just has none.
                    [center, lo, hi, spreadName] = behavior.Plot.spreadOf_(Dk, spread, options.ConfidenceLevel);
                    [H.Spread, tagName] = behavior.Plot.spreadBars_(ax, x, center, lo, hi, spread, ...
                        spreadName + " of subject medians", 2, 8, "subjectLines");
                    if ~isempty(H.Spread)
                        H.(tagName) = H.Spread;
                    end
                end
                if options.ShowMean
                    H.Mean = plot(ax, x, Dk.Mean, '-s', 'Color', behavior.Plot.INK, ...
                        'MarkerFaceColor', behavior.Plot.INK, 'MarkerSize', 8, 'LineWidth', 2.5, ...
                        'Tag', behavior.Plot.tag_("Mean"), ...
                        'DisplayName', sprintf('Mean of subject medians (n=%d)', numel(unique(S.Subject))));
                end
            end

            nSub = arrayfun(@(L) sum(S.Level == L), levels);
            ax.XTick = 1:m;
            ax.XTickLabel = compose("%s (n=%d)", levels, nSub);
            ax.TickLabelInterpreter = 'none';
            xlim(ax, [0.6, m + 0.4]);
            xlabel(ax, X.label(), 'Interpreter', 'none');
            ylabel(ax, behavior.Plot.valueLabel_(T, value) + ", subject median", 'Interpreter', 'none');
            H.Legend = behavior.Plot.legend_(ax, [behavior.Plot.firstPerName_(H.SubjectLine) H.Mean H.Spread], ...
                options.ColorBy.label());
            hold(ax, 'off');
        end

        function H = staircaseOverlay(ax, results, sessions, options)
            % H = behavior.Plot.staircaseOverlay(ax, results, sessions, Name = Value)
            % Every result's staircase track on one axes, coloured by a
            % facet of its session.
            %
            % Parameters:
            %   ax             - axes or uiaxes
            %   results        - behavior.Session.analyze results (struct
            %                    array or cell)
            %   sessions       - the table the facet reads (a catalog's
            %                    Sessions or an Aggregate table); matched to
            %                    the results by Key through
            %                    behavior.Aggregate.thresholds' join. []
            %                    uses what the results themselves carry.
            %   ColorBy        - behavior.Facet (default subject)
            %   ColorMap       - one of COLOR_MAPS (default "auto": a
            %                    gradient for an ordered facet such as
            %                    session or date, distinct colours
            %                    otherwise). A gradient is keyed by a colour
            %                    bar once it has more than MAX_LEGEND_LEVELS
            %                    levels, and by the legend below that.
            %   Normalize      - "none" (x = trial number in the session),
            %                    "trial" (included stimulus trials 1..n) or
            %                    "fraction" (k/n, so every track ends at 1)
            %   Steps          - draw each track as steps (default true): a
            %                    staircase HOLDS its level until the next
            %                    trial, which a sloped line misrepresents
            %   ShowReversals  - mark each reversal
            %   ShowThresholds - each result's Threshold as a marker at its
            %                    track's end, drawn over every track
            %   Unit           - y unit; "" = the results' Unit
            %
            % Tracks are drawn in level order, so with a gradient the latest
            % level lies on top.
            %
            % Returns:
            %   H - struct Axes, NoData, Legend, Track, Reversal, Threshold,
            %       LegendKey, ColorBar, ColorMap (the map used, "auto"
            %       resolved); H.Track(k).UserData.Key names the session
            arguments
                ax (1,1)
                results
                sessions = []
                options.ColorBy (1,1) behavior.Facet = behavior.Facet("subject")
                options.ColorMap (1,1) string {behavior.Plot.mustBeColorMap} = "auto"
                options.Normalize (1,1) string {mustBeMember(options.Normalize, ["none" "trial" "fraction"])} = "none"
                options.Steps (1,1) logical = true
                options.ShowReversals (1,1) logical = false
                options.ShowThresholds (1,1) logical = true
                options.Unit (1,1) string = ""
            end
            H = behavior.Plot.prepare_(ax, ["Track" "Reversal" "Threshold" "LegendKey" "ColorBar"]);
            H.ColorMap = behavior.Plot.resolveColorMap(options.ColorMap, options.ColorBy);
            R = behavior.Plot.asResults_(results);
            if isempty(R)
                H = behavior.Plot.noData_(H);
                return
            end
            % The join gives every result the facet columns its session has.
            T = behavior.Aggregate.thresholds(R, sessions);
            [cols, clev, cidx, map] = behavior.Plot.colorsFor(options.ColorBy, T, ColorMap = options.ColorMap);
            nPer = accumarray(cidx, 1, [numel(clev) 1]);
            gradient = map ~= "categorical";
            lw = 1.5;
            if numel(R) > 12
                lw = 1;             % a dense overlay reads better thin
            end

            thX = nan(1, numel(R)); thY = thX; thC = nan(numel(R), 3);
            [X, V, REV] = behavior.Plot.tracks_(R, options.Normalize);
            [~, drawOrder] = sort(cidx);       % stable: within a level, as given
            for k = reshape(drawOrder, 1, [])
                x = X{k}; v = V{k}; rev = REV{k};
                if isempty(v), continue, end
                c = cidx(k);
                col = cols(c, :);
                name = clev(c);
                if any(nPer > 1)        % one session per level (session #, date) needs no count
                    name = sprintf('%s (n=%d)', clev(c), nPer(c));
                end
                args = {'Color', col, 'LineWidth', lw, 'Tag', behavior.Plot.tag_("Track"), ...
                    'DisplayName', name, ...
                    'UserData', struct('Key', string(R(k).Key), 'Level', c)};
                if options.Steps
                    h = stairs(ax, x, v, args{:});
                else
                    h = plot(ax, x, v, '-', args{:});
                end
                H.Track(end+1) = h;
                if options.ShowReversals && any(rev)
                    H.Reversal(end+1) = plot(ax, x(rev), v(rev), 'LineStyle', 'none', 'Marker', 'o', ...
                        'MarkerSize', 4.5, 'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'LineWidth', 0.5, ...
                        'Tag', behavior.Plot.tag_("Reversal"));
                end
                th = double(R(k).Threshold);
                if options.ShowThresholds && isscalar(th) && isfinite(th)
                    thX(k) = x(end); thY(k) = th; thC(k, :) = col;
                end
            end
            if isempty(H.Track)
                H = behavior.Plot.noData_(H, "No result has a staircase track.");
                return
            end

            % Thresholds last, so no later track hides an earlier one's.
            for k = reshape(drawOrder, 1, [])
                if isnan(thY(k)), continue, end
                H.Threshold(end+1) = plot(ax, thX(k), thY(k), 'LineStyle', 'none', 'Marker', 'o', ...
                    'MarkerSize', 7, 'MarkerFaceColor', thC(k, :), 'MarkerEdgeColor', behavior.Plot.INK, ...
                    'LineWidth', 1, 'Tag', behavior.Plot.tag_("Threshold"));
            end
            if ~isempty(H.Threshold)
                H.LegendKey(end+1) = behavior.Plot.markerKey_(ax, 'o', 7, 'w', ...
                    sprintf('Session threshold (n=%d)', numel(H.Threshold)));
            end
            if ~isempty(H.Reversal)
                H.LegendKey(end+1) = behavior.Plot.markerKey_(ax, 'o', 4.5, behavior.Plot.NEUTRAL, 'Reversal');
            end

            if options.Normalize == "fraction"
                xlim(ax, [0 1]);
            end
            grid(ax, 'on');
            ax.GridAlpha = 0.1;
            ax.TickDir = 'out';
            xlabel(ax, behavior.Plot.trackAxisLabel_(options.Normalize), 'Interpreter', 'none');
            ylabel(ax, behavior.Plot.parameterLabel_(R, options.Unit, ""), 'Interpreter', 'none');

            % The key: a colour bar for a long gradient, the legend otherwise.
            ramp = clev ~= behavior.Facet.NONE;
            levelKeys = behavior.Plot.firstPerName_(H.Track);
            legendTitle = options.ColorBy.label();
            if gradient && sum(ramp) > behavior.Plot.MAX_LEGEND_LEVELS
                H.ColorBar = behavior.Plot.levelColorBar_(ax, cols(ramp, :), clev(ramp), legendTitle);
                lvl = arrayfun(@(h) h.UserData.Level, levelKeys);
                levelKeys = levelKeys(~ramp(lvl));          % "(none)" still needs its entry
                if isempty(levelKeys)
                    legendTitle = "";                       % the colour bar is already titled
                end
            end
            entries = [levelKeys H.LegendKey];
            loc = 'best';
            if numel(entries) > behavior.Plot.MAX_LEGEND_LEVELS
                loc = 'eastoutside';
            end
            H.Legend = behavior.Plot.legend_(ax, entries, legendTitle, loc);
            hold(ax, 'off');
        end

        function H = staircaseStack(ax, results, sessions, options)
            % H = behavior.Plot.staircaseStack(ax, results, sessions, Name = Value)
            % The overlay's tracks pulled apart: a band per level of a facet
            % (a session, by default), stacked top to bottom in the facet's
            % order on one shared x.
            %
            % Every band is the same height and the same scale -- the whole
            % range of the tracked values -- so where a track sits inside its
            % band compares from band to band. A scale bar beside the bottom
            % band gives that scale in the parameter's units, and a dotted
            % reference line at the same value in every band (the median
            % threshold, by default) gives the eye one level to compare
            % against. Sessions sharing a level share its band and its colour.
            %
            % Parameters:
            %   ax, results, sessions - as staircaseOverlay
            %   Rows           - behavior.Facet: a band per level (default
            %                    session, a band per session of one subject)
            %   ColorMap       - one of COLOR_MAPS, colouring each band's
            %                    tracks as staircaseOverlay colours its levels
            %   Normalize, Steps, ShowReversals, ShowThresholds, Unit - as
            %                    staircaseOverlay
            %   Reference      - "median" (of the finite thresholds), "none",
            %                    or a value in the parameter's units; a value
            %                    outside the tracks' range is not drawn
            %   Gap            - space between bands as a fraction of a
            %                    band's height (default 0.15)
            %
            % A level none of whose sessions has a staircase keeps its band,
            % with "No staircase" across it, so a missing session shows as a
            % gap rather than the stack silently closing up.
            %
            % Returns:
            %   H - struct Axes, NoData, Legend, Band, Track, Reversal,
            %       Threshold, Reference, ScaleBar (the bar and its label),
            %       Missing, LegendKey, ColorMap, Levels (the bands, top to
            %       bottom), Offsets (band k draws value v at
            %       Offsets(k) + v - ValueRange(1)), ValueRange;
            %       H.Track(k).UserData.Key names the session
            arguments
                ax (1,1)
                results
                sessions = []
                options.Rows (1,1) behavior.Facet = behavior.Facet("session")
                options.ColorMap (1,1) string {behavior.Plot.mustBeColorMap} = "auto"
                options.Normalize (1,1) string {mustBeMember(options.Normalize, ["none" "trial" "fraction"])} = "none"
                options.Steps (1,1) logical = true
                options.ShowReversals (1,1) logical = false
                options.ShowThresholds (1,1) logical = true
                options.Reference {localMustBeReference} = "median"
                options.Gap (1,1) double {mustBeNonnegative, mustBeFinite} = 0.15
                options.Unit (1,1) string = ""
            end
            H = behavior.Plot.prepare_(ax, ["Band" "Track" "Reversal" "Threshold" "Reference" ...
                "ScaleBar" "Missing" "LegendKey"]);
            H.ColorMap = behavior.Plot.resolveColorMap(options.ColorMap, options.Rows);
            H.Levels = strings(0, 1);
            H.Offsets = zeros(0, 1);
            H.ValueRange = [NaN NaN];
            R = behavior.Plot.asResults_(results);
            if isempty(R)
                H = behavior.Plot.noData_(H);
                return
            end
            T = behavior.Aggregate.thresholds(R, sessions);
            [cols, levels, idx] = behavior.Plot.colorsFor(options.Rows, T, ColorMap = options.ColorMap);
            m = numel(levels);
            nPer = accumarray(idx, 1, [m 1]);
            [X, V, REV] = behavior.Plot.tracks_(R, options.Normalize);
            allV = [V{:}];
            if isempty(allV)
                H = behavior.Plot.noData_(H, "No result has a staircase track.");
                return
            end

            % One scale for every band: the whole range of the tracks.
            lo = min(allV);
            span = max(allV) - lo;
            if span <= 0                         % a flat track: give it room
                span = max(abs(lo) * 0.1, 1);
                lo = lo - span / 2;
            end
            gap = options.Gap * span;
            base = ((m - (1:m)) * (span + gap)).';      % first level on top
            allX = [X{:}];
            x0 = min(allX);
            x1 = max(allX);
            if options.Normalize == "fraction"
                x0 = 0; x1 = 1;
            end
            if x1 <= x0, x1 = x0 + 1; end
            xspan = x1 - x0;
            xEnd = x1 + 0.13 * xspan;            % room for the scale bar
            H.Levels = levels;
            H.Offsets = base;
            H.ValueRange = [lo, lo + span];

            for k = 1:2:m
                H.Band(end+1) = patch(ax, [x0 xEnd xEnd x0], base(k) + [-gap -gap 2*span+gap 2*span+gap] / 2, ...
                    behavior.Plot.BAND_SHADE, 'EdgeColor', 'none', 'PickableParts', 'none', ...
                    'Tag', behavior.Plot.tag_("Band"));
            end

            unit = behavior.Plot.resultUnit_(R, options.Unit);
            has = accumarray(idx, ~cellfun(@isempty, V), [m 1], @any);   % bands with a track
            ref = behavior.Plot.referenceValue_(R, options.Reference);
            if isfinite(ref) && ref >= lo && ref <= lo + span
                ry = base(has) + ref - lo;
                xs = repmat([x0 x1 NaN], numel(ry), 1).';
                ys = [ry ry nan(numel(ry), 1)].';
                what = "Reference";
                if ~isnumeric(options.Reference), what = "Median threshold"; end
                H.Reference = plot(ax, xs(:), ys(:), ':', 'Color', behavior.Plot.INK, 'LineWidth', 1, ...
                    'Tag', behavior.Plot.tag_("Reference"), ...
                    'DisplayName', what + " " + behavior.Plot.valueText_(ref, unit));
            end

            lw = 1.25;
            if numel(R) > 12
                lw = 1;
            end
            thX = nan(1, numel(R)); thY = thX; thC = nan(numel(R), 3);
            [~, drawOrder] = sort(idx);
            for k = reshape(drawOrder, 1, [])
                x = X{k}; v = V{k}; rev = REV{k};
                if isempty(v), continue, end
                c = idx(k);
                y = base(c) + v - lo;
                args = {'Color', cols(c, :), 'LineWidth', lw, 'Tag', behavior.Plot.tag_("Track"), ...
                    'DisplayName', levels(c), 'UserData', struct('Key', string(R(k).Key), 'Level', c)};
                if options.Steps
                    H.Track(end+1) = stairs(ax, x, y, args{:});
                else
                    H.Track(end+1) = plot(ax, x, y, '-', args{:});
                end
                if options.ShowReversals && any(rev)
                    H.Reversal(end+1) = plot(ax, x(rev), y(rev), 'LineStyle', 'none', 'Marker', 'o', ...
                        'MarkerSize', 4, 'MarkerFaceColor', cols(c, :), 'MarkerEdgeColor', 'w', 'LineWidth', 0.5, ...
                        'Tag', behavior.Plot.tag_("Reversal"));
                end
                th = double(R(k).Threshold);
                if options.ShowThresholds && isscalar(th) && isfinite(th)
                    thX(k) = x(end); thY(k) = base(c) + th - lo; thC(k, :) = cols(c, :);
                end
            end
            for k = reshape(drawOrder, 1, [])
                if isnan(thY(k)), continue, end
                H.Threshold(end+1) = plot(ax, thX(k), thY(k), 'LineStyle', 'none', 'Marker', 'o', ...
                    'MarkerSize', 6, 'MarkerFaceColor', thC(k, :), 'MarkerEdgeColor', behavior.Plot.INK, ...
                    'LineWidth', 1, 'Tag', behavior.Plot.tag_("Threshold"));
            end
            for c = reshape(find(~has), 1, [])
                H.Missing(end+1) = text(ax, x0 + xspan / 2, base(c) + span / 2, "No staircase", ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontAngle', 'italic', ...
                    'Color', behavior.Plot.HATCH_COLOR, 'Interpreter', 'none', 'Tag', behavior.Plot.tag_("Missing"));
            end

            % The scale bar, centred in the bottom band.
            L = behavior.Plot.niceLength_(span);
            xb = x1 + 0.03 * xspan;
            yb = base(m) + (span - L) / 2;
            H.ScaleBar = plot(ax, [xb xb], [yb yb + L], '-', 'Color', behavior.Plot.INK, 'LineWidth', 2, ...
                'Tag', behavior.Plot.tag_("ScaleBar"));
            H.ScaleBar(2) = text(ax, xb + 0.012 * xspan, yb + L / 2, behavior.Plot.valueText_(L, unit), ...
                'VerticalAlignment', 'middle', 'Color', behavior.Plot.INK, 'Interpreter', 'none', ...
                'Clipping', 'off', 'Tag', behavior.Plot.tag_("ScaleBar"));

            if ~isempty(H.Threshold)
                H.LegendKey(end+1) = behavior.Plot.markerKey_(ax, 'o', 6, 'w', ...
                    sprintf('Session threshold (n=%d)', numel(H.Threshold)));
            end
            if ~isempty(H.Reversal)
                H.LegendKey(end+1) = behavior.Plot.markerKey_(ax, 'o', 4, behavior.Plot.NEUTRAL, 'Reversal');
            end

            xlim(ax, [x0 xEnd]);
            ylim(ax, [base(m) - gap / 2, base(1) + span + gap / 2]);
            t = ax.XTick;
            ax.XTick = t(t <= x1 + 1e-9);        % no tick under the scale bar
            [ticks, labels] = behavior.Plot.rowTicks_(levels, nPer);
            ax.YTick = flip(base(ticks) + span / 2);
            ax.YTickLabel = cellstr(flip(labels(ticks)));
            ax.TickLabelInterpreter = 'none';
            ax.TickDir = 'out';
            ax.XGrid = 'on';
            ax.GridAlpha = 0.1;
            xlabel(ax, behavior.Plot.trackAxisLabel_(options.Normalize), 'Interpreter', 'none');
            ylabel(ax, options.Rows.label(), 'Interpreter', 'none');
            H.Legend = behavior.Plot.legend_(ax, [H.Reference H.LegendKey], "", 'southoutside');
            if ~isempty(H.Legend)
                H.Legend.Orientation = 'horizontal';
            end
            hold(ax, 'off');
        end

        function H = staircaseHeatmap(ax, results, sessions, options)
            % H = behavior.Plot.staircaseHeatmap(ax, results, sessions, Name = Value)
            % A row per level of a facet (a session, by default), first
            % level at the top, and a cell per trial position, coloured by
            % the level the staircase held there.
            %
            % A cell with no data -- before a session's first included
            % stimulus trial or after its last, past the end of a shorter
            % session, every cell of a session with no staircase -- is NOT
            % coloured: it is hatched on a pale ground (MISSING_COLOR,
            % HATCH_COLOR) that no colour map reaches, and named in a key
            % below the axes. A row with no data at all says so in its label.
            %
            % Columns follow Normalize, as the overlay's x does:
            %   "none"     - trial number in the session. A staircase HOLDS
            %                its level between its stimulus trials (the
            %                overlay's steps), so catch trials and aborts
            %                inside the window carry the level before them
            %                rather than showing as gaps.
            %   "trial"    - included stimulus trial 1..n
            %   "fraction" - NumBins equal slices of each session's included
            %                stimulus trials, so every row spans the width
            %
            % Parameters:
            %   ax, results, sessions - as staircaseOverlay
            %   Rows          - behavior.Facet: a row per level (default
            %                   session)
            %   ColorMap      - one of COLOR_MAPS; a heatmap is always a
            %                   gradient, so "auto" and "categorical" draw it
            %                   in AUTO_SEQUENTIAL
            %   Normalize     - "none", "trial" or "fraction"
            %   NumBins       - columns for "fraction" (default 100)
            %   Combine       - how a row with several sessions combines them
            %                   per cell: "mean" (default) or "median" of the
            %                   sessions with data there
            %   ShowReversals - mark the reversals in rows of one session
            %   CLim          - colour limits ([] = the finite cells' range)
            %   Unit          - colour-bar unit; "" = the results' Unit
            %
            % Returns:
            %   H - struct Axes, NoData, Legend, Heatmap (the image), Missing
            %       (the hatch), Reversal, LegendKey, ColorBar, ColorMap,
            %       Levels (the rows, top to bottom), Count (sessions per
            %       row), Grid (rows-by-columns values, NaN = no data), X
            %       (each column's centre)
            arguments
                ax (1,1)
                results
                sessions = []
                options.Rows (1,1) behavior.Facet = behavior.Facet("session")
                options.ColorMap (1,1) string {behavior.Plot.mustBeColorMap} = "auto"
                options.Normalize (1,1) string {mustBeMember(options.Normalize, ["none" "trial" "fraction"])} = "none"
                options.NumBins (1,1) double {mustBeInteger, mustBePositive} = 100
                options.Combine (1,1) string {mustBeMember(options.Combine, ["mean" "median"])} = "mean"
                options.ShowReversals (1,1) logical = false
                options.CLim double {mustBeFinite} = []
                options.Unit (1,1) string = ""
            end
            H = behavior.Plot.prepare_(ax, ["Heatmap" "Missing" "Reversal" "LegendKey" "ColorBar"]);
            H.ColorMap = options.ColorMap;
            if ismember(H.ColorMap, ["auto" "categorical"])
                H.ColorMap = behavior.Plot.AUTO_SEQUENTIAL;
            end
            H.Levels = strings(0, 1);
            H.Count = zeros(0, 1);
            H.Grid = zeros(0, 0);
            H.X = zeros(1, 0);
            R = behavior.Plot.asResults_(results);
            if isempty(R)
                H = behavior.Plot.noData_(H);
                return
            end
            if ~isempty(options.CLim) && ~(numel(options.CLim) == 2 && options.CLim(1) < options.CLim(2))
                error('behavior:Plot:InvalidCLim', 'CLim must be [low high] with low < high.');
            end
            T = behavior.Aggregate.thresholds(R, sessions);
            [levels, idx] = options.Rows.order(T);
            m = numel(levels);
            nPer = accumarray(idx, 1, [m 1]);
            [~, V, REV, TI] = behavior.Plot.tracks_(R, "none");
            n = numel(R);
            switch options.Normalize
                case "none"
                    nc = ceil(max([0; cellfun(@(t) max([0 t]), TI)]));
                    xc = 1:nc;
                case "trial"
                    nc = max(cellfun(@numel, V));
                    xc = 1:nc;
                case "fraction"
                    nc = options.NumBins;
                    xc = ((1:nc) - 0.5) / nc;
            end
            if nc == 0 || all(cellfun(@isempty, V))
                H = behavior.Plot.noData_(H, "No result has a staircase track.");
                return
            end
            each = nan(n, nc);
            for k = 1:n
                each(k, :) = behavior.Plot.heatmapRow_(TI{k}, V{k}, options.Normalize, nc);
            end
            G = nan(m, nc);
            for c = 1:m
                rows = each(idx == c, :);
                if size(rows, 1) == 1
                    G(c, :) = rows;
                elseif options.Combine == "mean"
                    G(c, :) = mean(rows, 1, 'omitnan');
                else
                    G(c, :) = median(rows, 1, 'omitnan');
                end
            end
            fin = isfinite(G);
            dx = 1;
            if options.Normalize == "fraction", dx = 1 / nc; end
            H.Levels = levels;
            H.Count = nPer;
            H.Grid = G;
            H.X = xc;

            lim = options.CLim;
            if isempty(lim)
                lim = [min(G(fin)) max(G(fin))];
                if lim(1) == lim(2), lim = lim + [-0.5 0.5]; end
            end
            colormap(ax, behavior.Plot.sequential(H.ColorMap, 256));
            ax.CLim = lim;
            ax.Color = behavior.Plot.MISSING_COLOR;
            H.Heatmap = image(ax, 'XData', xc([1 end]), 'YData', [1 m], 'CData', G, ...
                'CDataMapping', 'scaled', 'AlphaData', double(fin), 'Tag', behavior.Plot.tag_("Heatmap"));
            ax.YDir = 'reverse';
            ax.Layer = 'top';
            xlim(ax, [xc(1) - dx / 2, xc(end) + dx / 2]);
            ylim(ax, [0.5, m + 0.5]);

            if options.ShowReversals
                % Only where a row IS one session: a combined row has no
                % single track whose reversals could be marked.
                [rx, ry] = deal(cell(1, n));
                for k = 1:n
                    c = idx(k);
                    if nPer(c) ~= 1 || ~any(REV{k}), continue, end
                    at = find(REV{k});
                    switch options.Normalize
                        case "none",     rx{k} = TI{k}(at);
                        case "trial",    rx{k} = at;
                        case "fraction", rx{k} = (at - 0.5) / numel(V{k});
                    end
                    ry{k} = repmat(c, 1, numel(at));
                end
                rx = [rx{:}];
                if ~isempty(rx)
                    H.Reversal = plot(ax, rx, [ry{:}], 'LineStyle', 'none', 'Marker', 'o', 'MarkerSize', 3.5, ...
                        'MarkerFaceColor', 'w', 'MarkerEdgeColor', behavior.Plot.INK, 'LineWidth', 0.5, ...
                        'Tag', behavior.Plot.tag_("Reversal"));
                    H.LegendKey(end+1) = behavior.Plot.markerKey_(ax, 'o', 3.5, 'w', 'Reversal');
                end
            end

            [ticks, labels] = behavior.Plot.rowTicks_(levels, nPer);
            empty = ~any(fin, 2);
            labels(empty) = labels(empty) + " (no staircase)";
            ax.YTick = ticks;
            ax.YTickLabel = cellstr(labels(ticks));
            ax.TickLabelInterpreter = 'none';
            ax.TickDir = 'out';
            xlabel(ax, behavior.Plot.trackAxisLabel_(options.Normalize), 'Interpreter', 'none');
            ylabel(ax, options.Rows.label(), 'Interpreter', 'none');
            H.ColorBar = colorbar(ax, 'Tag', behavior.Plot.tag_("ColorBar"));
            H.ColorBar.Label.String = behavior.Plot.parameterLabel_(R, options.Unit, "");
            H.ColorBar.Label.Interpreter = 'none';

            if ~all(fin(:))
                H.Missing = behavior.Plot.hatch_(ax, ~fin, xc, dx);
                H.LegendKey = [patch(ax, NaN, NaN, behavior.Plot.MISSING_COLOR, ...
                    'EdgeColor', behavior.Plot.HATCH_COLOR, 'Tag', behavior.Plot.tag_("LegendKey"), ...
                    'DisplayName', sprintf('No data, hatched (%d of %d cells)', sum(~fin(:)), numel(fin))) H.LegendKey];
            end
            H.Legend = behavior.Plot.legend_(ax, H.LegendKey, "", 'southoutside');
            if ~isempty(H.Legend)
                H.Legend.Orientation = 'horizontal';
            end
            hold(ax, 'off');
        end

        function H = psychometric(ax, F, options)
            % H = behavior.Plot.psychometric(ax, F, Name = Value)
            % A psychometric fit in the common schema (behavior.fit.Builtin):
            % the proportion of "yes" per level, the fitted curve, and the
            % threshold with its confidence interval.
            %
            % Parameters:
            %   ax         - axes or uiaxes
            %   F          - common fit struct (R.Fit of an analysis result)
            %   Unit       - x unit for the label
            %   ShowCI     - the threshold CI as a shaded band, when finite
            %   ShowCounts - marker area grows with NumTotal at the level
            %
            % A fit that did not converge (or cannot be identified) draws the
            % proportions only and writes F.Message into the axes.
            %
            % Returns:
            %   H - struct Axes, NoData, Legend, Proportion, Curve, Threshold,
            %       CI, Message
            arguments
                ax (1,1)
                F
                options.Unit (1,1) string = ""
                options.ShowCI (1,1) logical = true
                options.ShowCounts (1,1) logical = true
            end
            H = behavior.Plot.prepare_(ax, ["Proportion" "Curve" "Threshold" "CI" "Message"]);
            if ~isstruct(F) || isempty(F)
                H = behavior.Plot.noData_(H);
                return
            end
            F = F(1);
            lv = reshape(double(F.Levels), [], 1);
            p = reshape(double(F.Proportion), [], 1);
            nt = reshape(double(F.NumTotal), [], 1);
            ok = isfinite(lv) & isfinite(p);
            msg = strtrim(string(F.Message));
            if ~any(ok)
                H = behavior.Plot.noData_(H, msg);
                return
            end
            good = logical(F.Converged) && logical(F.Identifiable);
            col = behavior.Plot.palette(1);

            th = double(F.Threshold);
            lo = double(F.CI.ThresholdLo);
            hi = double(F.CI.ThresholdHi);
            if good && options.ShowCI && isfinite(lo) && isfinite(hi)
                H.CI = patch(ax, [lo hi hi lo], [0 0 1 1], col, 'FaceAlpha', 0.15, 'EdgeColor', 'none', ...
                    'Tag', behavior.Plot.tag_("CI"), ...
                    'DisplayName', sprintf('%g%% CI', 100 * double(F.CI.Level)));
            end

            if options.ShowCounts && any(isfinite(nt(ok)) & nt(ok) > 0)
                sz = 20 + 160 * nt(ok) / max(nt(ok));
            else
                sz = 40;
            end
            H.Proportion = scatter(ax, lv(ok), p(ok), sz, col, 'filled', 'MarkerEdgeColor', col * 0.6, ...
                'Tag', behavior.Plot.tag_("Proportion"), ...
                'DisplayName', sprintf('Data (%d trials)', sum(nt(ok & isfinite(nt)))));

            if good
                cx = reshape(double(F.Curve.x), [], 1);
                cp = reshape(double(F.Curve.P), [], 1);
                okC = isfinite(cx) & isfinite(cp);
                if any(okC)
                    H.Curve = plot(ax, cx(okC), cp(okC), '-', 'Color', col, 'LineWidth', 2, ...
                        'Tag', behavior.Plot.tag_("Curve"), 'DisplayName', "Fit (" + string(F.Shape) + ")");
                end
                if isscalar(th) && isfinite(th)
                    H.Threshold = plot(ax, [th th], [0 1], '--', 'Color', behavior.Plot.INK, 'LineWidth', 1.5, ...
                        'Tag', behavior.Plot.tag_("Threshold"), ...
                        'DisplayName', "Threshold " + behavior.Plot.withUnit_(sprintf('%.4g', th), options.Unit));
                end
            else
                if msg == ""
                    msg = "The fit did not converge.";
                end
                H.Message = text(ax, 0.02, 0.97, msg, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
                    'Interpreter', 'none', 'Color', behavior.Plot.INK, 'Tag', behavior.Plot.tag_("Message"));
            end

            ylim(ax, [0 1]);
            xlabel(ax, behavior.Plot.withUnit_("Stimulus level", options.Unit), 'Interpreter', 'none');
            ylabel(ax, "Proportion yes", 'Interpreter', 'none');
            H.Legend = behavior.Plot.legend_(ax, [H.CI H.Proportion H.Curve H.Threshold], "");
            hold(ax, 'off');
        end

        function H = reversalHistogram(ax, R, options)
            % H = behavior.Plot.reversalHistogram(ax, R, Name = Value)
            % The values at which the staircase reversed, with their mean and
            % median. Several results are pooled.
            %
            % Parameters:
            %   ax   - axes or uiaxes
            %   R    - behavior.Session.analyze result(s)
            %   Unit - x unit; "" = the result's Unit
            %
            % Returns:
            %   H - struct Axes, NoData, Legend, Histogram, Mean, Median
            arguments
                ax (1,1)
                R
                options.Unit (1,1) string = ""
            end
            H = behavior.Plot.prepare_(ax, ["Histogram" "Mean" "Median"]);
            R = behavior.Plot.asResults_(R);
            if isempty(R)
                H = behavior.Plot.noData_(H);
                return
            end
            v = cell2mat(arrayfun(@(r) reshape(double(r.ReversalValues), 1, []), reshape(R, 1, []), ...
                'UniformOutput', false));
            v = v(isfinite(v));
            if isempty(v)
                H = behavior.Plot.noData_(H, "The staircase has no reversals.");
                return
            end
            unit = behavior.Plot.resultUnit_(R, options.Unit);
            col = behavior.Plot.palette(1);
            H.Histogram = histogram(ax, v, 'FaceColor', col, 'EdgeColor', col * 0.6, 'FaceAlpha', 0.6, ...
                'Tag', behavior.Plot.tag_("Histogram"), 'DisplayName', sprintf('Reversals (n=%d)', numel(v)));
            mu = mean(v);
            md = median(v);
            H.Mean = xline(ax, mu, '--', 'Color', behavior.Plot.INK, 'LineWidth', 1.5, ...
                'Tag', behavior.Plot.tag_("Mean"), ...
                'DisplayName', "Mean " + behavior.Plot.withUnit_(sprintf('%.4g', mu), unit));
            H.Median = xline(ax, md, ':', 'Color', behavior.Plot.hexToRgb_(behavior.Plot.PALETTE_HEX(3)), ...
                'LineWidth', 2, 'Tag', behavior.Plot.tag_("Median"), ...
                'DisplayName', "Median " + behavior.Plot.withUnit_(sprintf('%.4g', md), unit));
            xlabel(ax, behavior.Plot.parameterLabel_(R, options.Unit, " at reversal"), 'Interpreter', 'none');
            ylabel(ax, "Count", 'Interpreter', 'none');
            H.Legend = behavior.Plot.legend_(ax, [H.Histogram H.Mean H.Median], "");
            hold(ax, 'off');
        end
    end

    methods (Static, Access = private)
        function H = timeline_(ax, T, value, colorBy, xAxis, showFit, showQC)
            % Shared body of thresholdTimeline and metricTimeline.
            H = behavior.Plot.prepare_(ax, ["SubjectLine" "Point" "Fit" "QC" "LegendKey"]);
            if ~behavior.Plot.hasRows_(T)
                H = behavior.Plot.noData_(H);
                return
            end
            behavior.Plot.mustHaveColumn_(T, value);
            [x, xl] = behavior.Plot.timeAxis_(T, xAxis);
            okX = ~ismissing(x);
            y = reshape(double(T.(value)), [], 1);
            ok = okX & isfinite(y);
            fy = nan(height(T), 1);
            if showFit && ismember("FitThreshold", string(T.Properties.VariableNames))
                fy = reshape(double(T.FitThreshold), [], 1);
            end
            okF = okX & isfinite(fy);
            if ~any(ok) && ~any(okF)
                H = behavior.Plot.noData_(H, value + " has no finite value.");
                return
            end
            [cols, clev, cidx] = behavior.Plot.colorsFor(colorBy, T);
            subj = string(T.Subject);

            % A line per subject, behind its markers.
            for s = reshape(behavior.Aggregate.naturalUnique(subj(ok)), 1, [])
                rows = find(subj == s & ok);
                if numel(rows) < 2, continue, end
                [~, k] = sort(x(rows));
                rows = rows(k);
                c = unique(cidx(rows));
                col = behavior.Plot.NEUTRAL;
                if isscalar(c), col = cols(c, :); end
                H.SubjectLine(end+1) = plot(ax, x(rows), y(rows), '-', 'Color', col, 'LineWidth', 1, ...
                    'Tag', behavior.Plot.tag_("SubjectLine"), ...
                    'UserData', struct('Subject', s));
            end

            for c = 1:numel(clev)
                rows = ok & cidx == c;
                if any(rows)
                    H.Point(end+1) = plot(ax, x(rows), y(rows), 'LineStyle', 'none', 'Marker', 'o', ...
                        'MarkerSize', 7, 'MarkerFaceColor', cols(c, :), 'MarkerEdgeColor', cols(c, :) * 0.6, ...
                        'Tag', behavior.Plot.tag_("Point"), ...
                        'DisplayName', sprintf('%s (n=%d)', clev(c), sum(rows)));
                end
                rowsF = okF & cidx == c;
                if any(rowsF)
                    H.Fit(end+1) = plot(ax, x(rowsF), fy(rowsF), 'LineStyle', 'none', 'Marker', 'd', ...
                        'MarkerSize', 8, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', cols(c, :), ...
                        'LineWidth', 1.2, 'Tag', behavior.Plot.tag_("Fit"));
                end
            end

            if showQC && ismember("NumQC", string(T.Properties.VariableNames))
                rowsQ = ok & reshape(double(T.NumQC), [], 1) > 0;
                if any(rowsQ)
                    H.QC = plot(ax, x(rowsQ), y(rowsQ), 'LineStyle', 'none', 'Marker', 'o', 'MarkerSize', 13, ...
                        'MarkerEdgeColor', behavior.Plot.INK, 'LineWidth', 1.5, ...
                        'Tag', behavior.Plot.tag_("QC"), 'DisplayName', sprintf('QC flag (n=%d)', sum(rowsQ)));
                end
            end
            if ~isempty(H.Fit)
                % One legend entry for every level's hollow diamonds.
                xp = x(1);
                xp(1) = missing;
                key = plot(ax, xp, NaN, 'LineStyle', 'none', 'Marker', 'd', 'MarkerSize', 8, ...
                    'MarkerFaceColor', 'none', 'MarkerEdgeColor', behavior.Plot.INK, 'LineWidth', 1.2, ...
                    'Tag', behavior.Plot.tag_("LegendKey"), 'DisplayName', ...
                    sprintf('Fitted threshold (n=%d)', sum(okF)));
                H.LegendKey(end+1) = key;
            end

            xlabel(ax, xl, 'Interpreter', 'none');
            ylabel(ax, behavior.Plot.valueLabel_(T, value), 'Interpreter', 'none');
            H.Legend = behavior.Plot.legend_(ax, [H.Point H.QC H.LegendKey], colorBy.label());
            hold(ax, 'off');
        end

        function [x, label] = timeAxis_(T, xAxis)
            % The timeline's x column and what the axis says it is.
            switch xAxis
                case "date"
                    behavior.Plot.mustHaveColumn_(T, "Start");
                    x = reshape(T.Start, [], 1);
                    label = "Session date";
                case "session"
                    behavior.Plot.mustHaveColumn_(T, "SessionOrdinal");
                    x = reshape(double(T.SessionOrdinal), [], 1);
                    label = "Session number (per subject)";
                case "days"
                    behavior.Plot.mustHaveColumn_(T, "DaysSinceFirst");
                    x = reshape(double(T.DaysSinceFirst), [], 1);
                    label = "Days since the subject's first session";
            end
        end

        function [h, key] = subjectMedians_(ax, T, value, G, levels, cols, cidx)
            % Each subject's median per level, offset so subjects do not overlap.
            h = gobjects(0);
            key = gobjects(0);
            S = behavior.Aggregate.bySubject(T, value, GroupBy = G);
            S = S(isfinite(S.Median), :);
            if height(S) == 0, return, end
            h = gobjects(1, height(S));
            n = 0;
            subj = string(T.Subject);
            lvl = G.values(T);
            for k = 1:numel(levels)
                rows = find(S.Level == levels(k));
                ns = numel(rows);
                for j = 1:ns
                    s = S.Subject(rows(j));
                    c = unique(cidx(subj == s & lvl == levels(k)));
                    col = behavior.Plot.NEUTRAL;
                    if isscalar(c), col = cols(c, :); end
                    off = 0;
                    if ns > 1
                        off = ((j - 1) / (ns - 1) - 0.5) * 0.3;
                    end
                    n = n + 1;
                    h(n) = plot(ax, k + off, S.Median(rows(j)), 'LineStyle', 'none', 'Marker', 'd', ...
                        'MarkerSize', 11, 'MarkerFaceColor', col, 'MarkerEdgeColor', behavior.Plot.INK, ...
                        'LineWidth', 1.2, 'Tag', behavior.Plot.tag_("SubjectMedian"), ...
                        'UserData', struct('Subject', s, 'Level', levels(k)));
                end
            end
            h = h(1:n);
            key = plot(ax, NaN, NaN, 'LineStyle', 'none', 'Marker', 'd', 'MarkerSize', 11, ...
                'MarkerFaceColor', 'w', 'MarkerEdgeColor', behavior.Plot.INK, 'LineWidth', 1.2, ...
                'Tag', behavior.Plot.tag_("LegendKey"), ...
                'DisplayName', sprintf('Subject median (n=%d)', numel(unique(S.Subject))));
        end

        function [center, lo, hi, name] = spreadOf_(D, spread, level)
            % Each behavior.Stats.describe row's spread as a centre and its
            % two ends, and what a legend calls it. SEM, SD and the CI lie
            % about the mean; the IQR and the range about the median, which
            % they always contain (the mean need not lie inside either).
            % "none" gives NaN.
            n = height(D);
            center = D.Mean;
            lo = nan(n, 1);
            hi = nan(n, 1);
            name = "";
            switch spread
                case "sem"
                    lo = D.Mean - D.SEM; hi = D.Mean + D.SEM;
                    name = string(char(177)) + " SEM";
                case "sd"
                    lo = D.Mean - D.SD; hi = D.Mean + D.SD;
                    name = string(char(177)) + " SD";
                case "ci"
                    lo = D.CILo; hi = D.CIHi;
                    name = sprintf("%g%% bootstrap CI of the mean", 100 * level);
                case "iqr"
                    center = D.Median; lo = D.Q1; hi = D.Q3;
                    name = "Interquartile range";
                case "range"
                    center = D.Median; lo = D.Min; hi = D.Max;
                    name = "Range (min to max)";
            end
        end

        function [h, tagName] = spreadBars_(ax, x, center, lo, hi, spread, name, lineWidth, capSize, caller)
            % Each level's spread as a capped bar from lo to hi with no
            % marker of its own -- the mean is the caller's to draw, or not.
            % Tagged CI for the bootstrap CI and ErrorBar for every other
            % spread, UserData.Spread saying which. A level whose spread is
            % not finite (one value, or too few for a bootstrap) has none.
            tagName = "ErrorBar";
            if spread == "ci"
                tagName = "CI";
            end
            h = gobjects(0);
            x = reshape(x, [], 1);
            center = reshape(center, [], 1);
            lo = reshape(lo, [], 1);
            hi = reshape(hi, [], 1);
            ok = isfinite(center) & isfinite(lo) & isfinite(hi);
            if ~any(ok)
                if spread == "ci"
                    vprintf(2, 'behavior.Plot.%s: no level has the %d values a bootstrap CI needs', ...
                        caller, behavior.Stats.MIN_BOOT)
                end
                return
            end
            h = errorbar(ax, x(ok), center(ok), max(center(ok) - lo(ok), 0), max(hi(ok) - center(ok), 0), ...
                'LineStyle', 'none', 'Marker', 'none', 'Color', behavior.Plot.INK, 'LineWidth', lineWidth, ...
                'CapSize', capSize, 'Tag', behavior.Plot.tag_(tagName), 'DisplayName', name, ...
                'UserData', struct('Spread', spread));
        end

        function H = prepare_(ax, fields)
            % Check the axes, clear it (keeping its Tag and UserData) and
            % start the handle struct with every field the figure fills.
            if ~(isscalar(ax) && isgraphics(ax) && strcmp(ax.Type, 'axes'))
                error('behavior:Plot:InvalidAxes', ...
                    'behavior.Plot draws into an axes or uiaxes you supply; it never creates a figure.');
            end
            tag = ax.Tag;
            ud = ax.UserData;
            menu = ax.ContextMenu;
            colorbar(ax, 'off');             % a sibling of the axes: cla leaves it
            cla(ax, 'reset');
            ax.Tag = tag;
            ax.UserData = ud;
            ax.ContextMenu = menu;
            box(ax, 'on');
            hold(ax, 'on');
            H = struct('Axes', ax, 'NoData', gobjects(0), 'Legend', gobjects(0));
            for f = fields
                H.(f) = gobjects(0);
            end
        end

        function H = noData_(H, detail)
            % The centred "No data" text, with a reason beneath it when given.
            arguments
                H struct
                detail (1,1) string = ""
            end
            ax = H.Axes;
            txt = "No data";
            if strtrim(detail) ~= ""
                txt = [txt; detail];
            end
            H.NoData = text(ax, 0.5, 0.5, txt, 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', 'Interpreter', 'none', 'Color', behavior.Plot.INK, ...
                'Tag', behavior.Plot.tag_("NoData"));
            ax.XTick = [];
            ax.YTick = [];
            hold(ax, 'off');
        end

        function [X, V, REV, TI] = tracks_(R, normalize)
            % Each result's staircase as the track figures draw it: x per
            % Normalize ("none" trial number, "trial" 1..n, "fraction" k/n),
            % the value, the reversal flags and the trial index -- finite
            % trial/value pairs only. One cell per result, empty for none.
            n = numel(R);
            [X, V, REV, TI] = deal(cell(n, 1));
            for k = 1:n
                tr = R(k).Track;
                ti = reshape(double(tr.TrialIndex), 1, []);
                v = reshape(double(tr.Value), 1, []);
                rev = reshape(logical(tr.Reversal), 1, []);
                keep = isfinite(ti) & isfinite(v);
                ti = ti(keep); v = v(keep); rev = rev(keep);
                nk = numel(v);
                switch normalize
                    case "none",     x = ti;
                    case "trial",    x = 1:nk;
                    case "fraction", x = (1:nk) / nk;
                end
                X{k} = x; V{k} = v; REV{k} = rev; TI{k} = ti;
            end
        end

        function row = heatmapRow_(ti, v, normalize, nc)
            % One session's heatmap row of nc cells, NaN where it has no data.
            row = nan(1, nc);
            n = numel(v);
            if n == 0, return, end
            switch normalize
                case "none"
                    % The level is held from one stimulus trial to the next,
                    % as the overlay's steps hold it.
                    [ti, o] = sort(round(ti));
                    v = v(o);
                    ok = ti >= 1 & ti <= nc;
                    ti = ti(ok); v = v(ok);
                    if isempty(v), return, end
                    held = zeros(1, nc);
                    held(ti) = 1:numel(v);
                    held = cummax(held);
                    span = ti(1):ti(end);
                    row(span) = v(held(span));
                case "trial"
                    row(1:n) = v;
                case "fraction"
                    % Stimulus trial k covers ((k-1)/n, k/n]; a slice takes
                    % the trial its centre falls in.
                    row = v(min(n, max(1, ceil(((1:nc) - 0.5) / nc * n))));
            end
        end

        function h = hatch_(ax, missing, xc, dx)
            % Diagonal strokes over every run of missing cells, as one line
            % object. Strokes lie on lines shared by the whole grid, so the
            % hatch runs unbroken across neighbouring rows and columns, at
            % 45 degrees and HATCH_SPACING pixels apart for the axes' size
            % when drawn (a resize afterwards only changes their angle).
            [m, nc] = size(missing);
            px = behavior.Plot.axesPixels_(ax);
            kx = px(1) / (nc * dx);              % pixels per x unit
            ky = px(2) / m;                      % pixels per row
            s = kx / ky;                         % data slope of a 45-degree stroke
            d = behavior.Plot.HATCH_SPACING / kx;
            % Every run of missing cells, row by row: find on the transpose
            % lists starts and ends in the same (row-major) order.
            e = diff([false(m, 1) missing false(m, 1)], 1, 2).';
            [first, row] = find(e == 1);
            last = find(e == -1) - (row - 1) * (nc + 1) - 1;
            [XS, YS] = deal(cell(1, numel(row)));
            for j = 1:numel(row)
                x0 = xc(first(j)) - dx / 2;
                x1 = xc(last(j)) + dx / 2;
                y0 = row(j) - 0.5;
                y1 = row(j) + 0.5;
                % Stroke b runs along x = b + y/s.
                b = (ceil((x0 - y1 / s) / d):floor((x1 - y0 / s) / d)).' * d;
                ya = max(y0, s * (x0 - b));
                yb = min(y1, s * (x1 - b));
                ok = yb > ya;
                b = b(ok); ya = ya(ok); yb = yb(ok);
                XS{j} = reshape([b + ya / s, b + yb / s, nan(numel(b), 1)].', 1, []);
                YS{j} = reshape([ya, yb, nan(numel(b), 1)].', 1, []);
            end
            x = [XS{:}];
            y = [YS{:}];
            h = plot(ax, x, y, '-', 'Color', behavior.Plot.HATCH_COLOR, 'LineWidth', 0.75, ...
                'PickableParts', 'none', 'Tag', behavior.Plot.tag_("Missing"));
        end

        function px = axesPixels_(ax)
            % The plot box's size in pixels, or a typical one when the axes
            % has not been laid out (a tab that was never in front).
            px = [600 350];
            try
                u = ax.Units;
                ax.Units = 'pixels';
                p = ax.InnerPosition;
                ax.Units = u;
                if p(3) >= 40 && p(4) >= 40
                    px = p(3:4);
                end
            catch ME
                vprintf(3, 'behavior.Plot: axes size unknown (%s)', ME.message);
            end
        end

        function [ticks, labels] = rowTicks_(levels, nPer)
            % A label per row ("3", or "Pre (n=4)" for a row of several
            % sessions) and the rows to label: all of them, or every k-th
            % past MAX_ROW_LABELS.
            labels = reshape(string(levels), [], 1);
            many = reshape(nPer, [], 1) > 1;
            labels(many) = compose("%s (n=%d)", labels(many), reshape(nPer(many), [], 1));
            m = numel(labels);
            step = max(1, ceil(m / behavior.Plot.MAX_ROW_LABELS));
            ticks = (1:step:m).';
        end

        function txt = trackAxisLabel_(normalize)
            % The x label of a track figure for its Normalize.
            switch normalize
                case "none",     txt = "Trial";
                case "trial",    txt = "Included stimulus trial";
                case "fraction", txt = "Fraction of the session's included stimulus trials";
            end
        end

        function ref = referenceValue_(R, reference)
            % A stack's reference level: a stated value, or the median of
            % the finite thresholds ("median"), or NaN ("none", or none finite).
            ref = NaN;
            if isnumeric(reference)
                ref = double(reference);
                return
            end
            if lower(string(reference)) ~= "median"
                return
            end
            th = nan(numel(R), 1);
            for k = 1:numel(R)
                t = double(R(k).Threshold);
                if isscalar(t), th(k) = t; end
            end
            th = th(isfinite(th));
            if ~isempty(th)
                ref = median(th);
            end
        end

        function L = niceLength_(span)
            % A round scale-bar length -- 1, 2 or 5 times a power of ten --
            % no longer than half the span.
            half = span / 2;
            e = 10 ^ floor(log10(half));
            L = e;
            for f = [5 2]
                if f * e <= half
                    L = f * e;
                    return
                end
            end
        end

        function txt = valueText_(v, unit)
            % "24.1 dB": a value with its unit, when there is one.
            txt = string(sprintf('%.4g', v));
            if strtrim(unit) ~= ""
                txt = txt + " " + unit;
            end
        end

        function lg = legend_(ax, h, titleText, location)
            % A legend over the given handles, or none when there are none.
            arguments
                ax
                h
                titleText (1,1) string
                location = 'best'
            end
            lg = gobjects(0);
            h = h(isgraphics(h));
            if isempty(h)
                legend(ax, 'off');
                return
            end
            lg = legend(ax, h, 'Interpreter', 'none', 'Location', location, 'Tag', behavior.Plot.tag_("Legend"));
            lg.AutoUpdate = 'off';
            if strlength(titleText) > 0
                lg.Title.String = titleText;
                lg.Title.Interpreter = 'none';
            end
        end

        function key = markerKey_(ax, marker, sz, face, name)
            % A legend-only marker (NaN data draws nothing) in INK outline.
            key = plot(ax, NaN, NaN, 'LineStyle', 'none', 'Marker', marker, 'MarkerSize', sz, ...
                'MarkerFaceColor', face, 'MarkerEdgeColor', behavior.Plot.INK, 'LineWidth', 1, ...
                'Tag', behavior.Plot.tag_("LegendKey"), 'DisplayName', name);
        end

        function cb = levelColorBar_(ax, cols, levels, titleText)
            % A colour bar with one band per level, ticked at the levels'
            % centres -- every level when they fit, else about ten spread
            % evenly with the first and last always labelled.
            n = size(cols, 1);
            colormap(ax, cols);
            ax.CLim = [0.5, n + 0.5];
            at = 1:n;
            if n > 12
                at = unique(round(linspace(1, n, 10)));
            end
            [labels, prefix] = behavior.Plot.compactLabels_(levels);
            if prefix ~= ""
                titleText = titleText + " (" + prefix + char(8230) + ")";
            end
            cb = colorbar(ax, 'Ticks', at, 'TickLabels', cellstr(labels(at)), ...
                'TickLabelInterpreter', 'none', 'TickDirection', 'out', 'Tag', behavior.Plot.tag_("ColorBar"));
            cb.Label.String = titleText;
            cb.Label.Interpreter = 'none';
        end

        function [labels, prefix] = compactLabels_(levels)
            % Colour-bar tick labels kept short, because a uiaxes in a grid
            % layout reserves room for a narrow label only and a wide one
            % runs into the neighbouring control. A prefix every level
            % shares up to a separator ("2026-09-" of a run of dates, "2026-"
            % of weeks) is lifted into the title; what remains is cut to
            % MAX_TICK_CHARS.
            levels = reshape(string(levels), [], 1);
            prefix = "";
            if numel(levels) > 1
                c = char(levels(1));
                n = numel(c);
                for k = 2:numel(levels)
                    o = char(levels(k));
                    m = min(n, numel(o));
                    d = find(c(1:m) ~= o(1:m), 1);
                    if isempty(d), n = m; else, n = d - 1; end
                end
                cut = find(ismember(c(1:n), '-_ /:'), 1, 'last');
                % Only when every level keeps something after the cut.
                if ~isempty(cut) && all(strlength(levels) > cut)
                    prefix = string(c(1:cut));
                end
            end
            labels = extractAfter(levels, strlength(prefix));
            long = strlength(labels) > behavior.Plot.MAX_TICK_CHARS;
            labels(long) = extractBefore(labels(long), behavior.Plot.MAX_TICK_CHARS) + char(8230);
        end

        function h = firstPerName_(h)
            % The first of the handles sharing each DisplayName -- one legend
            % entry per colour level however many lines it has -- in the
            % levels' order (UserData.Level), not the order they were drawn.
            if isempty(h), return, end
            [~, first] = unique(string(get(h, 'DisplayName')), 'stable');
            h = h(sort(first));
            [~, k] = sort(arrayfun(@(x) x.UserData.Level, h));
            h = h(k);
        end

        function tf = hasRows_(T)
            tf = istable(T) && height(T) > 0 && width(T) > 0;
        end

        function mustHaveColumn_(T, name)
            if ~ismember(name, string(T.Properties.VariableNames))
                error('behavior:Plot:UnknownColumn', ...
                    'The table has no column "%s"; see behavior.Aggregate.valueColumns.', name);
            end
        end

        function txt = valueLabel_(T, value)
            % "Reversal threshold (dB)": the valueColumns label, with the
            % table's unit for a value measured in the parameter's units. A
            % psignifit width is in log units for a logn or weibull fit
            % (FitShape) and in the parameter's units otherwise.
            V = behavior.Aggregate.valueColumns();
            k = find(V.Name == value, 1);
            if isempty(k)
                txt = value;
                return
            end
            txt = V.Label(k);
            vars = string(T.Properties.VariableNames);
            kind = V.Kind(k);
            if kind == "width" && ismember("FitShape", vars)
                shapes = unique(string(T.FitShape(isfinite(double(T.(value))))));
                isLog = ismember(shapes, ["logn" "weibull"]);
                if ~isempty(shapes) && all(isLog)
                    txt = txt + " (log units)";
                    return
                elseif any(isLog)
                    txt = txt + " (mixed: log and parameter units)";
                    return
                end
            end
            if ismember(kind, ["parameter" "width"]) && ismember("Unit", vars)
                u = unique(string(T.Unit));
                u = u(~ismissing(u) & strtrim(u) ~= "");
                if isscalar(u)
                    txt = behavior.Plot.withUnit_(txt, u);
                elseif numel(u) > 1
                    txt = txt + " (mixed units: " + strjoin(u, ", ") + ")";
                end
            elseif V.Kind(k) == "rate"
                txt = txt + " (proportion)";
            end
        end

        function txt = parameterLabel_(R, unitOverride, suffix)
            % "Depth at reversal (dB)": the tracked parameter's name and unit.
            p = unique(arrayfun(@(r) string(r.Parameter), R));
            p = p(p ~= "");
            if isscalar(p)
                name = p;
            else
                name = "Tracked value";
            end
            txt = behavior.Plot.withUnit_(name + suffix, behavior.Plot.resultUnit_(R, unitOverride));
        end

        function u = resultUnit_(R, unitOverride)
            % The stated unit, else the one unit the results agree on, else "".
            u = unitOverride;
            if u ~= "", return, end
            units = unique(arrayfun(@(r) string(r.Unit), R));
            units = units(~ismissing(units) & strtrim(units) ~= "");
            if isscalar(units)
                u = units;
            end
        end

        function txt = withUnit_(txt, unit)
            txt = string(txt);
            if strtrim(unit) ~= ""
                txt = txt + " (" + unit + ")";
            end
        end

        function R = asResults_(results)
            % Results as one struct column, whatever shape they came in.
            if iscell(results)
                results = results(~cellfun(@isempty, results));
                if isempty(results)
                    R = struct([]);
                else
                    R = [results{:}];
                end
            elseif isstruct(results)
                R = results;
            elseif isempty(results)
                R = struct([]);
            else
                error('behavior:Plot:InvalidResults', ...
                    'results must be a struct array or a cell array of behavior.Session.analyze results.');
            end
            R = reshape(R, [], 1);
        end

        function j = jitter_(group, ok, width)
            % Deterministic horizontal spread within each group: a
            % golden-ratio sequence, so the picture is the same every time and
            % the global random stream is never touched.
            j = zeros(size(group));
            for g = reshape(unique(group(ok)), 1, [])
                rows = find(ok & group == g);
                n = numel(rows);
                if n < 2, continue, end
                j(rows) = (mod((1:n) * 0.6180339887, 1) - 0.5) * width;
            end
        end

        function c = lighten_(c, amount)
            c = c + (1 - c) * amount;
        end

        function rgb = hexToRgb_(hex)
            hex = char(erase(reshape(string(hex), [], 1), "#"));
            rgb = [hex2dec(hex(:, 1:2)) hex2dec(hex(:, 3:4)) hex2dec(hex(:, 5:6))] / 255;
        end

        function t = tag_(role)
            t = char(behavior.Plot.TAG_PREFIX + role);
        end
    end
end


% ---------------------------------------------------------------------------
function localMustBeReference(v)
% A stack's Reference: "median", "none", or one finite number.
ok = (isnumeric(v) && isscalar(v) && isfinite(v)) ...
    || ((isstring(v) || ischar(v)) && ismember(lower(string(v)), ["median" "none"]));
if ~ok
    error('behavior:Plot:InvalidReference', ...
        'Reference must be "median", "none" or one finite value in the parameter''s units.');
end
end
