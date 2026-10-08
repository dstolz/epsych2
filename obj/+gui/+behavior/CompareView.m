classdef CompareView < gui.behavior.View
    % gui.behavior.CompareView  The checked sessions compared across groups.
    %
    % The Compare tab of epsych.BehaviorAnalysis. One value (a
    % behavior.Aggregate.valueColumns column) of every checked, visible
    % session, grouped by a facet and drawn one of five ways:
    %   box, bar, strip - behavior.Plot.groupComparison along Group by,
    %                     points coloured by Color by
    %   lines           - behavior.Plot.subjectLines: one line per subject
    %                     through its per-level medians along X axis
    %   overlay         - behavior.Plot.staircaseOverlay: every checked
    %                     session's staircase, coloured by Color by through
    %                     Colors (behavior.Plot.COLOR_MAPS: distinct colours,
    %                     or a gradient across an ordered facet such as
    %                     Session # or Date; Auto picks between them)
    % The value is chosen in up to three menus, the valueColumns address of
    % a column: the measure, then for "Staircase threshold" which estimate
    % (the last-N reversal threshold, or the min/median/mean/max over the
    % sliding blocks) and which correction (as analysed, unweighted, or
    % weighted), and for "Psychometric fit" which parameter (threshold,
    % location, slope, width, lapse, guess, overdispersion, deviance).
    % Mean and Spread choose the summary lines drawn over the groups
    % (behavior.Plot.SPREADS; Auto is what the tab always drew).
    % Beside it, the descriptive statistics of the value per Group by level
    % (behavior.Stats.describe: n, mean, SD, SEM, median, IQR, and the
    % bootstrap CI when Bootstrap CI is ticked or the spread is the CI), and
    % their sentence on the status line. Descriptive only, by decision: no
    % tests, no p-values.
    %
    % The view's choices are the project's (behavior.Study.setFacets), so a
    % preset and a generated script carry them; Bootstrap CI is the
    % Settings' Compare.BootstrapCI, which changes no result.
    %
    % See also: gui.behavior.View, behavior.Plot, behavior.Stats, behavior.Facet

    properties (SetAccess = private)
        Table = table()        % behavior.Aggregate.thresholds of the checked sessions
        Results = []           % their behavior.Session.analyze results
        Stats = table()        % behavior.Stats.describe shown
        Plotted = struct()     % the handle struct the last behavior.Plot call returned
        Active (1,1) logical = true
    end

    properties (Access = private)
        Stale_ (1,1) logical = false
        Updating_ (1,1) logical = false
    end

    properties (Constant, Access = private)
        MUTED (1,3) double = [0.35 0.38 0.42]
        KIND_LABELS = ["Box" "Bar (mean)" "Strip" "Subject lines" "Staircase overlay"]
        MISSING = "<missing>"      % the measure menu's entry for a saved value this version lacks
    end

    methods
        function obj = CompareView(parent, study)
            obj@gui.behavior.View(parent, study);
        end

        function build(obj)
            g = uigridlayout(obj.Parent, [3 1]);
            g.RowHeight = {26, 26, '1x'};
            g.Padding = [4 4 4 4];
            g.RowSpacing = 6;
            obj.H.root = g;

            % Row 1: what is compared, and by what.
            c = uigridlayout(g, [1 10]);
            c.ColumnWidth = {'fit', 130, 'fit', 160, 150, 110, 'fit', 140, 'fit', 140};
            c.Padding = [0 0 0 0];
            c.ColumnSpacing = 6;
            uilabel(c, 'Text', 'Plot');
            obj.H.kind = uidropdown(c, 'Items', cellstr(obj.KIND_LABELS), ...
                'ItemsData', cellstr(behavior.Project.ViewKinds), ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("Kind", src.Value));
            uilabel(c, 'Text', 'Value');
            obj.H.measure = uidropdown(c, 'Items', {''}, ...
                'Tooltip', 'What is compared', ...
                'ValueChangedFcn', @(src, ~) obj.onValuePart_("Measure", string(src.Value)));
            obj.H.statistic = uidropdown(c, 'Items', {''}, ...
                'Tooltip', ['Staircase threshold: the last-N reversal threshold, or the min, median, mean ' ...
                'or max of the thresholds of every sliding block of N reversals. Psychometric fit: ' ...
                'the fitted parameter (width and overdispersion are psignifit''s only)'], ...
                'ValueChangedFcn', @(src, ~) obj.onValuePart_("Statistic", string(src.Value)));
            obj.H.correction = uidropdown(c, 'Items', {''}, ...
                'Tooltip', ['As analysed follows Settings > Staircase > Apply weighted correction; ' ...
                'Unweighted and Weighted (Hoover 2025) are each computed whatever that setting'], ...
                'ValueChangedFcn', @(src, ~) obj.onValuePart_("Correction", string(src.Value)));
            uilabel(c, 'Text', 'Group by');
            obj.H.groupBy = uidropdown(c, 'Items', {'All sessions'}, 'ItemsData', {'none'}, ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("GroupBy", src.Value));
            uilabel(c, 'Text', 'Color by');
            obj.H.colorBy = uidropdown(c, 'Items', {'Subject'}, 'ItemsData', {'subject'}, ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("ColorBy", src.Value));

            % Row 2: how it is drawn.
            d = uigridlayout(g, [1 8]);
            d.ColumnWidth = {'fit', 140, 'fit', 140, 'fit', 'fit', 110, 'fit'};
            d.Padding = [0 0 0 0];
            d.ColumnSpacing = 6;
            uilabel(d, 'Text', 'Colors');
            maps = behavior.Plot.COLOR_MAPS;
            obj.H.colorMap = uidropdown(d, 'Items', cellstr(arrayfun(@behavior.Plot.colorMapLabel, maps)), ...
                'ItemsData', cellstr(maps), 'Value', 'auto', ...
                'Tooltip', ['How the Staircase overlay colours Color by: distinct colours, or a gradient ' ...
                'from the first level to the last (Auto: a gradient for Session #, Date, Week, Month, Year)'], ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("ColorMap", src.Value));
            uilabel(d, 'Text', 'X axis');
            obj.H.xAxis = uidropdown(d, 'Items', {'Date'}, 'ItemsData', {'date'}, ...
                'Tooltip', 'The levels along x for Subject lines', ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("XAxis", src.Value));
            obj.H.mean = uicheckbox(d, 'Text', 'Mean', 'Value', true, ...
                'Tooltip', ['Each group''s mean: the bar of a bar chart, the line of a strip, a square ' ...
                'beside a box, the heavy line of Subject lines'], ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("ShowMean", string(src.Value)));
            uilabel(d, 'Text', 'Spread');
            spreads = behavior.Plot.SPREADS;
            obj.H.spread = uidropdown(d, 'Items', cellstr(arrayfun(@behavior.Plot.spreadLabel, spreads)), ...
                'ItemsData', cellstr(spreads), 'Value', 'auto', ...
                'Tooltip', ['The dispersion drawn for each group: SEM, SD or the bootstrap CI about the ' ...
                'mean, the IQR or the range about the median, or none. Auto: the SEM (the CI when ' ...
                'Bootstrap CI is ticked), and nothing beside a box unless Bootstrap CI is ticked'], ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("Spread", src.Value));
            obj.H.boot = uicheckbox(d, 'Text', 'Bootstrap CI', ...
                'Tooltip', 'A percentile bootstrap CI on each group''s mean in the table (Settings > Compare); Auto spread draws it', ...
                'ValueChangedFcn', @(src, ~) obj.onBootstrap_(src.Value));

            b = uigridlayout(g, [1 2]);
            b.ColumnWidth = {'1x', 380};
            b.Padding = [0 0 0 0];
            b.ColumnSpacing = 8;
            obj.H.axes = uiaxes(b);
            r = uigridlayout(b, [2 1]);
            r.RowHeight = {'1x', 'fit'};
            r.Padding = [0 0 0 0];
            obj.H.stats = uitable(r, 'RowName', {}, 'RowStriping', 'on', ...
                'ColumnName', {'Level', 'n', 'Mean', 'SD', 'SEM', 'Median', 'Q1', 'Q3', 'CI lo', 'CI hi'});
            obj.H.sentence = uilabel(r, 'Text', '', 'WordWrap', 'on', 'FontColor', obj.MUTED);
        end

        function setActive(obj, tf)
            obj.Active = tf;
            if tf && obj.Stale_
                obj.refresh("show");
            end
        end

        function refresh(obj, reason)
            arguments
                obj
                reason (1,1) string = "show"
            end
            if ~isvalid(obj) || ~isgraphics(obj.H.root) || reason == "ResultsChanged"
                return
            end
            if ~obj.Active
                obj.Stale_ = true;
                return
            end
            obj.Stale_ = false;
            obj.fillControls_();

            keys = obj.Study.Selection;
            if ~isempty(keys)
                keys = keys(~obj.Study.isHidden(keys));
            end
            if isempty(keys)
                obj.Table = table();
                obj.Results = [];
                obj.Stats = table();
                cla(obj.H.axes);
                legend(obj.H.axes, 'off');
                title(obj.H.axes, 'Check sessions in the browser to compare them', 'Interpreter', 'none');
                obj.forgetPlot_("compare");
                obj.H.stats.Data = cell(0, 10);
                obj.H.sentence.Text = '';
                return
            end
            try
                [T, R] = obj.Study.results(keys);
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus("Compare: " + string(ME.message));
                return
            end
            obj.Table = T;
            obj.Results = R;
            obj.draw_();
        end
    end

    methods (Access = private)
        function fillControls_(obj)
            obj.Updating_ = true;
            cleanup = onCleanup(@() obj.doneUpdating_());
            P = obj.Study.Project;
            F = behavior.Facet.available(obj.Study.sessions(IncludeHidden = true), ...
                reshape(string([P.Groupings.Name]), 1, []));
            labels = arrayfun(@(f) f.label(), F);
            texts = arrayfun(@(f) f.toText(), F);
            fac = P.Facets;
            pairs = {obj.H.groupBy, "GroupBy"; obj.H.colorBy, "ColorBy"; obj.H.xAxis, "XAxis"};
            for k = 1:size(pairs, 1)
                dd = pairs{k, 1};
                cur = string(fac.(pairs{k, 2}));
                missing = double(~ismember(cur, texts));    % a saved facet this root no longer offers
                L = [labels, repmat(behavior.Facet.fromText(cur).label() + " (missing)", 1, missing)];
                X = [texts, repmat(cur, 1, missing)];
                dd.Items = cellstr(L);
                dd.ItemsData = cellstr(X);
                dd.Value = char(cur);
            end
            obj.fillValue_(string(fac.Value));
            obj.H.kind.Value = char(fac.Kind);
            obj.H.colorMap.Value = char(obj.colorMap_());
            obj.H.mean.Value = obj.showMean_();
            obj.H.spread.Value = char(obj.spread_());
            obj.H.boot.Value = obj.Study.Settings.Compare.BootstrapCI;
            isLines = string(fac.Kind) == "lines";
            isOverlay = string(fac.Kind) == "overlay";
            obj.H.xAxis.Enable = matlab.lang.OnOffSwitchState(isLines);
            obj.H.groupBy.Enable = matlab.lang.OnOffSwitchState(~isLines);
            obj.H.colorMap.Enable = matlab.lang.OnOffSwitchState(isOverlay);
            obj.H.mean.Enable = matlab.lang.OnOffSwitchState(~isOverlay);
            obj.H.spread.Enable = matlab.lang.OnOffSwitchState(~isOverlay);
            delete(cleanup);
        end

        function fillValue_(obj, value)
            % The three value menus at the column's valueColumns address:
            % the measure, then its statistics and corrections (a menu with
            % one form shows a dash, greyed). A saved value this version
            % does not offer is kept on the measure menu, marked missing.
            V = behavior.Aggregate.valueColumns();
            measures = unique(V.Measure, 'stable');
            k = find(V.Name == value, 1);
            if isempty(k)
                obj.H.measure.Items = cellstr([measures; value + " (missing)"]);
                obj.H.measure.ItemsData = cellstr([measures; obj.MISSING]);
                obj.H.measure.Value = char(obj.MISSING);
                obj.setPart_(obj.H.statistic, "", strings(0, 1));
                obj.setPart_(obj.H.correction, "", strings(0, 1));
                return
            end
            obj.H.measure.Items = cellstr(measures);
            obj.H.measure.ItemsData = cellstr(measures);
            obj.H.measure.Value = char(V.Measure(k));
            inMeasure = V.Measure == V.Measure(k);
            obj.setPart_(obj.H.statistic, V.Statistic(k), unique(V.Statistic(inMeasure), 'stable'));
            obj.setPart_(obj.H.correction, V.Correction(k), ...
                unique(V.Correction(inMeasure & V.Statistic == V.Statistic(k)), 'stable'));
        end

        function setPart_(~, dd, value, options)
            % One value menu: its options, or a greyed dash when there is
            % no choice to make.
            options = options(options ~= "");
            if isempty(options)
                dd.Items = {char(8212)};
                dd.ItemsData = {''};
                dd.Value = '';
                dd.Enable = 'off';
                return
            end
            dd.Items = cellstr(options);
            dd.ItemsData = cellstr(options);
            dd.Value = char(value);
            dd.Enable = 'on';
        end

        function tf = showMean_(obj)
            % The project's ShowMean; a hand-edited file holding something
            % else is read as true rather than breaking the plot.
            tf = obj.Study.Project.Facets.ShowMean;
            if ~(islogical(tf) && isscalar(tf))
                tf = true;
            end
        end

        function s = spread_(obj)
            % The project's Spread, "auto" for one this version lacks.
            s = lower(string(obj.Study.Project.Facets.Spread));
            if ~ismember(s, behavior.Plot.SPREADS)
                s = "auto";
            end
        end

        function m = colorMap_(obj)
            % The project's overlay colour map; a hand-edited file naming
            % none is read as "auto" rather than breaking the overlay.
            m = lower(string(obj.Study.Project.Facets.ColorMap));
            if ~ismember(m, behavior.Plot.COLOR_MAPS)
                m = "auto";
            end
        end

        function doneUpdating_(obj)
            if isvalid(obj)
                obj.Updating_ = false;
            end
        end

        function draw_(obj)
            P = obj.Study.Project;
            fac = P.Facets;
            T = obj.Table;
            value = string(fac.Value);
            G = behavior.Facet.fromText(fac.GroupBy);
            C = behavior.Facet.fromText(fac.ColorBy);
            X = behavior.Facet.fromText(fac.XAxis);
            cmp = obj.Study.Settings.Compare;
            % The summary lines, and the statistics behind them.
            summary = {'ShowMean', obj.showMean_(), 'Spread', obj.spread_(), 'ShowCI', cmp.BootstrapCI, ...
                'ConfidenceLevel', cmp.ConfidenceLevel, 'NumBoot', cmp.NumBoot};
            ax = obj.H.axes;
            D = [];
            % Drawn through plotInto_ so "Open in New Figure" can draw it
            % again; the handles hold the data, not the view.
            kind = string(fac.Kind);
            R = obj.Results;
            map = obj.colorMap_();
            V = behavior.Aggregate.valueColumns();
            label = V.Label(V.Name == value);
            if isempty(label), label = value; end
            n = sprintf(" (%d sessions)", height(T));
            switch kind
                case {"box" "bar" "strip"}
                    fcn = @(a) behavior.Plot.groupComparison(a, T, value, 'GroupBy', G, 'ColorBy', C, ...
                        'Kind', kind, summary{:});
                    name = "Compare · " + label(1) + " by " + G.label() + n;
                case "lines"
                    fcn = @(a) behavior.Plot.subjectLines(a, T, value, 'XAxis', X, 'ColorBy', C, summary{:});
                    name = "Compare · " + label(1) + ", a line per subject along " + X.label() + n;
                case "overlay"
                    fcn = @(a) behavior.Plot.staircaseOverlay(a, R, T, ColorBy = C, ColorMap = map);
                    name = "Compare · Staircases coloured by " + C.label() + n;
            end
            [Hp, ok] = obj.plotInto_("compare", ax, fcn, name);
            if ~ok
                Hp = struct();
            elseif isfield(Hp, 'Stats')
                D = Hp.Stats;
            end
            obj.Plotted = Hp;
            if isempty(D) || ~istable(D)
                try
                    D = behavior.Stats.describe(T, value, GroupBy = G, BootstrapCI = cmp.BootstrapCI, ...
                        ConfidenceLevel = cmp.ConfidenceLevel, NumBoot = cmp.NumBoot);
                catch ME
                    vprintf(2, ME);
                    D = table();
                end
            end
            obj.Stats = D;
            obj.fillStats_(D);
            hint = obj.noValueHint_(T, value);
            if hint ~= ""
                obj.setStatus(hint);
            end
        end

        function s = noValueHint_(obj, T, value)
            % Why no session has the value, when the settings say why: the
            % plot itself can only say that it has none.
            s = "";
            if ~ismember(value, string(T.Properties.VariableNames)) || height(T) == 0 ...
                    || any(isfinite(double(T.(value))))
                return
            end
            st = obj.Study.Settings;
            V = behavior.Aggregate.valueColumns();
            k = find(V.Name == value, 1);
            if isempty(k), return, end
            if V.Measure(k) == behavior.Aggregate.FIT_MEASURE
                if ~st.Fit.Enabled
                    s = "No session has a fit: fitting is off (Settings > Fit).";
                elseif ismember(value, ["FitWidth" "FitEta"]) && st.Fit.Engine ~= "psignifit"
                    s = "Width and overdispersion are psignifit's: choose it as the fit engine (Settings > Fit).";
                end
            elseif V.Correction(k) == "Weighted" && isstruct(obj.Results) && isfield(obj.Results, 'Estimates')
                why = arrayfun(@(r) string(r.Estimates.Weighted.Message), obj.Results(:));
                why = why(why ~= "");
                if ~isempty(why)
                    s = "No session has a weighted threshold: " + why(1);
                end
            end
        end

        function fillStats_(obj, D)
            if ~istable(D) || height(D) == 0
                obj.H.stats.Data = cell(0, 10);
                obj.H.sentence.Text = '';
                return
            end
            f = @(x) round(x, 4, 'significant');
            obj.H.stats.Data = table(string(D.Level), D.N, f(D.Mean), f(D.SD), f(D.SEM), f(D.Median), ...
                f(D.Q1), f(D.Q3), f(D.CILo), f(D.CIHi), 'VariableNames', ...
                {'Level', 'n', 'Mean', 'SD', 'SEM', 'Median', 'Q1', 'Q3', 'CILo', 'CIHi'});
            obj.H.stats.ColumnName = {'Level', 'n', 'Mean', 'SD', 'SEM', 'Median', 'Q1', 'Q3', 'CI lo', 'CI hi'};
            s = behavior.Stats.sentence(D);
            obj.H.sentence.Text = char(s);
            obj.setStatus(s);
        end

        function onFacet_(obj, role, value)
            if obj.Updating_, return, end
            try
                args = {char(role), string(value)};
                obj.Study.setFacets(args{:});    % ProjectChanged -> refresh
            catch ME
                obj.setStatus(string(ME.message));
                obj.fillControls_();
            end
        end

        function onValuePart_(obj, part, choice)
            % One of the three value menus changed: the column at the new
            % address (behavior.Aggregate.valueAt keeps the other two menus'
            % choices where the measure has them) becomes the Value.
            if obj.Updating_, return, end
            address = struct('Measure', string(obj.H.measure.Value), ...
                'Statistic', string(obj.H.statistic.Value), 'Correction', string(obj.H.correction.Value));
            address.(part) = choice;
            if address.Measure == obj.MISSING, return, end
            name = behavior.Aggregate.valueAt(address.Measure, address.Statistic, address.Correction);
            if name ~= ""
                obj.onFacet_("Value", name);
            end
        end

        function onBootstrap_(obj, tf)
            if obj.Updating_, return, end
            s = obj.Study.Settings;
            s.Compare.BootstrapCI = tf;
            obj.Study.setSettings(s);
        end
    end
end
