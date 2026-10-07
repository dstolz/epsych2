classdef Browser < gui.behavior.View
    % gui.behavior.Browser  Every session of a data root as a checkbox tree.
    %
    % The left side of epsych.BehaviorAnalysis: Project > Subject > Session,
    % each session node reading "yyyy-MM-dd HH:mm · tags · n trials". The
    % CHECKED sessions are the analysed set (behavior.Study.select, kept in
    % the project file); the SELECTED node is the one the window shows. A
    % search field and a Show filter narrow what is listed without changing
    % what is checked: checking in a filtered tree changes only the listed
    % sessions' part of the selection.
    %
    %   B = gui.behavior.Browser(container, study);
    %   B.OnSelect = @(nodeData) ...;          % a node was selected
    %   B.OnOpenSession = @(key) ...;          % Enter, double-click, Open
    %
    % Styles: grey = hidden, unreadable or no trials; amber = a file-level
    % QC flag (behavior.Catalog QCFile); italic = run in test mode. The
    % details pane under the tree describes the selected node: the file, its
    % subject (with the roster's facts), tags, notes, QC, the window
    % override and the comments.
    %
    % THE SEARCH FIELD filters as you type. The keystrokes are kept in
    % LiveFilter_ and the field's Value is never written from its
    % ValueChangingFcn -- writing it there drops characters typed while the
    % tree rebuilds (gui.SubjectManager's documented trap).
    %
    % See also: gui.behavior.View, epsych.BehaviorAnalysis, behavior.Study

    properties
        OnSelect = []           % @(nodeData) a node was selected
        OnOpenSession = []      % @(key) open a session
        OnFilterChanged = []    % @(showText) the operator changed Show
    end

    properties (SetAccess = private)
        Filter (1,1) string = "All"
        NodeKeys (1,:) string = strings(1, 0)    % the session nodes listed, in tree order
    end

    properties (Constant)
        SHOW = ["All" "Checked" "Hidden" "Test" "Needs attention"]
    end

    properties (Access = private)
        LiveFilter_ (1,1) string = ""
        SessionNodes_ = []
        Signature_ (1,1) string = ""
    end

    properties (Constant, Access = private)
        GREY  (1,3) double = [0.58 0.60 0.64]
        AMBER (1,3) double = [0.72 0.42 0.02]
        EXPAND_ALL_BELOW = 400     % sessions; beyond this only projects open
    end

    methods
        function obj = Browser(parent, study)
            obj@gui.behavior.View(parent, study);
            obj.refresh("show");
        end

        function build(obj)
            g = uigridlayout(obj.Parent, [3 1]);
            g.RowHeight = {24, '1x', 150};
            g.Padding = [0 0 0 0];
            g.RowSpacing = 6;
            obj.H.root = g;

            top = uigridlayout(g, [1 2]);
            top.ColumnWidth = {'1x', 120};
            top.Padding = [0 0 0 0];
            top.ColumnSpacing = 6;
            obj.H.search = uieditfield(top, 'text', 'Placeholder', 'Find subject, tag, file...', ...
                'Tooltip', 'Filter the list as you type (Ctrl+F). Matches project, subject, tags and file name.', ...
                'ValueChangingFcn', @(~, evt) obj.onSearch_(string(evt.Value)), ...
                'ValueChangedFcn', @(src, ~) obj.onSearch_(string(src.Value)));
            obj.H.show = uidropdown(top, 'Items', cellstr(obj.SHOW), 'Value', 'All', ...
                'Tooltip', ['All: every session not hidden. Checked: the analysed ones. Hidden: ' ...
                    'the hidden ones. Test: run in test mode. Needs attention: a file-level QC flag.'], ...
                'ValueChangedFcn', @(src, ~) obj.onShowChanged_(string(src.Value)));

            obj.H.tree = uitree(g, 'checkbox', ...
                'CheckedNodesChangedFcn', @(~,~) obj.onChecked_(), ...
                'SelectionChangedFcn', @(~,~) obj.onSelected_(), ...
                'DoubleClickedFcn', @(~,~) obj.open());
            obj.H.details = uitextarea(g, 'Editable', 'off', 'Value', {''}, ...
                'FontColor', [0.20 0.22 0.26]);

            cm = uicontextmenu(ancestor(obj.Parent, 'figure'));
            obj.H.cm = cm;
            obj.H.cm_open = uimenu(cm, 'Text', 'Open', 'MenuSelectedFcn', @(~,~) obj.open());
            obj.H.cm_review = uimenu(cm, 'Text', 'Review Session...', 'MenuSelectedFcn', @(~,~) obj.review());
            obj.H.cm_hide = uimenu(cm, 'Text', 'Hide', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.toggleHidden());
            obj.H.cm_window = uimenu(cm, 'Text', 'Trial Window Override...', ...
                'MenuSelectedFcn', @(~,~) obj.promptWindow(obj.selectedKey_()));
            obj.H.cm_comment = uimenu(cm, 'Text', 'Comment...', 'MenuSelectedFcn', @(~,~) obj.promptComment(""));
            obj.H.cm_assign = uimenu(cm, 'Text', 'Assign to grouping');
            obj.H.cm_check = uimenu(cm, 'Text', 'Check subtree', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) obj.checkSubtree(true));
            obj.H.cm_uncheck = uimenu(cm, 'Text', 'Uncheck subtree', 'MenuSelectedFcn', @(~,~) obj.checkSubtree(false));
            obj.H.cm_copy = uimenu(cm, 'Text', 'Copy Path', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) obj.copyPath(obj.selectedKey_()));
            obj.H.cm_folder = uimenu(cm, 'Text', 'Show in Folder', ...
                'MenuSelectedFcn', @(~,~) obj.showInFolder(obj.selectedKey_()));
            cm.ContextMenuOpeningFcn = @(~, evt) obj.onContextMenu_(evt);
            obj.H.tree.ContextMenu = cm;
        end

        function refresh(obj, reason)
            % refresh(obj, reason)
            % Rebuild the tree when what it lists changed; otherwise only the
            % checks and the details follow.
            arguments
                obj
                reason (1,1) string = "show"
            end
            if ~isvalid(obj) || ~isgraphics(obj.H.root)
                return
            end
            switch reason
                case {"show" "CatalogChanged" "ProjectChanged"}
                    obj.rebuild_(reason == "show" || reason == "CatalogChanged");
                case "SelectionChanged"
                    if obj.Filter == "Checked"
                        obj.rebuild_(false);
                    else
                        obj.applyChecks_();
                    end
            end
        end

        % ------------------------------------------------------- public seam
        function setFilter(obj, name)
            % setFilter(obj, name)
            % The Show filter: "All", "Checked", "Hidden", "Test", "Needs attention".
            arguments
                obj
                name (1,1) string {mustBeMember(name, ["All" "Checked" "Hidden" "Test" "Needs attention"])}
            end
            obj.Filter = name;
            obj.H.show.Value = char(name);
            obj.rebuild_(true);
        end

        function setSearch(obj, text)
            % setSearch(obj, text)
            % What the search field filters on (as if typed).
            arguments
                obj
                text (1,1) string
            end
            obj.H.search.Value = char(text);
            obj.onSearch_(text);
        end

        function reveal(obj, key)
            % reveal(obj, key)
            % Select a session's node (no callback) when it is listed.
            arguments
                obj
                key (1,1) string
            end
            i = find(obj.norm_(obj.NodeKeys) == obj.norm_(key), 1);
            if isempty(i)
                return
            end
            n = obj.SessionNodes_(i);
            obj.H.tree.SelectedNodes = n;
            try
                expand(n.Parent);
                scroll(obj.H.tree, n);
            catch ME
                vprintf(3, ME);
            end
            obj.showDetails_(n.NodeData);
        end

        function open(obj)
            % open(obj)
            % Open the selected session (OnOpenSession).
            key = obj.selectedKey_();
            if key ~= "" && ~isempty(obj.OnOpenSession)
                obj.OnOpenSession(key);
            end
        end

        function review(obj)
            key = obj.selectedKey_();
            if key == "", return, end
            try
                row = obj.Study.Catalog.session(key);
                epsych.ReviewSession(char(row.File));
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus("Review Session: " + string(ME.message));
            end
        end

        function toggleHidden(obj)
            % toggleHidden(obj)
            % Hide the selected session(s), or show them again when hidden.
            keys = obj.selectedKeys_();
            if isempty(keys), return, end
            tf = ~all(obj.Study.isHidden(keys));
            obj.Study.hide(keys, tf);
            if tf
                obj.setStatus(sprintf("Hid %d session(s); Show > Hidden lists them.", numel(keys)));
            else
                obj.setStatus(sprintf("%d session(s) shown again.", numel(keys)));
            end
        end

        function promptWindow(obj, key)
            % promptWindow(obj, key)
            % Ask for a session's trial-window override.
            arguments
                obj
                key (1,1) string
            end
            if key == "", return, end
            a = inputdlg({sprintf(['Trials of this session to analyse: "all", "last 100", "3-83", "20+".\n' ...
                'Empty uses the analysis settings (%s).'], obj.Study.Settings.Window)}, ...
                'Trial Window Override', [1 60], {char(obj.Study.windowFor(key))});
            if isempty(a), return, end
            try
                obj.Study.setWindow(key, strtrim(string(a{1})));
            catch ME
                obj.setStatus(string(ME.message));
            end
        end

        function promptComment(obj, keyOrSubject)
            % promptComment(obj, keyOrSubject)
            % Ask for a comment on a session (by key) or a subject (by name);
            % "" = the selected node.
            arguments
                obj
                keyOrSubject (1,1) string
            end
            if keyOrSubject == ""
                nd = obj.selectedData_();
                if isempty(nd) || nd.Kind == "project", return, end
                keyOrSubject = nd.Key;
            end
            a = inputdlg({char("Comment on " + keyOrSubject + " (empty removes it):")}, 'Comment', ...
                [4 70], {char(obj.Study.Project.commentFor(keyOrSubject))});
            if isempty(a), return, end
            txt = strjoin(strtrim(string(cellstr(a{1}))), " ");
            obj.Study.setComment(keyOrSubject, txt);
        end

        function checkSubtree(obj, tf)
            % checkSubtree(obj, tf)
            % Check or uncheck every listed session under the selected node.
            nd = obj.selectedData_();
            if isempty(nd), return, end
            keys = obj.keysUnder_(nd);
            sel = obj.Study.Selection;
            if tf
                sel = [sel keys(~ismember(obj.norm_(keys), obj.norm_(sel)))];
            else
                sel = sel(~ismember(obj.norm_(sel), obj.norm_(keys)));
            end
            obj.Study.select(sel);
        end

        function copyPath(obj, key)
            arguments
                obj
                key (1,1) string
            end
            if key == "", return, end
            row = obj.Study.Catalog.session(key);
            try
                clipboard('copy', char(row.File));
                obj.setStatus("Copied " + row.File);
            catch ME
                obj.setStatus("The clipboard is not available here: " + string(ME.message));
            end
        end

        function showInFolder(obj, key)
            arguments
                obj
                key (1,1) string
            end
            if key == "", return, end
            row = obj.Study.Catalog.session(key);
            try
                epsych.SubjectRoster.openLink(char(row.Folder));
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus("Show in Folder: " + string(ME.message));
            end
        end

        function focusSearch(obj)
            try
                focus(obj.H.search);
            catch ME
                vprintf(3, ME);
            end
        end

        function c = counts(obj)
            % c = counts(obj)
            % Nodes listed: struct Projects, Subjects, Sessions.
            p = obj.H.tree.Children;
            ns = 0;
            for k = 1:numel(p)
                ns = ns + numel(p(k).Children);
            end
            c = struct('Projects', numel(p), 'Subjects', ns, 'Sessions', numel(obj.NodeKeys));
        end
    end

    methods (Access = private)
        % ------------------------------------------------------- building
        function rebuild_(obj, force)
            S = obj.Study;
            T = S.sessions(IncludeHidden = true);
            rows = obj.filterRows_(T);
            sig = obj.signature_(T, rows);
            if ~force && sig == obj.Signature_
                obj.applyChecks_();
                obj.showDetails_(obj.selectedData_());
                return
            end
            obj.Signature_ = sig;

            keep = obj.selectedData_();
            tree = obj.H.tree;
            delete(tree.Children);
            removeStyle(tree);
            obj.SessionNodes_ = [];
            obj.NodeKeys = strings(1, 0);

            R = T(rows, :);
            n = height(R);
            if n == 0
                obj.showDetails_([]);
                return
            end
            keys = reshape(string(R.Key), 1, []);
            nodes = gobjects(1, n);
            grey = false(1, n);
            amber = false(1, n);
            italic = false(1, n);
            proj = string(R.Project);
            subj = string(R.Subject);
            [up, ~, ip] = unique(proj, 'stable');
            for a = 1:numel(up)
                inP = find(ip == a)';
                pn = uitreenode(tree, 'Text', char(sprintf("%s (%d)", up(a), numel(inP))), ...
                    'NodeData', obj.nodeData_("project", up(a), up(a), ""));
                [us, ~, is] = unique(subj(inP), 'stable');
                for b = 1:numel(us)
                    inS = inP(is == b);
                    sn = uitreenode(pn, 'Text', char(sprintf("%s (%d)", us(b), numel(inS))), ...
                        'NodeData', obj.nodeData_("subject", us(b), up(a), us(b)));
                    for i = inS
                        nodes(i) = uitreenode(sn, 'Text', char(obj.sessionText_(R(i, :))), ...
                            'NodeData', obj.nodeData_("session", keys(i), up(a), us(b)));
                        grey(i) = R.Hidden(i) || R.Error(i) ~= "" || R.Trials(i) == 0;
                        amber(i) = ~grey(i) && ~isempty(R.QCFile{i});
                        italic(i) = R.IsTest(i);
                    end
                end
            end
            obj.SessionNodes_ = nodes;
            obj.NodeKeys = keys;

            if any(grey), addStyle(tree, uistyle('FontColor', obj.GREY), 'node', nodes(grey)); end
            if any(amber), addStyle(tree, uistyle('FontColor', obj.AMBER), 'node', nodes(amber)); end
            if any(italic), addStyle(tree, uistyle('FontAngle', 'italic'), 'node', nodes(italic)); end

            if n < obj.EXPAND_ALL_BELOW
                expand(tree, 'all');
            else
                expand(tree);
            end
            obj.applyChecks_();
            obj.restoreSelection_(keep);
        end

        function rows = filterRows_(obj, T)
            n = height(T);
            if n == 0
                rows = false(0, 1);
                return
            end
            switch obj.Filter
                case "All"
                    rows = ~T.Hidden;
                case "Checked"
                    rows = ~T.Hidden & ismember(obj.norm_(T.Key), obj.norm_(obj.Study.Selection));
                case "Hidden"
                    rows = T.Hidden;
                case "Test"
                    rows = T.IsTest & ~T.Hidden;
                case "Needs attention"
                    rows = ~T.Hidden & (cellfun(@(q) ~isempty(q), T.QCFile) | T.Error ~= "" | T.Trials == 0);
            end
            q = strtrim(obj.LiveFilter_);
            if q ~= ""
                hay = lower(string(T.Project) + " " + string(T.Subject) + " " + string(T.TagText) ...
                    + " " + string(T.FileName));
                for w = split(lower(q))'
                    rows = rows & contains(hay, w);
                end
            end
        end

        function sig = signature_(obj, T, rows)
            % What the listing depends on: which sessions, how each is styled
            % and labelled. A ProjectChanged for a setting changes none of it.
            if ~any(rows)
                sig = obj.Filter + "|empty";
                return
            end
            R = T(rows, :);
            parts = string(R.Key) + string(R.Hidden) + string(R.IsTest) + string(R.Trials) ...
                + string(R.Window ~= "") + string(R.Comment ~= "");
            sig = obj.Filter + "|" + behavior.hex8(char(strjoin(parts, "|")));
        end

        function txt = sessionText_(~, row)
            parts = strings(1, 0);
            if isdatetime(row.Start) && ~isnat(row.Start)
                parts(end+1) = string(row.Start, 'yyyy-MM-dd HH:mm');
            else
                parts(end+1) = string(row.FileName);
            end
            if string(row.TagText) ~= ""
                parts(end+1) = strjoin(string(row.Tags{1}), " ");
            end
            parts(end+1) = sprintf("%d trials", row.Trials);
            txt = strjoin(parts, " · ");
            if row.Window ~= ""
                txt = txt + "  [" + row.Window + "]";
            end
            if row.Comment ~= ""
                txt = txt + "  *";
            end
        end

        function nd = nodeData_(~, kind, key, project, subject)
            nd = struct('Kind', kind, 'Key', key, 'Project', project, 'Subject', subject);
        end

        function applyChecks_(obj)
            if isempty(obj.SessionNodes_)
                return
            end
            on = ismember(obj.norm_(obj.NodeKeys), obj.norm_(obj.Study.Selection));
            if any(on)
                obj.H.tree.CheckedNodes = obj.SessionNodes_(on);
            else
                obj.H.tree.CheckedNodes = [];
            end
        end

        function restoreSelection_(obj, nd)
            if isempty(nd)
                obj.showDetails_([]);
                return
            end
            if nd.Kind == "session"
                i = find(obj.norm_(obj.NodeKeys) == obj.norm_(nd.Key), 1);
                if ~isempty(i)
                    obj.H.tree.SelectedNodes = obj.SessionNodes_(i);
                    obj.showDetails_(nd);
                    return
                end
            else
                n = obj.findNode_(nd);
                if ~isempty(n)
                    obj.H.tree.SelectedNodes = n;
                    obj.showDetails_(nd);
                    return
                end
            end
            obj.showDetails_([]);
        end

        function n = findNode_(obj, nd)
            n = [];
            for p = reshape(obj.H.tree.Children, 1, [])
                if nd.Kind == "project" && p.NodeData.Key == nd.Key
                    n = p;
                    return
                end
                for s = reshape(p.Children, 1, [])
                    if nd.Kind == "subject" && s.NodeData.Key == nd.Key && s.NodeData.Project == nd.Project
                        n = s;
                        return
                    end
                end
            end
        end

        % ------------------------------------------------------- callbacks
        function onSearch_(obj, text)
            obj.LiveFilter_ = text;
            obj.rebuild_(true);
        end

        function onShowChanged_(obj, value)
            obj.Filter = value;
            obj.rebuild_(true);
            if ~isempty(obj.OnFilterChanged)
                obj.OnFilterChanged(value);
            end
        end

        function onChecked_(obj)
            % The listed sessions' part of the selection is the checked
            % nodes; sessions not listed keep their state.
            checked = obj.checkedKeys_();
            sel = obj.Study.Selection;
            listed = obj.norm_(obj.NodeKeys);
            keep = sel(~ismember(obj.norm_(sel), listed));
            stay = sel(ismember(obj.norm_(sel), obj.norm_(checked)));
            added = checked(~ismember(obj.norm_(checked), obj.norm_(sel)));
            try
                obj.Study.select([keep stay added]);
                obj.setStatus(sprintf("%d session(s) checked for analysis.", numel(obj.Study.Selection)));
            catch ME
                vprintf(0, 1, ME);
                obj.applyChecks_();
            end
        end

        function keys = checkedKeys_(obj)
            keys = strings(1, 0);
            C = obj.H.tree.CheckedNodes;
            if isempty(C), return, end
            D = [C.NodeData];
            D = D(string({D.Kind}) == "session");
            if ~isempty(D)
                keys = reshape([D.Key], 1, []);
            end
        end

        function onSelected_(obj)
            nd = obj.selectedData_();
            obj.showDetails_(nd);
            if ~isempty(nd) && ~isempty(obj.OnSelect)
                obj.OnSelect(nd);
            end
        end

        function onContextMenu_(obj, evt)
            % Act on the node right-clicked: select it first.
            target = evt.ContextObject;
            if isa(target, 'matlab.ui.container.TreeNode')
                if isempty(obj.H.tree.SelectedNodes) || ~any(obj.H.tree.SelectedNodes == target)
                    obj.H.tree.SelectedNodes = target;
                    obj.onSelected_();
                end
            end
            nd = obj.selectedData_();
            isSess = ~isempty(nd) && nd.Kind == "session";
            hasNode = ~isempty(nd);
            obj.H.cm_open.Enable = matlab.lang.OnOffSwitchState(isSess);
            obj.H.cm_review.Enable = matlab.lang.OnOffSwitchState(isSess);
            obj.H.cm_window.Enable = matlab.lang.OnOffSwitchState(isSess);
            obj.H.cm_copy.Enable = matlab.lang.OnOffSwitchState(isSess);
            obj.H.cm_folder.Enable = matlab.lang.OnOffSwitchState(isSess);
            obj.H.cm_comment.Enable = matlab.lang.OnOffSwitchState(hasNode && nd.Kind ~= "project");
            obj.H.cm_check.Enable = matlab.lang.OnOffSwitchState(hasNode);
            obj.H.cm_uncheck.Enable = matlab.lang.OnOffSwitchState(hasNode);
            keys = obj.selectedKeys_();
            obj.H.cm_hide.Enable = matlab.lang.OnOffSwitchState(~isempty(keys));
            if ~isempty(keys) && all(obj.Study.isHidden(keys))
                obj.H.cm_hide.Text = 'Unhide';
            else
                obj.H.cm_hide.Text = 'Hide';
            end
            obj.fillAssignMenu_(nd);
        end

        function fillAssignMenu_(obj, nd)
            m = obj.H.cm_assign;
            delete(m.Children);
            G = obj.Study.Project.Groupings;
            ok = ~isempty(nd) && nd.Kind ~= "project" && ~isempty(G);
            m.Enable = matlab.lang.OnOffSwitchState(ok);
            if ~ok, return, end
            target = nd.Key;     % a subject's name, or a session's key (an override)
            for g = 1:numel(G)
                name = G(g).Name;
                cur = obj.Study.Project.groupingLevel(name, obj.keyOrEmpty_(nd), nd.Subject);
                sub = uimenu(m, 'Text', char(name));
                for L = ["" reshape(G(g).Levels, 1, [])]
                    txt = L;
                    if L == "", txt = "(none)"; end
                    uimenu(sub, 'Text', char(txt), 'Checked', matlab.lang.OnOffSwitchState(L == cur), ...
                        'MenuSelectedFcn', @(~,~) obj.assign_(name, target, L));
                end
            end
        end

        function k = keyOrEmpty_(~, nd)
            k = "";
            if nd.Kind == "session", k = nd.Key; end
        end

        function assign_(obj, name, target, level)
            try
                obj.Study.assign(name, target, level);
                obj.setStatus(sprintf("%s: %s is now in ""%s"".", name, target, level));
            catch ME
                obj.setStatus(string(ME.message));
            end
        end

        % ------------------------------------------------------- details
        function showDetails_(obj, nd)
            if isempty(nd)
                obj.H.details.Value = {''};
                return
            end
            S = obj.Study;
            L = strings(0, 1);
            switch nd.Kind
                case "project"
                    T = S.sessions(IncludeHidden = true);
                    in = string(T.Project) == nd.Key;
                    L(end+1) = "Project " + nd.Key;
                    L(end+1) = sprintf("%d session(s) of %d subject(s), %d hidden", sum(in), ...
                        numel(unique(string(T.Subject(in)))), sum(T.Hidden(in)));
                case "subject"
                    L = obj.subjectLines_(nd);
                case "session"
                    L = obj.sessionLines_(nd.Key);
            end
            obj.H.details.Value = cellstr(L);
        end

        function L = subjectLines_(obj, nd)
            S = obj.Study;
            C = S.Catalog.Subjects;
            L = "Subject " + nd.Key + " in " + nd.Project;
            i = find(string(C.Subject) == nd.Key & string(C.Project) == nd.Project, 1);
            if ~isempty(i)
                r = C(i, :);
                L(end+1) = sprintf("%d session(s), %s to %s", r.NumSessions, obj.when_(r.FirstSession), obj.when_(r.LastSession));
                L(end+1) = "Sex " + obj.orDash_(r.Sex) + "  ·  Species " + obj.orDash_(r.Species);
                names = string(C.Properties.VariableNames);
                if ismember("RosterKnown", names)
                    if r.RosterKnown
                        L(end+1) = "Roster: " + obj.orDash_(r.RosterSex) + ", " + obj.orDash_(r.RosterSpecies) ...
                            + "; projects " + obj.orDash_(strjoin(string(r.RosterProjects), ", ")) ...
                            + "; last protocol " + obj.orDash_(r.RosterLastProtocol);
                    else
                        L(end+1) = "Roster: not in the roster";
                    end
                end
            end
            c = S.Project.commentFor(nd.Key);
            if c ~= "", L(end+1) = "Comment: " + c; end
            G = S.Project.Groupings;
            levels = arrayfun(@(g) g.Name + ": " + obj.orDash_(S.Project.groupingLevel(g.Name, "", nd.Key)), G);
            L = [L reshape(string(levels), 1, [])];
        end

        function L = sessionLines_(obj, key)
            S = obj.Study;
            row = S.Catalog.session(key);
            L = string(row.File);
            when = obj.when_(row.Start);
            if isduration(row.Duration) && ~isnan(row.Duration)
                when = when + " for " + string(round(minutes(row.Duration))) + " min";
            end
            L(end+1) = "When: " + when;
            L(end+1) = sprintf("%s / %s  ·  %d trials (%d test)  ·  box %s  ·  %s", row.Project, row.Subject, ...
                row.Trials, row.NumTest, obj.orDash_(string(row.BoxID)), obj.orDash_(row.Paradigm));
            L(end+1) = "Subject: sex " + obj.orDash_(row.SubjectSex) + ", species " + obj.orDash_(row.SubjectSpecies);
            T = S.sessions(IncludeHidden = true);
            j = find(obj.norm_(T.Key) == obj.norm_(key), 1);
            if ~isempty(j) && ismember("RosterKnown", string(T.Properties.VariableNames))
                if T.RosterKnown(j)
                    L(end+1) = "Roster: " + obj.orDash_(T.RosterSex(j)) + ", " + obj.orDash_(T.RosterSpecies(j));
                else
                    L(end+1) = "Roster: not in the roster";
                end
            end
            tags = string(row.Tags{1});
            L(end+1) = "Tags: " + obj.orDash_(strjoin(tags, ", "));
            qc = string(row.QCFile{1});
            if ~isempty(qc), L(end+1) = "QC: " + strjoin(qc, ", "); end
            if row.Error ~= "", L(end+1) = "Error: " + row.Error; end
            w = S.windowFor(key);
            if w ~= ""
                L(end+1) = "Trial window override: " + w;
            else
                L(end+1) = "Trial window: the settings' (" + S.Settings.Window + ")";
            end
            if S.isHidden(key)
                L(end+1) = "HIDDEN";
            end
            c = S.Project.commentFor(key);
            if c ~= "", L(end+1) = "Comment: " + c; end
            notes = string(row.NotesText);
            if notes ~= ""
                L(end+1) = "Notes:";
                L = [reshape(L, 1, []) reshape(splitlines(notes), 1, [])];
            end
        end

        % ------------------------------------------------------- helpers
        function nd = selectedData_(obj)
            nd = [];
            n = obj.H.tree.SelectedNodes;
            if ~isempty(n) && isvalid(n(1))
                nd = n(1).NodeData;
            end
        end

        function key = selectedKey_(obj)
            key = "";
            nd = obj.selectedData_();
            if ~isempty(nd) && nd.Kind == "session"
                key = nd.Key;
            end
        end

        function keys = selectedKeys_(obj)
            % The selected node's sessions: itself, or every listed one under it.
            nd = obj.selectedData_();
            if isempty(nd)
                keys = strings(1, 0);
            else
                keys = obj.keysUnder_(nd);
            end
        end

        function keys = keysUnder_(obj, nd)
            switch nd.Kind
                case "session"
                    keys = nd.Key;
                otherwise
                    in = false(1, numel(obj.SessionNodes_));
                    for i = 1:numel(obj.SessionNodes_)
                        d = obj.SessionNodes_(i).NodeData;
                        in(i) = d.Project == nd.Project && (nd.Kind == "project" || d.Subject == nd.Subject);
                    end
                    keys = obj.NodeKeys(in);
            end
        end

        function k = norm_(~, keys)
            k = epsych.BehaviorAnalysis.normKey(keys);
        end

        function s = when_(~, t)
            if isdatetime(t) && ~isnat(t)
                s = string(t, 'yyyy-MM-dd HH:mm');
            else
                s = "unknown";
            end
        end

        function s = orDash_(~, v)
            s = string(v);
            if isempty(s) || ismissing(s(1)) || s(1) == "" || s(1) == "NaN"
                s = "-";
            else
                s = s(1);
            end
        end
    end
end
