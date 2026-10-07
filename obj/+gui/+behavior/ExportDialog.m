classdef ExportDialog < handle
    % gui.behavior.ExportDialog  Which tables, in which formats, into which folder.
    %
    % Opened from epsych.BehaviorAnalysis (File > Export Tables..., Ctrl+E,
    % the export tool, the Table tab's Export...). The tables are
    % behavior.Export's (sessions, subjects, thresholds, fits, metrics,
    % reversals, notes), always with the column dictionary beside them; the
    % formats CSV (one file per table), XLSX (one workbook) and MAT (one
    % struct). Export calls the window's exportTables over the checked
    % sessions. The folder and the formats are remembered (ExportFolder,
    % ExportFormats in the window's preferences) when Export is pressed.
    %
    %   D = gui.behavior.ExportDialog(app);
    %
    % See also: epsych.BehaviorAnalysis.exportTables, behavior.Export

    properties (SetAccess = private)
        App
        H (1,1) struct = struct()
        Files (:,1) string = strings(0, 1)     % what the last Export wrote
    end

    properties (Constant)
        FIGURE_TAG = 'EPsychBehaviorExport'
        FORMATS = ["csv" "xlsx" "mat"]
    end

    methods
        function obj = ExportDialog(app, options)
            arguments
                app (1,1) epsych.BehaviorAnalysis
                options.Visible (1,1) logical = true
            end
            figs = findall(groot, 'Type', 'figure', 'Tag', obj.FIGURE_TAG);
            for k = 1:numel(figs)
                if isobject(figs(k).UserData) && isvalid(figs(k).UserData), delete(figs(k).UserData); end
            end
            obj.App = app;
            obj.build_(options.Visible);
        end

        function delete(obj)
            if isfield(obj.H, 'figure') && isgraphics(obj.H.figure)
                obj.H.figure.CloseRequestFcn = '';
                delete(obj.H.figure);
            end
        end

        function files = export(obj)
            % files = export(obj)
            % Export with what the dialog says, and remember folder and formats.
            files = strings(0, 1);
            tables = behavior.Export.TABLES(arrayfun(@(c) c.Value, obj.H.tables));
            formats = obj.FORMATS(arrayfun(@(c) c.Value, obj.H.formats));
            folder = strtrim(string(obj.H.folder.Value));
            if isempty(tables) || isempty(formats) || folder == ""
                obj.H.status.Text = 'Choose at least one table, one format, and a folder.';
                return
            end
            G = epsych.BehaviorAnalysis.PREF_TAG;
            setpref(G, 'ExportFolder', char(folder));
            setpref(G, 'ExportFormats', formats);
            try
                files = obj.App.exportTables(folder, Formats = formats, Tables = tables, ...
                    Prefix = string(obj.H.prefix.Value));
                obj.Files = files;
                obj.H.status.Text = char(sprintf("Wrote %d file(s) to %s", numel(files), folder));
            catch ME
                vprintf(0, 1, ME);
                obj.H.status.Text = char("Export failed: " + string(ME.message));
            end
        end
    end

    methods (Access = private)
        function build_(obj, visible)
            G = epsych.BehaviorAnalysis.PREF_TAG;
            folder = string(pwd);
            if ispref(G, 'ExportFolder'), folder = string(getpref(G, 'ExportFolder')); end
            formats = "csv";
            if ispref(G, 'ExportFormats'), formats = string(getpref(G, 'ExportFormats')); end

            f = uifigure('Name', 'Export Tables', 'Tag', obj.FIGURE_TAG, 'Position', [260 200 560 400], ...
                'Visible', matlab.lang.OnOffSwitchState(visible));
            f.UserData = obj;
            f.CloseRequestFcn = @(~,~) delete(obj);
            obj.H.figure = f;
            g = uigridlayout(f, [5 2]);
            g.RowHeight = {'1x', 26, 26, 'fit', 30};
            g.ColumnWidth = {'1x', '1x'};

            t = uipanel(g, 'Title', 'Tables');
            t.Layout.Row = 1;
            tg = uigridlayout(t, [numel(behavior.Export.TABLES) 1]);
            tg.RowHeight = repmat({20}, 1, numel(behavior.Export.TABLES));
            on = ["sessions" "subjects" "thresholds" "fits" "metrics"];
            for k = 1:numel(behavior.Export.TABLES)
                name = behavior.Export.TABLES(k);
                obj.H.tables(k) = uicheckbox(tg, 'Text', char(name), 'Value', ismember(name, on));
            end
            p = uipanel(g, 'Title', 'Formats');
            p.Layout.Row = 1;
            p.Layout.Column = 2;
            pg = uigridlayout(p, [3 1]);
            pg.RowHeight = {20, 20, 20};
            labels = ["CSV (one file per table)" "Excel workbook (.xlsx)" "MAT-file (struct EPsychExport)"];
            for k = 1:numel(obj.FORMATS)
                obj.H.formats(k) = uicheckbox(pg, 'Text', char(labels(k)), 'Value', ismember(obj.FORMATS(k), formats));
            end

            fg = uigridlayout(g, [1 3]);
            fg.Layout.Row = 2;
            fg.Layout.Column = [1 2];
            fg.ColumnWidth = {'fit', '1x', 'fit'};
            fg.Padding = [0 0 0 0];
            uilabel(fg, 'Text', 'Folder');
            obj.H.folder = uieditfield(fg, 'text', 'Value', char(folder));
            uibutton(fg, 'Text', 'Browse...', 'ButtonPushedFcn', @(~,~) obj.browse_());

            xg = uigridlayout(g, [1 2]);
            xg.Layout.Row = 3;
            xg.Layout.Column = [1 2];
            xg.ColumnWidth = {'fit', 160};
            xg.Padding = [0 0 0 0];
            uilabel(xg, 'Text', 'File-name prefix');
            obj.H.prefix = uieditfield(xg, 'text', 'Value', 'epsych_');

            obj.H.status = uilabel(g, 'Text', ...
                'The checked sessions are exported (every visible one when none is checked).', ...
                'WordWrap', 'on', 'FontColor', [0.35 0.38 0.42]);
            obj.H.status.Layout.Row = 4;
            obj.H.status.Layout.Column = [1 2];

            b = uigridlayout(g, [1 3]);
            b.Layout.Row = 5;
            b.Layout.Column = [1 2];
            b.ColumnWidth = {'1x', 100, 100};
            b.Padding = [0 0 0 0];
            uilabel(b, 'Text', '');
            uibutton(b, 'Text', 'Export', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) obj.export());
            uibutton(b, 'Text', 'Close', 'ButtonPushedFcn', @(~,~) delete(obj));
        end

        function browse_(obj)
            d = uigetdir(obj.H.folder.Value, 'Export the tables into');
            figure(obj.H.figure);
            if ~isequal(d, 0)
                obj.H.folder.Value = d;
            end
        end
    end
end
