classdef GroupingsDialog < handle
    % gui.behavior.GroupingsDialog  Named manual groupings: their levels and who is in each.
    %
    % Opened from epsych.BehaviorAnalysis (Groups > Manage Groupings...,
    % Ctrl+M). A grouping (Treatment: Control, Noise) puts each SUBJECT in a
    % level; a single SESSION can override its subject's level (a pilot
    % session, a day the subject was handled differently). Both become the
    % facet "manual:<Name>" -- Group by, Color by, the exports' group_<Name>
    % column -- and live in the project file.
    %
    % Left: the groupings, with Add / Rename / Remove and the selected
    % one's levels (comma separated; Set Levels). Right: every subject with
    % its level, and below every visible session with its override, each
    % edited in place from a dropdown of the levels. Every edit goes through
    % behavior.Study (assign, addGrouping, removeGrouping) at once; there is
    % no OK to forget.
    %
    %   D = gui.behavior.GroupingsDialog(study);
    %
    % See also: behavior.Project.addGrouping, behavior.Facet

    properties (SetAccess = private)
        Study
        H (1,1) struct = struct()
        Grouping (1,1) string = ""     % the one shown
    end

    properties (Constant)
        FIGURE_TAG = 'EPsychBehaviorGroupings'
        NONE = "(none)"
        INHERIT = "(subject's)"
    end

    properties (Access = private)
        Listener_ = []
        SessionKeys_ (1,:) string = strings(1, 0)     % rows of the sessions table, DATA order
    end

    methods
        function obj = GroupingsDialog(study, options)
            arguments
                study (1,1) behavior.Study
                options.Visible (1,1) logical = true
            end
            figs = findall(groot, 'Type', 'figure', 'Tag', obj.FIGURE_TAG);
            for k = 1:numel(figs)
                if isobject(figs(k).UserData) && isvalid(figs(k).UserData), delete(figs(k).UserData); end
            end
            obj.Study = study;
            obj.build_(options.Visible);
            obj.Listener_ = addlistener(study, 'ProjectChanged', @(~,~) obj.refresh());
            obj.refresh();
        end

        function delete(obj)
            if ~isempty(obj.Listener_) && isvalid(obj.Listener_)
                delete(obj.Listener_);
            end
            if isfield(obj.H, 'figure') && isgraphics(obj.H.figure)
                obj.H.figure.CloseRequestFcn = '';
                delete(obj.H.figure);
            end
        end

        function refresh(obj)
            % refresh(obj)
            % Redraw from the project.
            if ~isvalid(obj) || ~isgraphics(obj.H.figure), return, end
            G = obj.Study.Project.Groupings;
            names = reshape(string([G.Name]), 1, []);
            obj.H.list.Items = cellstr(names);
            if ~ismember(obj.Grouping, names)
                obj.Grouping = "";
                if ~isempty(names), obj.Grouping = names(1); end
            end
            if obj.Grouping ~= ""
                obj.H.list.Value = char(obj.Grouping);
            end
            on = 'off';
            if obj.Grouping ~= "", on = 'on'; end
            set([obj.H.levels obj.H.btnLevels obj.H.btnRename obj.H.btnRemove obj.H.subjects obj.H.sessions], 'Enable', on);
            if obj.Grouping == ""
                obj.H.levels.Value = '';
                obj.H.subjects.Data = cell(0, 2);
                obj.H.sessions.Data = cell(0, 3);
                return
            end
            g = G(names == obj.Grouping);
            obj.H.levels.Value = char(strjoin(g.Levels, ", "));
            P = obj.Study.Project;

            T = obj.Study.sessions(IncludeHidden = true);
            subj = unique(string(T.Subject), 'stable');
            lev = arrayfun(@(s) P.groupingLevel(obj.Grouping, "", s), subj);
            lev(lev == "") = obj.NONE;
            obj.H.subjects.Data = [cellstr(subj(:)) cellstr(lev(:))];
            obj.H.subjects.ColumnFormat = {'char', cellstr([obj.NONE g.Levels])};

            V = obj.Study.sessions();
            keys = reshape(string(V.Key), 1, []);
            own = strings(size(keys));
            for k = 1:numel(keys)
                i = find(epsych.BehaviorAnalysis.normKey([g.Sessions.Key]) == epsych.BehaviorAnalysis.normKey(keys(k)), 1);
                if isempty(i)
                    own(k) = obj.INHERIT;
                else
                    own(k) = g.Sessions(i).Level;
                end
            end
            obj.SessionKeys_ = keys;
            obj.H.sessions.Data = [cellstr(string(V.Subject)) cellstr(string(V.FileName)) cellstr(own(:))];
            obj.H.sessions.ColumnFormat = {'char', 'char', cellstr([obj.INHERIT g.Levels])};
        end
    end

    methods (Access = private)
        function build_(obj, visible)
            f = uifigure('Name', 'Groupings', 'Tag', obj.FIGURE_TAG, 'Position', [220 140 900 600], ...
                'Visible', matlab.lang.OnOffSwitchState(visible));
            f.UserData = obj;
            f.CloseRequestFcn = @(~,~) delete(obj);
            obj.H.figure = f;
            g = uigridlayout(f, [1 2]);
            g.ColumnWidth = {260, '1x'};

            L = uigridlayout(g, [8 1]);
            L.RowHeight = {'fit', '1x', 26, 26, 26, 'fit', 26, 26};
            L.Padding = [0 0 0 0];
            uilabel(L, 'Text', 'Groupings', 'FontWeight', 'bold');
            obj.H.list = uilistbox(L, 'Items', {}, 'ValueChangedFcn', @(src, ~) obj.choose_(string(src.Value)));
            uibutton(L, 'Text', 'Add...', 'ButtonPushedFcn', @(~,~) obj.add_());
            obj.H.btnRename = uibutton(L, 'Text', 'Rename...', 'ButtonPushedFcn', @(~,~) obj.rename_());
            obj.H.btnRemove = uibutton(L, 'Text', 'Remove', 'ButtonPushedFcn', @(~,~) obj.remove_());
            uilabel(L, 'Text', 'Levels (comma separated)');
            obj.H.levels = uieditfield(L, 'text');
            obj.H.btnLevels = uibutton(L, 'Text', 'Set Levels', ...
                'Tooltip', 'Assignments to a level no longer listed are cleared', ...
                'ButtonPushedFcn', @(~,~) obj.setLevels_());

            R = uigridlayout(g, [4 1]);
            R.RowHeight = {'fit', '1x', 'fit', '1x'};
            R.Padding = [0 0 0 0];
            uilabel(R, 'Text', 'Subjects', 'FontWeight', 'bold');
            obj.H.subjects = uitable(R, 'ColumnName', {'Subject', 'Level'}, 'RowName', {}, ...
                'ColumnEditable', [false true], 'ColumnWidth', {'1x', 180}, ...
                'CellEditCallback', @(~, evt) obj.onSubjectEdit_(evt));
            uilabel(R, 'Text', 'Per-session overrides (visible sessions)', 'FontWeight', 'bold');
            obj.H.sessions = uitable(R, 'ColumnName', {'Subject', 'File', 'Level'}, 'RowName', {}, ...
                'ColumnEditable', [false false true], 'ColumnWidth', {140, '1x', 180}, ...
                'CellEditCallback', @(~, evt) obj.onSessionEdit_(evt));
        end

        function choose_(obj, name)
            obj.Grouping = name;
            obj.refresh();
        end

        function add_(obj)
            a = inputdlg({'Name of the grouping (e.g. Treatment):', 'Levels, comma separated (e.g. Control, Noise):'}, ...
                'Add Grouping', [1 50; 1 50]);
            if isempty(a), return, end
            try
                obj.Study.addGrouping(strtrim(string(a{1})), obj.splitLevels_(a{2}));
                obj.Grouping = strtrim(string(a{1}));
                obj.refresh();
            catch ME
                obj.say_(ME.message);
            end
        end

        function rename_(obj)
            old = obj.Grouping;
            a = inputdlg('New name:', 'Rename Grouping', [1 50], {char(old)});
            if isempty(a) || strtrim(string(a{1})) == old, return, end
            new = strtrim(string(a{1}));
            % No rename in the project API: copy it under the new name, then
            % remove the old one, so every assignment survives.
            P = obj.Study.Project;
            G = P.Groupings(string([P.Groupings.Name]) == old);
            try
                P.addGrouping(new, G.Levels);
                for s = G.Subjects
                    P.assign(new, s.Subject, s.Level);
                end
                for s = G.Sessions
                    P.assign(new, s.Key, s.Level);
                end
                obj.Grouping = new;
                obj.Study.removeGrouping(old);    % announces the change
            catch ME
                obj.say_(ME.message);
            end
        end

        function remove_(obj)
            if obj.Grouping == "", return, end
            if strcmp(obj.H.figure.Visible, 'on')
                c = uiconfirm(obj.H.figure, char("Remove the grouping """ + obj.Grouping + """ and every assignment in it?"), ...
                    'Remove Grouping', 'Options', {'Remove', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                if c ~= "Remove", return, end
            end
            obj.Study.removeGrouping(obj.Grouping);
        end

        function setLevels_(obj)
            try
                obj.Study.setLevels(obj.Grouping, obj.splitLevels_(obj.H.levels.Value));
            catch ME
                obj.say_(ME.message);
                obj.refresh();
            end
        end

        function onSubjectEdit_(obj, evt)
            row = evt.Indices(1);
            subject = string(obj.H.subjects.Data{row, 1});
            level = string(evt.NewData);
            if level == obj.NONE, level = ""; end
            obj.assign_(subject, level);
        end

        function onSessionEdit_(obj, evt)
            row = evt.Indices(1);      % DATA row
            key = obj.SessionKeys_(row);
            level = string(evt.NewData);
            if level == obj.INHERIT, level = ""; end
            obj.assign_(key, level);
        end

        function assign_(obj, target, level)
            try
                obj.Study.assign(obj.Grouping, target, level);
            catch ME
                obj.say_(ME.message);
                obj.refresh();
            end
        end

        function levels = splitLevels_(~, txt)
            parts = split(string(txt), ",");
            levels = reshape(strtrim(parts(strtrim(parts) ~= "")), 1, []);
        end

        function say_(obj, message)
            if strcmp(obj.H.figure.Visible, 'on')
                uialert(obj.H.figure, char(message), 'Groupings');
            else
                vprintf(1, 'gui.behavior.GroupingsDialog: %s', message);
            end
        end
    end
end
