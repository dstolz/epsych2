classdef SubjectView < gui.behavior.View
    % gui.behavior.SubjectView  One subject over time: learning curves and every staircase.
    %
    % The Subject tab of epsych.BehaviorAnalysis. The subject follows the
    % browser's selection (a subject node, or a session's subject). Shown:
    % the reversal threshold per session against time with the fitted
    % threshold beside it (behavior.Plot.thresholdTimeline), any other value
    % against time (metricTimeline, value chosen above it), every one of
    % the subject's staircases overlaid (staircaseOverlay), and a table of
    % the sessions.
    %
    % The overlay has controls of its own -- Color by (any facet, default
    % Session #), Colors (behavior.Plot.COLOR_MAPS; Auto is a gradient
    % across an ordered facet, so the subject's sessions run from first to
    % last along the map) and X (trial, stimulus trial, or fraction of the
    % session) -- and a right-click menu for reversals, thresholds and step
    % drawing. They are display choices, not analysis: kept in Overlay,
    % changed with setOverlay, and reported through OnOverlayChanged when
    % the operator changes one, so the window can remember them.
    %
    % The sessions are the subject's CHECKED ones; when none
    % of its sessions is checked, all of its visible sessions, so selecting
    % a subject always shows something.
    %
    %   V = gui.behavior.SubjectView(container, study);
    %   V.setSubject("SUBJ-ID-1234");
    %   V.OnOpenSession = @(key) ...;      % double-click a row
    %   V.setOverlay(ColorBy = "date", ColorMap = "turbo", Normalize = "fraction");
    %
    % Only redrawn while its tab is in front (setActive); a change while it
    % is behind marks it stale, and it redraws when brought forward.
    %
    % See also: gui.behavior.View, behavior.Plot, epsych.BehaviorAnalysis

    properties
        OnOpenSession = []
        OnOverlayChanged = []     % @(overlay) after the operator changes an overlay control
    end

    properties (SetAccess = private)
        Subject (1,1) string = ""
        Keys (1,:) string = strings(1, 0)     % the table's rows, in DATA order
        Value (1,1) string = "DPrime"         % metric timeline's value
        Table = table()                       % behavior.Aggregate.thresholds shown
        Active (1,1) logical = true
        % The overlay's display choices: ColorBy (facet text), ColorMap
        % (behavior.Plot.COLOR_MAPS), Normalize ("none"|"trial"|"fraction"),
        % ShowReversals, ShowThresholds, Steps.
        Overlay (1,1) struct = struct('ColorBy', "session", 'ColorMap', "auto", 'Normalize', "none", ...
            'ShowReversals', false, 'ShowThresholds', true, 'Steps', true)
    end

    properties (Access = private)
        Stale_ (1,1) logical = false
        Results_ = []             % the shown sessions' analyze results, for an overlay redraw
    end

    properties (Constant, Access = private)
        MUTED (1,3) double = [0.35 0.38 0.42]
        NORMALIZE = ["none" "trial" "fraction"]
        NORMALIZE_LABELS = ["Trial in session" "Stimulus trial" "Fraction of session"]
    end

    methods
        function obj = SubjectView(parent, study)
            obj@gui.behavior.View(parent, study);
        end

        function build(obj)
            g = uigridlayout(obj.Parent, [3 2]);
            g.RowHeight = {24, '1x', '1x'};
            g.ColumnWidth = {'1x', '1x'};
            g.Padding = [4 4 4 4];
            g.RowSpacing = 6;
            g.ColumnSpacing = 8;
            obj.H.root = g;

            obj.H.title = uilabel(g, 'Text', 'Select a subject or one of its sessions in the browser', ...
                'FontWeight', 'bold', 'FontSize', 13);
            obj.H.title.Layout.Column = 1;
            v = uigridlayout(g, [1 2]);
            v.ColumnWidth = {'fit', '1x'};
            v.Padding = [0 0 0 0];
            uilabel(v, 'Text', 'Learning curve of');
            V = behavior.Aggregate.valueColumns();
            obj.H.value = uidropdown(v, 'Items', cellstr(V.Label), 'ItemsData', cellstr(V.Name), ...
                'Value', char(obj.Value), 'ValueChangedFcn', @(src, ~) obj.setValue(string(src.Value)));

            obj.H.timeline = uiaxes(g);
            obj.H.timeline.Layout.Row = 2;
            obj.H.timeline.Layout.Column = 1;
            obj.H.metric = uiaxes(g);
            obj.H.metric.Layout.Row = 2;
            obj.H.metric.Layout.Column = 2;
            o = uigridlayout(g, [2 1]);
            o.RowHeight = {22, '1x'};
            o.Padding = [0 0 0 0];
            o.RowSpacing = 2;
            o.Layout.Row = 3;
            o.Layout.Column = 1;
            oc = uigridlayout(o, [1 6]);
            oc.ColumnWidth = {'fit', 120, 130, 'fit', 120, '1x'};
            oc.Padding = [0 0 0 0];
            oc.ColumnSpacing = 4;
            uilabel(oc, 'Text', 'Color by');
            obj.H.ovColorBy = uidropdown(oc, 'Items', {'Session #'}, 'ItemsData', {'session'}, ...
                'Tooltip', 'What the staircases are coloured by', ...
                'ValueChangedFcn', @(src, ~) obj.onOverlay_("ColorBy", string(src.Value)));
            maps = behavior.Plot.COLOR_MAPS;
            obj.H.ovColorMap = uidropdown(oc, 'Items', cellstr(arrayfun(@behavior.Plot.colorMapLabel, maps)), ...
                'ItemsData', cellstr(maps), 'Value', 'auto', ...
                'Tooltip', ['Distinct colours, or a gradient from the first level to the last ' ...
                '(Auto: a gradient for Session #, Date, Week, Month, Year)'], ...
                'ValueChangedFcn', @(src, ~) obj.onOverlay_("ColorMap", string(src.Value)));
            uilabel(oc, 'Text', 'X');
            obj.H.ovNormalize = uidropdown(oc, 'Items', cellstr(obj.NORMALIZE_LABELS), ...
                'ItemsData', cellstr(obj.NORMALIZE), 'Value', 'none', ...
                'Tooltip', 'Align the staircases on trial number, stimulus trial, or fraction of the session', ...
                'ValueChangedFcn', @(src, ~) obj.onOverlay_("Normalize", string(src.Value)));
            uilabel(oc, 'Text', 'Right-click: more', 'FontColor', obj.MUTED, ...
                'HorizontalAlignment', 'right', 'FontAngle', 'italic');

            obj.H.overlay = uiaxes(o);
            cm = uicontextmenu(ancestor(obj.Parent, 'figure'));
            obj.H.ovShowReversals = uimenu(cm, 'Text', 'Show Reversals', ...
                'MenuSelectedFcn', @(~, ~) obj.onOverlay_("ShowReversals", ~obj.Overlay.ShowReversals));
            obj.H.ovShowThresholds = uimenu(cm, 'Text', 'Show Session Thresholds', ...
                'MenuSelectedFcn', @(~, ~) obj.onOverlay_("ShowThresholds", ~obj.Overlay.ShowThresholds));
            obj.H.ovSteps = uimenu(cm, 'Text', 'Draw as Steps', ...
                'MenuSelectedFcn', @(~, ~) obj.onOverlay_("Steps", ~obj.Overlay.Steps));
            obj.H.overlay.ContextMenu = cm;
            obj.syncOverlayControls_();
            obj.H.table = uitable(g, 'ColumnName', {'Date', 'Tags', 'Window', 'Trials', 'Threshold', ...
                'Fit', 'd''', 'QC'}, 'RowName', {}, 'RowStriping', 'on', 'ColumnSortable', true, ...
                'SelectionType', 'row', 'Multiselect', 'off', ...
                'Tooltip', 'Double-click a session to open it on the Session tab', ...
                'DoubleClickedFcn', @(~, evt) obj.onDoubleClick_(evt));
            obj.H.table.Layout.Row = 3;
            obj.H.table.Layout.Column = 2;
        end

        function setActive(obj, tf)
            % setActive(obj, tf)
            % In front (redraws on change) or behind (marks itself stale).
            obj.Active = tf;
            if tf && obj.Stale_
                obj.refresh("show");
            end
        end

        function setSubject(obj, name)
            % setSubject(obj, name)
            % Show one subject ("" clears).
            arguments
                obj
                name (1,1) string
            end
            if name == obj.Subject && ~obj.Stale_
                return
            end
            obj.Subject = name;
            obj.refresh("show");
        end

        function setValue(obj, name)
            % setValue(obj, name)
            % The value the learning curve shows (a behavior.Aggregate.valueColumns name).
            arguments
                obj
                name (1,1) string
            end
            obj.Value = name;
            obj.H.value.Value = char(name);
            obj.refresh("show");
        end

        function setOverlay(obj, options)
            % setOverlay(obj, ColorBy=, ColorMap=, Normalize=, ShowReversals=, ShowThresholds=, Steps=)
            % The overlay's display choices. Only the options given change;
            % a ColorBy that names no facet, or a ColorMap or Normalize that
            % is not one of the choices, is refused before anything changes.
            arguments
                obj
                options.ColorBy (1,1) string
                options.ColorMap (1,1) string
                options.Normalize (1,1) string
                options.ShowReversals (1,1) logical
                options.ShowThresholds (1,1) logical
                options.Steps (1,1) logical
            end
            O = obj.Overlay;
            for f = reshape(string(fieldnames(options)), 1, [])
                v = options.(f);
                switch f
                    case "ColorBy"
                        fac = behavior.Facet.fromText(v);
                        if fac.Kind == "none" && lower(strtrim(v)) ~= "none"
                            error('gui:behavior:SubjectView:InvalidOverlay', '"%s" names no facet.', v);
                        end
                        v = fac.toText();
                    case "ColorMap"
                        v = lower(v);
                        behavior.Plot.mustBeColorMap(v);
                    case "Normalize"
                        if ~ismember(v, obj.NORMALIZE)
                            error('gui:behavior:SubjectView:InvalidOverlay', ...
                                '"%s" is not an overlay x axis (%s).', v, strjoin(obj.NORMALIZE, ", "));
                        end
                end
                O.(f) = v;
            end
            if isequal(O, obj.Overlay), return, end
            obj.Overlay = O;
            obj.syncOverlayControls_();
            obj.drawOverlay_();
        end

        function key = keyForRow(obj, row)
            % key = keyForRow(obj, row)
            % The session of a table row, in DATA order (what uitable reports
            % whatever the operator sorted by).
            key = obj.Keys(row);
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
            if obj.Subject == ""
                obj.clear_();
                return
            end
            [keys, scope] = obj.keys_();
            if isempty(keys)
                obj.clear_();
                obj.H.title.Text = char(obj.Subject + ": no visible sessions");
                return
            end
            try
                [T, R] = obj.Study.results(keys);
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus("Subject " + obj.Subject + ": " + string(ME.message));
                return
            end
            obj.Table = T;
            obj.Keys = reshape(string(T.Key), 1, []);
            obj.H.title.Text = char(sprintf("%s: %d %s session(s)", obj.Subject, height(T), scope));

            color = behavior.Facet("subject");
            if any(T.NumTags > 0)
                color = behavior.Facet("tag", Index = 1);
            end
            obj.draw_(@() behavior.Plot.thresholdTimeline(obj.H.timeline, T, ColorBy = color), obj.H.timeline);
            obj.draw_(@() behavior.Plot.metricTimeline(obj.H.metric, T, obj.Value, ColorBy = color), obj.H.metric);
            obj.Results_ = R;
            obj.syncOverlayControls_();
            obj.drawOverlay_();
            obj.fillTable_(T);
        end
    end

    methods (Access = private)
        function [keys, scope] = keys_(obj)
            % The subject's checked visible sessions, else all its visible ones.
            T = obj.Study.sessions();
            mine = reshape(string(T.Key(string(T.Subject) == obj.Subject)), 1, []);
            norm = @(k) epsych.BehaviorAnalysis.normKey(k);
            keys = mine(ismember(norm(mine), norm(obj.Study.Selection)));
            scope = "checked";
            if isempty(keys)
                keys = mine;
                scope = "visible (none checked)";
            end
        end

        function drawOverlay_(obj)
            % The overlay alone, from the results already in hand: changing
            % how it looks never asks the Study for anything.
            if isempty(obj.Results_) || obj.Subject == ""
                return
            end
            if ~obj.Active
                obj.Stale_ = true;
                return
            end
            O = obj.Overlay;
            R = obj.Results_;
            T = obj.Table;
            obj.draw_(@() behavior.Plot.staircaseOverlay(obj.H.overlay, R, T, ...
                ColorBy = behavior.Facet.fromText(O.ColorBy), ColorMap = O.ColorMap, ...
                Normalize = O.Normalize, ShowReversals = O.ShowReversals, ...
                ShowThresholds = O.ShowThresholds, Steps = O.Steps), obj.H.overlay);
            title(obj.H.overlay, sprintf('Every staircase (n=%d)', height(T)), 'Interpreter', 'none');
        end

        function syncOverlayControls_(obj)
            % The overlay controls showing Overlay; Color by offers every
            % facet the root has, plus a remembered one it no longer offers.
            O = obj.Overlay;
            P = obj.Study.Project;
            F = behavior.Facet.available(obj.Study.sessions(IncludeHidden = true), ...
                reshape(string([P.Groupings.Name]), 1, []));
            labels = arrayfun(@(f) f.label(), F);
            texts = arrayfun(@(f) f.toText(), F);
            if ~ismember(O.ColorBy, texts)
                labels(end+1) = behavior.Facet.fromText(O.ColorBy).label() + " (missing)";
                texts(end+1) = O.ColorBy;
            end
            obj.H.ovColorBy.Items = cellstr(labels);
            obj.H.ovColorBy.ItemsData = cellstr(texts);
            obj.H.ovColorBy.Value = char(O.ColorBy);
            obj.H.ovColorMap.Value = char(O.ColorMap);
            obj.H.ovNormalize.Value = char(O.Normalize);
            obj.H.ovShowReversals.Checked = matlab.lang.OnOffSwitchState(O.ShowReversals);
            obj.H.ovShowThresholds.Checked = matlab.lang.OnOffSwitchState(O.ShowThresholds);
            obj.H.ovSteps.Checked = matlab.lang.OnOffSwitchState(O.Steps);
        end

        function onOverlay_(obj, field, value)
            % An operator change: apply it, then tell the window.
            try
                args = {char(field), value};
                obj.setOverlay(args{:});
            catch ME
                obj.setStatus(string(ME.message));
                obj.syncOverlayControls_();
                return
            end
            if ~isempty(obj.OnOverlayChanged)
                try
                    obj.OnOverlayChanged(obj.Overlay);
                catch ME
                    vprintf(2, ME);
                end
            end
        end

        function draw_(obj, fcn, ax)
            try
                fcn();
            catch ME
                vprintf(0, 1, ME);
                cla(ax);
                text(ax, 0.5, 0.5, string(ME.message), 'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'Color', obj.MUTED, 'Interpreter', 'none');
            end
        end

        function fillTable_(obj, T)
            n = height(T);
            date = T.Start;
            date.Format = 'yyyy-MM-dd HH:mm';
            win = string(T.Window);
            win(win == "") = "(settings)";
            D = table(date, string(T.TagText), win, T.NumIncluded, round(T.Threshold, 4, 'significant'), ...
                round(T.FitThreshold, 4, 'significant'), round(T.DPrime, 3, 'significant'), string(T.QC), ...
                'VariableNames', {'Date', 'Tags', 'Window', 'Trials', 'Threshold', 'Fit', 'dPrime', 'QC'});
            obj.H.table.Data = D;
            obj.H.table.ColumnName = {'Date', 'Tags', 'Window', 'Trials', 'Threshold', 'Fit', 'd''', 'QC'};
            removeStyle(obj.H.table);
            flagged = find(T.NumQC > 0);
            if ~isempty(flagged) && n > 0
                addStyle(obj.H.table, uistyle('FontColor', [0.72 0.42 0.02]), 'row', flagged);
            end
        end

        function onDoubleClick_(obj, evt)
            row = evt.InteractionInformation.Row;
            if isempty(row) || row < 1 || row > numel(obj.Keys) || isempty(obj.OnOpenSession)
                return
            end
            obj.OnOpenSession(obj.keyForRow(row));
        end

        function clear_(obj)
            for ax = [obj.H.timeline obj.H.metric obj.H.overlay]
                cla(ax);
                title(ax, '');
                legend(ax, 'off');
                colorbar(ax, 'off');
            end
            obj.Results_ = [];
            obj.H.table.Data = table();
            obj.Keys = strings(1, 0);
            obj.Table = table();
            obj.H.title.Text = 'Select a subject or one of its sessions in the browser';
        end
    end
end
