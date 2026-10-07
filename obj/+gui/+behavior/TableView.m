classdef TableView < gui.behavior.View
    % gui.behavior.TableView  The numbers of the checked sessions, one row each.
    %
    % The Table tab of epsych.BehaviorAnalysis: behavior.Study.results of
    % the checked, visible sessions (behavior.Aggregate.thresholds) with a
    % column chooser beside it. Copy puts the shown columns on the clipboard
    % as tab-separated text (behavior.Export.toTSV, formatted as the CSV
    % export is); Export... opens the window's export dialog.
    %
    % Columns sort from their headers. The sort is the display's business
    % only: Keys is in DATA order, and every callback works in the DATA row
    % uitable reports (Selection, InteractionInformation.Row), never the
    % row the operator sees -- keyForRow is that mapping.
    %
    %   V = gui.behavior.TableView(container, study);
    %   V.setColumns(["Subject" "Tag1" "Threshold"]);
    %
    % See also: gui.behavior.View, behavior.Aggregate, behavior.Export

    properties
        OnOpenSession = []     % @(key) double-click
        OnSelect = []          % @(key) a row selected
        OnExport = []          % @() Export...
    end

    properties (SetAccess = private)
        Table = table()                     % behavior.Aggregate.thresholds, DATA order
        Keys (1,:) string = strings(1, 0)   % Table.Key, DATA order
        Columns (1,:) string = strings(1, 0)    % chosen ([] = the defaults)
        Active (1,1) logical = true
    end

    properties (Access = private)
        Stale_ (1,1) logical = false
    end

    properties (Constant)
        IDENTITY = ["Project" "Subject" "Start" "TagText" "Window" "Parameter" "Unit"]
    end

    methods
        function obj = TableView(parent, study)
            obj@gui.behavior.View(parent, study);
        end

        function build(obj)
            g = uigridlayout(obj.Parent, [1 2]);
            g.ColumnWidth = {'1x', 200};
            g.Padding = [4 4 4 4];
            g.ColumnSpacing = 8;
            obj.H.root = g;

            left = uigridlayout(g, [2 1]);
            left.RowHeight = {26, '1x'};
            left.Padding = [0 0 0 0];
            bar = uigridlayout(left, [1 4]);
            bar.ColumnWidth = {'1x', 'fit', 'fit', 'fit'};
            bar.Padding = [0 0 0 0];
            obj.H.count = uilabel(bar, 'Text', '', 'FontColor', [0.35 0.38 0.42]);
            obj.H.btnDefaults = uibutton(bar, 'Text', 'Default Columns', ...
                'ButtonPushedFcn', @(~,~) obj.setColumns(strings(1, 0)));
            obj.H.btnCopy = uibutton(bar, 'Text', 'Copy', ...
                'Tooltip', 'Copy the table as tab-separated text, for a spreadsheet or a notebook', ...
                'ButtonPushedFcn', @(~,~) obj.copy());
            obj.H.btnExport = uibutton(bar, 'Text', 'Export...', ...
                'ButtonPushedFcn', @(~,~) obj.export_());
            obj.H.table = uitable(left, 'RowName', {}, 'RowStriping', 'on', 'ColumnSortable', true, ...
                'SelectionType', 'row', 'Multiselect', 'off', ...
                'Tooltip', 'Click a header to sort. Double-click a row to open that session.', ...
                'SelectionChangedFcn', @(src, ~) obj.onSelection_(src.Selection), ...
                'DoubleClickedFcn', @(~, evt) obj.onDoubleClick_(evt));

            right = uigridlayout(g, [2 1]);
            right.RowHeight = {'fit', '1x'};
            right.Padding = [0 0 0 0];
            uilabel(right, 'Text', 'Columns', 'FontWeight', 'bold');
            obj.H.columns = uilistbox(right, 'Multiselect', 'on', 'Items', {}, ...
                'Tooltip', 'Ctrl+click to choose the columns shown, copied and sorted', ...
                'ValueChangedFcn', @(src, ~) obj.setColumns(string(src.Value)));
        end

        function setActive(obj, tf)
            obj.Active = tf;
            if tf && obj.Stale_
                obj.refresh("show");
            end
        end

        function setColumns(obj, names)
            % setColumns(obj, names)
            % The columns shown, in order (empty = the defaults).
            arguments
                obj
                names (1,:) string
            end
            obj.Columns = names;
            obj.show_();
        end

        function key = keyForRow(obj, row)
            % key = keyForRow(obj, row)
            % The session of a DATA row.
            key = obj.Keys(row);
        end

        function D = shownTable(obj)
            % D = shownTable(obj)
            % The table as shown: the chosen columns, in DATA order.
            D = obj.H.table.Data;
            if ~istable(D), D = table(); end
        end

        function ok = copy(obj)
            % ok = copy(obj)
            % The shown columns to the clipboard as tab-separated text.
            ok = behavior.Export.copyTable(obj.shownTable());
            if ok
                obj.setStatus(sprintf("Copied %d row(s) to the clipboard.", height(obj.shownTable())));
            else
                obj.setStatus("The clipboard is not available here.");
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
            keys = obj.Study.Selection;
            if ~isempty(keys)
                keys = keys(~obj.Study.isHidden(keys));
            end
            if isempty(keys)
                obj.Table = table();
                obj.Keys = strings(1, 0);
            else
                try
                    obj.Table = obj.Study.results(keys);
                catch ME
                    vprintf(0, 1, ME);
                    obj.setStatus("Table: " + string(ME.message));
                    return
                end
                obj.Keys = reshape(string(obj.Table.Key), 1, []);
            end
            obj.show_();
        end
    end

    methods (Access = private)
        function show_(obj)
            T = obj.Table;
            avail = obj.displayable_(T);
            cols = obj.Columns(ismember(obj.Columns, avail));
            if isempty(cols)
                V = behavior.Aggregate.valueColumns();
                cols = [obj.IDENTITY reshape(V.Name, 1, []) "QC"];
                cols = cols(ismember(cols, avail));
            end
            obj.H.columns.Items = cellstr(avail);
            obj.H.columns.Value = cellstr(cols);
            if height(T) == 0 || isempty(cols)
                obj.H.table.Data = table();
                obj.H.count.Text = 'No sessions are checked.';
                return
            end
            D = table();
            for c = cols
                D.(c) = obj.column_(T.(c));
            end
            obj.H.table.Data = D;
            obj.H.count.Text = char(sprintf("%d session(s), %d column(s)", height(D), numel(cols)));
        end

        function names = displayable_(~, T)
            % Columns with one scalar per row (text, number, logical, time).
            names = strings(1, 0);
            if width(T) == 0, return, end
            vn = string(T.Properties.VariableNames);
            ok = false(size(vn));
            for k = 1:numel(vn)
                v = T.(vn(k));
                ok(k) = size(v, 2) == 1 && (isnumeric(v) || islogical(v) || isstring(v) ...
                    || isdatetime(v) || isduration(v) || iscategorical(v) || iscellstr(v));
            end
            names = vn(ok & vn ~= "Key");
            names = [names "Key"];
        end

        function v = column_(~, v)
            if iscell(v) || iscategorical(v)
                v = string(v);
            elseif isdatetime(v)
                v.Format = 'yyyy-MM-dd HH:mm';
            elseif isnumeric(v) && ~isinteger(v)
                v = round(double(v), 5, 'significant');
            end
        end

        function onSelection_(obj, sel)
            if isempty(sel) || isempty(obj.OnSelect), return, end
            row = sel(1);
            if row >= 1 && row <= numel(obj.Keys)
                obj.OnSelect(obj.keyForRow(row));
            end
        end

        function onDoubleClick_(obj, evt)
            row = evt.InteractionInformation.Row;
            if isempty(row) || row < 1 || row > numel(obj.Keys) || isempty(obj.OnOpenSession)
                return
            end
            obj.OnOpenSession(obj.keyForRow(row));
        end

        function export_(obj)
            if ~isempty(obj.OnExport)
                obj.OnExport();
            end
        end
    end
end
