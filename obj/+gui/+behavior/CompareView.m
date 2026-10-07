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
    %                     session's staircase, coloured by Color by
    % Beside it, the descriptive statistics of the value per Group by level
    % (behavior.Stats.describe: n, mean, SD, SEM, median, IQR, and the
    % bootstrap CI when Bootstrap CI is ticked), and their sentence on the
    % status line. Descriptive only, by decision: no tests, no p-values.
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
    end

    methods
        function obj = CompareView(parent, study)
            obj@gui.behavior.View(parent, study);
        end

        function build(obj)
            g = uigridlayout(obj.Parent, [2 1]);
            g.RowHeight = {26, '1x'};
            g.Padding = [4 4 4 4];
            g.RowSpacing = 6;
            obj.H.root = g;

            c = uigridlayout(g, [1 11]);
            c.ColumnWidth = {'fit', 140, 'fit', 140, 'fit', 140, 'fit', 160, 'fit', 130, 'fit'};
            c.Padding = [0 0 0 0];
            c.ColumnSpacing = 6;
            uilabel(c, 'Text', 'Group by');
            obj.H.groupBy = uidropdown(c, 'Items', {'All sessions'}, 'ItemsData', {'none'}, ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("GroupBy", src.Value));
            uilabel(c, 'Text', 'Color by');
            obj.H.colorBy = uidropdown(c, 'Items', {'Subject'}, 'ItemsData', {'subject'}, ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("ColorBy", src.Value));
            uilabel(c, 'Text', 'X axis');
            obj.H.xAxis = uidropdown(c, 'Items', {'Date'}, 'ItemsData', {'date'}, ...
                'Tooltip', 'The levels along x for Subject lines', ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("XAxis", src.Value));
            uilabel(c, 'Text', 'Value');
            V = behavior.Aggregate.valueColumns();
            obj.H.value = uidropdown(c, 'Items', cellstr(V.Label), 'ItemsData', cellstr(V.Name), ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("Value", src.Value));
            uilabel(c, 'Text', 'Plot');
            obj.H.kind = uidropdown(c, 'Items', cellstr(obj.KIND_LABELS), ...
                'ItemsData', cellstr(behavior.Project.ViewKinds), ...
                'ValueChangedFcn', @(src, ~) obj.onFacet_("Kind", src.Value));
            obj.H.boot = uicheckbox(c, 'Text', 'Bootstrap CI', ...
                'Tooltip', 'A percentile bootstrap CI on each group''s mean (Settings > Compare)', ...
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
            V = behavior.Aggregate.valueColumns();
            names = V.Name;
            vlabels = V.Label;
            if ~ismember(string(fac.Value), names)
                names(end+1) = string(fac.Value);
                vlabels(end+1) = string(fac.Value);
            end
            obj.H.value.Items = cellstr(vlabels);
            obj.H.value.ItemsData = cellstr(names);
            obj.H.value.Value = char(fac.Value);
            obj.H.kind.Value = char(fac.Kind);
            obj.H.boot.Value = obj.Study.Settings.Compare.BootstrapCI;
            isLines = string(fac.Kind) == "lines";
            obj.H.xAxis.Enable = matlab.lang.OnOffSwitchState(isLines);
            obj.H.groupBy.Enable = matlab.lang.OnOffSwitchState(~isLines);
            delete(cleanup);
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
            ax = obj.H.axes;
            D = [];
            try
                switch string(fac.Kind)
                    case {"box" "bar" "strip"}
                        Hp = behavior.Plot.groupComparison(ax, T, value, GroupBy = G, ColorBy = C, ...
                            Kind = string(fac.Kind), ShowCI = cmp.BootstrapCI, ConfidenceLevel = cmp.ConfidenceLevel);
                        D = Hp.Stats;
                    case "lines"
                        Hp = behavior.Plot.subjectLines(ax, T, value, XAxis = X, ColorBy = C);
                        D = Hp.Stats;
                    case "overlay"
                        Hp = behavior.Plot.staircaseOverlay(ax, obj.Results, T, ColorBy = C);
                end
            catch ME
                vprintf(0, 1, ME);
                cla(ax);
                text(ax, 0.5, 0.5, string(ME.message), 'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'Color', obj.MUTED, 'Interpreter', 'none');
                Hp = struct();
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

        function onBootstrap_(obj, tf)
            if obj.Updating_, return, end
            s = obj.Study.Settings;
            s.Compare.BootstrapCI = tf;
            obj.Study.setSettings(s);
        end
    end
end
