classdef SubjectView < gui.behavior.View
    % gui.behavior.SubjectView  One subject over time: learning curves and every staircase.
    %
    % The Subject tab of epsych.BehaviorAnalysis. The subject follows the
    % browser's selection (a subject node, or a session's subject). Shown:
    % the reversal threshold per session against time with the fitted
    % threshold beside it (behavior.Plot.thresholdTimeline), any other value
    % against time (metricTimeline, value chosen above it), every one of
    % the subject's staircases overlaid (staircaseOverlay), and a table of
    % the sessions. The sessions are the subject's CHECKED ones; when none
    % of its sessions is checked, all of its visible sessions, so selecting
    % a subject always shows something.
    %
    %   V = gui.behavior.SubjectView(container, study);
    %   V.setSubject("SUBJ-ID-1234");
    %   V.OnOpenSession = @(key) ...;      % double-click a row
    %
    % Only redrawn while its tab is in front (setActive); a change while it
    % is behind marks it stale, and it redraws when brought forward.
    %
    % See also: gui.behavior.View, behavior.Plot, epsych.BehaviorAnalysis

    properties
        OnOpenSession = []
    end

    properties (SetAccess = private)
        Subject (1,1) string = ""
        Keys (1,:) string = strings(1, 0)     % the table's rows, in DATA order
        Value (1,1) string = "DPrime"         % metric timeline's value
        Table = table()                       % behavior.Aggregate.thresholds shown
        Active (1,1) logical = true
    end

    properties (Access = private)
        Stale_ (1,1) logical = false
    end

    properties (Constant, Access = private)
        MUTED (1,3) double = [0.35 0.38 0.42]
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
            obj.H.overlay = uiaxes(g);
            obj.H.overlay.Layout.Row = 3;
            obj.H.overlay.Layout.Column = 1;
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
            obj.draw_(@() behavior.Plot.staircaseOverlay(obj.H.overlay, R, T, ColorBy = color), obj.H.overlay);
            title(obj.H.overlay, 'Every staircase', 'Interpreter', 'none');
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
            end
            obj.H.table.Data = table();
            obj.Keys = strings(1, 0);
            obj.Table = table();
            obj.H.title.Text = 'Select a subject or one of its sessions in the browser';
        end
    end
end
