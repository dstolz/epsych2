classdef BehaviorAnalysis < handle
    % epsych.BehaviorAnalysis  Offline behavioral analysis across sessions, subjects and projects.
    %
    % One window over one data root (<root>/<Project>/<Subject>/<files>.mat):
    % a checkbox tree of every session on the left, and five tabs on the
    % right -- one Session (its staircase, thresholds, fit and notes), one
    % Subject (learning curves and every staircase overlaid), a Compare tab
    % across the checked sessions grouped by any facet, a Table of the
    % numbers, and the shown session's psychometric Fit (psignifit's own
    % plots and posteriors when psignifit fits). Every analysis it shows can
    % be written out as a plain MATLAB script that reproduces it exactly,
    % and every table exported.
    %
    %   epsych.BehaviorAnalysis                    % opens the last root
    %   epsych.BehaviorAnalysis("D:\Data\Lab")
    %   app = epsych.BehaviorAnalysis(root, Visible = false);   % headless, for tests
    %
    % THE WINDOW HOLDS NO DATA. Everything it shows is read from a
    % behavior.Study (catalog, project file, settings, memoized results), and
    % every change goes through the Study's methods, whose events every view
    % follows -- which is also what makes the window drivable from code
    % through the public methods below with Visible = false.
    %
    % ONE WINDOW. A second call raises the open window -- and opens its root
    % there when one is given -- rather than replacing it, because the window
    % holds decisions (hidden sessions, windows, groupings) that may not be
    % saved yet. epsych.BehaviorAnalysis.find() returns it.
    %
    % WHAT IS WRITTEN WHERE. Under the root, only <root>/EPsych_Analysis/
    % (behavior.Project's project.json, at Save); the scan cache goes to
    % %LOCALAPPDATA%\EPsych\AnalysisCache; a root that cannot be written gets
    % an alternate store folder, remembered per root. This window's own
    % preferences (group PREF_TAG) are machine state only -- position, recent
    % roots, the browser's filter, the last tab, export folder and formats,
    % the Subject tab's overlay display (SubjectOverlay) -- and are written
    % only from controls the user operated.
    %
    % Only between sessions: scanning reads every file on the MATLAB thread
    % the trial loop runs on, so the window refuses to scan while
    % epsych.RunExpt is running. Review Session... stays available.
    %
    % Public methods (each what the matching control does):
    %   openRoot(root), rescan(), saveProject(), selectSession(key),
    %   check(keys, tf), hide(keys, tf), setWindowOverride(key, text),
    %   setFacet(role, text), applySettings(s), showTab(name),
    %   exportTables(folder, Formats=), exportFigure(file),
    %   writeScript(file, Scope=), recomputeAll()
    %
    % Properties (read-only):
    %   Study - the behavior.Study ([] until a root is open)
    %   Views - struct Browser, Session, Subject, Compare, Table, Fit
    %   H     - graphics handles
    %
    % Documentation: documentation/behavior/BehaviorAnalysis_UserGuide.md
    % See also: behavior.Study, gui.behavior.View, behavior.ScriptWriter

    properties (SetAccess = private)
        Study = []
        Views (1,1) struct = struct()
        H (1,1) struct = struct()
    end

    properties (Constant)
        FIGURE_TAG (1,:) char = 'EPsychBehaviorAnalysis'
        PREF_TAG (1,:) char = 'epsych2_BehaviorAnalysis'
        DEFAULT_POSITION (1,4) double = [80 60 1440 880]
        TAB_NAMES (1,5) string = ["Session" "Subject" "Compare" "Table" "Fit"]
        MAX_RECENT (1,1) double = 10
    end

    properties (Constant, Access = private)
        MUTED (1,3) double = [0.35 0.38 0.42]
        WARN (1,3) double = [0.60 0.32 0.02]
        BAR_COLOR (1,3) double = [1.00 0.95 0.75]
        DEFAULT_BROWSER_WIDTH (1,1) double = 340
        BAR_HEIGHT (1,1) double = 30
    end

    properties (Access = private)
        StudyListeners_ = event.listener.empty
        CacheFolder_ (1,1) string = ""
        Roster_ (1,1) string = "auto"
        Updating_ (1,1) logical = false     % refreshHeader_ is writing the controls
        StoreProblem_ (1,1) string = ""     % why the last save failed, if it did
        BrowserVisible_ (1,1) logical = true
        BarDismissed_ (1,1) string = ""     % the bar text the operator dismissed
    end

    % -----------------------------------------------------------------------
    methods
        function self = BehaviorAnalysis(root, options)
            % app = epsych.BehaviorAnalysis(root, Visible=, Store=, Roster=, CacheFolder=)
            %
            % Parameters:
            %   root        - data root to open ("" = the last one, when shown)
            %   Visible     - show the window (false for headless tests)
            %   Store       - alternate project store folder for this root
            %   Roster      - "auto" | "none" | an .esub file (enriches subjects)
            %   CacheFolder - scan cache folder (default
            %                 behavior.Catalog.defaultCacheFolder())
            arguments
                root (1,1) string = ""
                options.Visible (1,1) logical = true
                options.Store (1,1) string = ""
                options.Roster (1,1) string = "auto"
                options.CacheFolder (1,1) string = behavior.Catalog.defaultCacheFolder()
            end

            prior = epsych.BehaviorAnalysis.find();
            if ~isempty(prior)
                % The open window may hold unsaved decisions: raise it.
                self = prior;
                if options.Visible
                    self.H.figure.Visible = 'on';
                    figure(self.H.figure);
                end
                if root ~= "" && ~self.isOpen_(root)
                    self.openRoot(root, Store = options.Store);
                end
                if nargout == 0
                    clear self
                end
                return
            end

            self.CacheFolder_ = options.CacheFolder;
            self.Roster_ = options.Roster;
            self.BrowserVisible_ = logical(self.getPref_('BrowserVisible', true));
            self.buildUI(options.Visible);
            self.refreshHeader_();

            if root == "" && options.Visible
                last = string(self.getPref_('LastRoot', ""));
                if last ~= "" && isfolder(last)
                    root = last;
                end
            end
            if root ~= ""
                self.openRoot(root, Store = options.Store);
            else
                self.setStatus_("Open a data root (File > Open Root..., Ctrl+O) to begin.");
            end

            if nargout == 0
                clear self
            end
        end

        function delete(self)
            % delete(self)
            % Close the window: release the Study's listeners and every view.
            % Never asks about unsaved changes -- closing from the window does.
            self.releaseStudy_();
            try
                if isfield(self.H, 'figure') && isgraphics(self.H.figure)
                    if strcmp(self.H.figure.Visible, 'on')
                        gui.BehaviorGUI.saveFigurePosition(self.PREF_TAG, self.H.figure.Position);
                    end
                    self.H.figure.UserData = [];
                    self.H.figure.CloseRequestFcn = '';
                    delete(self.H.figure);
                end
            catch ME
                vprintf(2, ME);
            end
        end

        % ---------------------------------------------------- public seam
        ok = openRoot(self, root, options)
        ok = rescan(self)
        selectSession(self, key)
        showTab(self, name)
        file = writeScript(self, file, options)
        files = exportTables(self, folder, options)
        file = exportFigure(self, file)

        function ok = saveProject(self)
            % ok = saveProject(self)
            % Write the project file. A store that cannot be written shows
            % the notification bar, which offers an alternate store folder.
            ok = false;
            if isempty(self.Study)
                return
            end
            P = self.Study.Project;
            ok = self.Study.save();
            if ok
                self.StoreProblem_ = "";
                self.setStatus_("Saved " + P.File + " (revision " + P.Revision + ")");
            else
                if P.ReadOnly
                    self.StoreProblem_ = "The project file is read-only: " + strjoin(P.Warnings, " ");
                else
                    self.StoreProblem_ = "The project cannot be saved: " + P.Store + " cannot be written.";
                end
                self.alert_(self.StoreProblem_ + " Choose a store folder from the yellow bar.", ...
                    'Save Project', 'warning');
            end
            self.refreshHeader_();
        end

        function check(self, keys, tf)
            % check(self, keys, tf)
            % Check (tf true) or uncheck sessions: the analysed set.
            arguments
                self
                keys (1,:) string
                tf (1,1) logical = true
            end
            if isempty(self.Study), return, end
            sel = self.Study.Selection;
            if tf
                sel = [sel keys(~ismember(epsych.BehaviorAnalysis.normKey(keys), epsych.BehaviorAnalysis.normKey(sel)))];
            else
                sel = sel(~ismember(epsych.BehaviorAnalysis.normKey(sel), epsych.BehaviorAnalysis.normKey(keys)));
            end
            self.Study.select(sel);
        end

        function hide(self, keys, tf, options)
            % hide(self, keys, tf, Reason = "")
            % Hide sessions from every list and analysis (tf false shows them).
            arguments
                self
                keys (1,:) string
                tf (1,1) logical = true
                options.Reason (1,1) string = ""
            end
            if isempty(self.Study) || isempty(keys), return, end
            self.Study.hide(keys, tf, Reason = options.Reason);
            if tf
                self.setStatus_(sprintf("Hid %d session(s). View > Show > Hidden lists them.", numel(keys)));
            else
                self.setStatus_(sprintf("%d session(s) shown again.", numel(keys)));
            end
        end

        function ok = setWindowOverride(self, key, text)
            % ok = setWindowOverride(self, key, text)
            % A trial window for one session ("" = the settings' window).
            arguments
                self
                key (1,1) string
                text (1,1) string
            end
            ok = false;
            if isempty(self.Study), return, end
            try
                self.Study.setWindow(key, text);
                ok = true;
            catch ME
                self.alert_(string(ME.message), 'Trial Window', 'warning');
            end
        end

        function ok = setFacet(self, role, text)
            % ok = setFacet(self, role, text)
            % One part of the Compare view: role GroupBy, ColorBy, XAxis,
            % Value, Kind or ColorMap; text as behavior.Facet.toText
            % ("tag:1"), or a behavior.Plot.COLOR_MAPS name for ColorMap.
            arguments
                self
                role (1,1) string {mustBeMember(role, ["GroupBy" "ColorBy" "XAxis" "Value" "Kind" "ColorMap"])}
                text (1,1) string
            end
            ok = false;
            if isempty(self.Study), return, end
            try
                args = {char(role), text};
                self.Study.setFacets(args{:});
                ok = true;
            catch ME
                self.alert_(string(ME.message), 'Compare', 'warning');
            end
        end

        function ok = applySettings(self, s)
            % ok = applySettings(self, s)
            % Make s the analysis settings, unless it brings a problem the
            % current settings do not have (behavior.Settings.problems),
            % which is reported instead.
            arguments
                self
                s (1,1) behavior.Settings
            end
            ok = false;
            if isempty(self.Study), return, end
            p = s.problems();
            fresh = setdiff(p, self.Study.Settings.problems());
            if ~isempty(fresh)
                self.alert_("Not applied: " + strjoin(fresh, " "), 'Analysis Settings', 'warning');
                self.refreshHeader_();
                return
            end
            self.Study.setSettings(s);
            ok = true;
            if isempty(p)
                self.setStatus_("Settings " + s.hash() + ": " + s.describe());
            else
                self.setStatus_("Settings applied, with: " + strjoin(p, " "));
            end
        end

        function n = recomputeAll(self)
            % n = recomputeAll(self)
            % Forget every result and analyse every visible session again.
            n = 0;
            if isempty(self.Study), return, end
            dlg = self.progress_('Recompute All', 'Analysing sessions...');
            closeDlg = onCleanup(@() epsych.BehaviorAnalysis.closeDialog_(dlg));
            n = self.Study.recomputeAll(Progress = @(k, m) epsych.BehaviorAnalysis.progressStep_(dlg, k, m, 'Analysing session'));
            clear closeDlg
            self.refreshViews_("SettingsChanged");
            self.setStatus_(sprintf("Recomputed %d session(s).", n));
        end

        function keys = analysedKeys(self)
            % keys = analysedKeys(self)
            % The checked sessions that are not hidden: what Subject,
            % Compare, Table, exports and scripts analyse.
            keys = strings(1, 0);
            if isempty(self.Study), return, end
            keys = self.Study.Selection;
            if ~isempty(keys)
                keys = keys(~self.Study.isHidden(keys));
            end
        end

        function name = currentTab(self)
            % name = currentTab(self)
            % The tab in front: "Session", "Subject", "Compare" or "Table".
            name = string(self.H.tabs.SelectedTab.Title);
        end
    end

    % -----------------------------------------------------------------------
    methods (Static)
        function app = find()
            % app = epsych.BehaviorAnalysis.find()
            % The open window, or [] when there is none.
            app = [];
            figs = findall(groot, 'Type', 'figure', 'Tag', epsych.BehaviorAnalysis.FIGURE_TAG);
            for i = 1:numel(figs)
                u = figs(i).UserData;
                if isa(u, 'epsych.BehaviorAnalysis') && isvalid(u)
                    app = u;
                    return
                end
            end
        end

        function k = normKey(keys)
            % k = epsych.BehaviorAnalysis.normKey(keys)
            % Keys as they compare (behavior.Catalog.keyEquals's rule).
            k = replace(string(keys), "\", "/");
            if ispc
                k = lower(k);
            end
        end
    end

    methods (Static, Access = private)
        function tf = progressStep_(dlg, k, n, what)
            % Advance a progress dialog ([] when hidden); false = cancelled.
            tf = true;
            if isempty(dlg) || ~isvalid(dlg), return, end
            dlg.Value = (k - 1) / max(n, 1);
            dlg.Message = sprintf('%s %d of %d...', what, k, n);
            tf = ~dlg.CancelRequested;
        end

        function closeDialog_(dlg)
            if ~isempty(dlg) && isvalid(dlg)
                close(dlg);
            end
        end
    end

    % -----------------------------------------------------------------------
    methods (Access = private)
        buildUI(self, visible)
        buildMenus_(self)
        buildToolbar_(self)
        refreshHeader_(self)

        function tf = isOpen_(self, root)
            % Whether root is the root already open.
            tf = false;
            if isempty(self.Study) || ~isfolder(root), return, end
            here = string(java.io.File(char(root)).getCanonicalPath());
            open = string(java.io.File(char(self.Study.Root)).getCanonicalPath());
            tf = epsych.BehaviorAnalysis.normKey(here) == epsych.BehaviorAnalysis.normKey(open);
        end

        function releaseStudy_(self)
            % Views first (their listeners and graphics), then the window's own.
            names = ["Browser" self.TAB_NAMES];
            for v = names
                if isfield(self.Views, v)
                    try
                        if isvalid(self.Views.(v)), delete(self.Views.(v)); end
                    catch ME
                        vprintf(2, ME);
                    end
                end
            end
            self.Views = struct();
            try
                L = self.StudyListeners_;
                L = L(isvalid(L));
                if ~isempty(L), delete(L); end
            catch ME
                vprintf(2, ME);
            end
            self.StudyListeners_ = event.listener.empty;
            self.Study = [];
        end

        function attachStudy_(self, S)
            % Build the views over a Study and follow its events.
            self.Study = S;
            self.Views.Browser = gui.behavior.Browser(self.H.browserHost, S);
            self.Views.Session = gui.behavior.SessionView(self.H.tab.Session, S);
            self.Views.Subject = gui.behavior.SubjectView(self.H.tab.Subject, S);
            self.Views.Compare = gui.behavior.CompareView(self.H.tab.Compare, S);
            self.Views.Table = gui.behavior.TableView(self.H.tab.Table, S);
            self.Views.Fit = gui.behavior.FitView(self.H.tab.Fit, S);
            for v = ["Browser" self.TAB_NAMES]
                self.Views.(v).StatusFcn = @(t) self.setStatus_(t);
            end
            B = self.Views.Browser;
            B.OnSelect = @(nd) self.onBrowserSelect_(nd);
            B.OnOpenSession = @(key) self.openSession_(key);
            B.OnFilterChanged = @(f) self.setPref_('ShowFilter', char(f));
            self.Views.Subject.OnOpenSession = @(key) self.openSession_(key);
            self.restoreSubjectOverlay_();
            self.Views.Subject.OnOverlayChanged = @(o) self.setPref_('SubjectOverlay', o);
            self.Views.Table.OnOpenSession = @(key) self.openSession_(key);
            self.Views.Table.OnSelect = @(key) self.selectSession(key);
            self.Views.Table.OnExport = @() self.exportDialog_();
            self.Views.Fit.OnSettings = @() self.settingsDialog_(Section = "psignifit");
            filter = string(self.getPref_('ShowFilter', "All"));
            if ismember(filter, gui.behavior.Browser.SHOW)
                B.setFilter(filter);
            end
            self.activateTab_(self.currentTab());

            names = ["CatalogChanged" "ProjectChanged" "SettingsChanged" "SelectionChanged"];
            for n = names
                self.StudyListeners_(end+1) = addlistener(S, n, @(~,~) self.refreshHeader_());
            end
            self.StudyListeners_(end+1) = addlistener(S, 'Busy', @(~, evt) self.onBusy_(evt));
        end

        function activateTab_(self, name)
            % Only the tab in front redraws on every change; the others are
            % marked stale and redraw when brought forward.
            for v = ["Subject" "Compare" "Table" "Fit"]
                if isfield(self.Views, v)
                    self.Views.(v).setActive(v == name);
                end
            end
        end

        function refreshViews_(self, reason)
            for v = ["Browser" self.TAB_NAMES]
                if isfield(self.Views, v) && isvalid(self.Views.(v))
                    try
                        self.Views.(v).refresh(reason);
                    catch ME
                        vprintf(0, 1, ME);
                    end
                end
            end
        end

        % ---- browser and menus -------------------------------------------
        function onBrowserSelect_(self, nd)
            switch nd.Kind
                case "session"
                    self.selectSession(nd.Key);
                case "subject"
                    self.Views.Subject.setSubject(nd.Key);
            end
        end

        function openSession_(self, key)
            self.selectSession(key);
            self.userShowTab_("Session");
        end

        function userShowTab_(self, name)
            % A tab chosen by the operator is remembered; showTab from code is not.
            self.showTab(name);
            self.setPref_('LastTab', char(name));
        end

        function onTabChanged_(self)
            name = self.currentTab();
            self.activateTab_(name);
            self.setPref_('LastTab', char(name));
        end

        function ax = figureTarget_(self)
            % The axes Export Figure saves on the tab in front ([] = none).
            ax = [];
            if isempty(self.Study), return, end
            switch self.currentTab()
                case "Session"
                    V = self.Views.Session;
                    if V.Key ~= "", ax = V.H.stairAxes; end
                case "Subject"
                    ax = self.Views.Subject.H.timeline;
                case "Compare"
                    ax = self.Views.Compare.H.axes;
                case "Fit"
                    V = self.Views.Fit;
                    if V.Key ~= "", ax = V.H.psychAxes; end
            end
            if ~isempty(ax) && ~isgraphics(ax)
                ax = [];
            end
        end

        function name = figureName_(self)
            % A file name for the figure on the tab in front.
            name = "behavior_" + lower(self.currentTab());
            if self.currentTab() == "Session" && self.Views.Session.Key ~= ""
                [~, name] = fileparts(self.Views.Session.Key);
                name = string(name);
            elseif self.currentTab() == "Subject" && self.Views.Subject.Subject ~= ""
                name = self.Views.Subject.Subject + "_timeline";
            elseif self.currentTab() == "Fit" && self.Views.Fit.Key ~= ""
                [~, name] = fileparts(self.Views.Fit.Key);
                name = string(name) + "_fit";
            end
        end

        function key = currentKey_(self)
            % The session the Session menu acts on: the one shown.
            key = "";
            if isfield(self.Views, 'Session') && isvalid(self.Views.Session)
                key = self.Views.Session.Key;
            end
        end

        function sessionAction_(self, what)
            key = self.currentKey_();
            if key == "" || isempty(self.Study)
                self.setStatus_("Select a session in the browser first.");
                return
            end
            B = self.Views.Browser;
            switch what
                case "open"
                    self.openSession_(key);
                case "review"
                    self.review_(key);
                case "hide"
                    self.hide(key, ~self.Study.isHidden(key));
                case "window"
                    B.promptWindow(key);
                case "comment"
                    B.promptComment(key);
                case "copy"
                    B.copyPath(key);
                case "folder"
                    B.showInFolder(key);
            end
        end

        function review_(self, key)
            % Review stays available during a run: one file, chosen on purpose.
            try
                row = self.Study.Catalog.session(key);
                epsych.ReviewSession(char(row.File));
                self.setStatus_("Opened " + row.FileName + " for review.");
            catch ME
                vprintf(0, 1, ME);
                self.alert_("This session could not be opened for review: " + string(ME.message), ...
                    'Review Session', 'error');
            end
        end

        function toggleBrowser_(self)
            self.BrowserVisible_ = ~self.BrowserVisible_;
            self.setPref_('BrowserVisible', self.BrowserVisible_);
            self.layoutBody_();
        end

        function layoutBody_(self)
            w = self.getPref_('BrowserWidth', self.DEFAULT_BROWSER_WIDTH);
            if ~isnumeric(w) || ~isscalar(w) || ~(w >= 150 && w <= 1200)
                w = self.DEFAULT_BROWSER_WIDTH;
            end
            if ~self.BrowserVisible_
                w = 0;
            end
            self.H.body.ColumnWidth = {w, '1x'};
            self.H.browserHost.Visible = matlab.lang.OnOffSwitchState(self.BrowserVisible_);
            if isfield(self.H, 'mnu_browser')
                self.H.mnu_browser.Checked = matlab.lang.OnOffSwitchState(self.BrowserVisible_);
            end
        end

        function find_(self)
            if ~self.BrowserVisible_
                self.toggleBrowser_();
            end
            if isfield(self.Views, 'Browser')
                self.Views.Browser.focusSearch();
            end
        end

        % ---- header ------------------------------------------------------
        function onHeaderEdit_(self, field)
            if self.Updating_ || isempty(self.Study)
                return
            end
            s = self.Study.Settings;
            try
                switch field
                    case "Analysis"
                        v = string(self.H.ddAnalysis.Value);
                        if v ~= "Staircase"
                            self.setStatus_(v + " analysis is planned for a later version; v1 analyses staircases.");
                            self.refreshHeader_();
                            return
                        end
                        s.Analysis = v;
                    case "Parameter"
                        s.Parameter = string(self.H.ddParameter.Value);
                    case "Window"
                        w = strtrim(string(self.H.edWindow.Value));
                        if w == "", w = "all"; end
                        s.Window = w;
                    case "ExcludeTest"
                        s.ExcludeTest = self.H.chkTest.Value;
                    case "ExcludeTrialTypes"
                        s.ExcludeTrialTypes = localParseTypes(self.H.edTypes.Value);
                end
            catch ME
                self.alert_(string(ME.message), 'Analysis Settings', 'warning');
                self.refreshHeader_();
                return
            end
            self.applySettings(s);
        end

        function onPresetChosen_(self)
            if self.Updating_ || isempty(self.Study), return, end
            v = string(self.H.ddPreset.Value);
            switch v
                case "::saveas"
                    self.refreshHeader_();
                    self.savePresetAs_();
                case "::manage"
                    self.refreshHeader_();
                    self.settingsDialog_(Section = "Presets");
                case "::custom"
                    % nothing to do
                otherwise
                    self.applyPreset_(v);
            end
        end

        function applyPreset_(self, name)
            try
                s = self.Study.applyPreset(name);   % announces both changes
                self.setStatus_("Preset """ + name + """ applied: " + s.describe());
            catch ME
                self.alert_(string(ME.message), 'Presets', 'warning');
                self.refreshHeader_();
            end
        end

        function savePresetAs_(self)
            if isempty(self.Study) || ~self.isVisible_(), return, end
            a = inputdlg('Save the current settings and Compare view as:', 'Save Preset', [1 50]);
            if isempty(a) || strtrim(string(a{1})) == "", return, end
            try
                F = rmfield(self.Study.Project.Facets, 'Modified');
                self.Study.savePreset(string(a{1}), View = F);
                self.setStatus_("Saved preset """ + strtrim(string(a{1})) + """.");
            catch ME
                self.alert_(string(ME.message), 'Presets', 'warning');
            end
        end

        % ---- dialogs -----------------------------------------------------
        function settingsDialog_(self, options)
            arguments
                self
                options.Section (1,1) string = ""
            end
            if isempty(self.Study), return, end
            gui.behavior.SettingsDialog(self.Study, OnApply = @(s) self.applySettings(s), ...
                Section = options.Section, Visible = self.isVisible_());
        end

        function groupingsDialog_(self)
            if isempty(self.Study), return, end
            gui.behavior.GroupingsDialog(self.Study, Visible = self.isVisible_());
        end

        function exportDialog_(self)
            if isempty(self.Study), return, end
            gui.behavior.ExportDialog(self, Visible = self.isVisible_());
        end

        function scriptMenu_(self, scope)
            try
                file = self.writeScript("", Scope = scope);
                if file ~= ""
                    self.setStatus_("Wrote " + file);
                end
            catch ME
                vprintf(0, 1, ME);
                self.alert_(string(ME.message), 'Generate Script', 'error');
            end
        end

        function figureMenu_(self)
            try
                file = self.exportFigure("");
                if file ~= ""
                    self.setStatus_("Wrote " + file);
                end
            catch ME
                vprintf(0, 1, ME);
                self.alert_(string(ME.message), 'Export Figure', 'error');
            end
        end

        function chooseStore_(self)
            % An alternate store folder for this root, remembered per root.
            if isempty(self.Study) || ~self.isVisible_(), return, end
            d = uigetdir(char(self.getPref_('ExportFolder', pwd)), 'Choose a folder for this root''s project file');
            figure(self.H.figure);
            if isequal(d, 0), return, end
            root = self.Study.Root;
            if self.Study.Project.Dirty
                c = uiconfirm(self.H.figure, ['The project''s unsaved changes cannot be carried to ' ...
                    'the new folder; they are lost when it opens. Continue?'], 'Choose Store Folder', ...
                    'Options', {'Continue', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
                if c ~= "Continue", return, end
            end
            A = self.alternateStores_();
            A = A(~strcmp(epsych.BehaviorAnalysis.normKey([A.Root]), epsych.BehaviorAnalysis.normKey(root)));
            A(end+1) = struct('Root', root, 'Store', string(d));
            self.setPref_('AlternateStores', A);
            self.openRoot(root, Store = string(d), Force = true);
        end

        function A = alternateStores_(self)
            A = struct('Root', {}, 'Store', {});
            v = self.getPref_('AlternateStores', A);
            if isstruct(v) && ~isempty(v) && all(isfield(v, {'Root', 'Store'}))
                c = arrayfun(@(x) struct('Root', string(x.Root), 'Store', string(x.Store)), v, 'UniformOutput', false);
                A = reshape([c{:}], 1, []);
            end
        end

        function doneUpdating_(self)
            if isvalid(self)
                self.Updating_ = false;
            end
        end

        function setBar_(self, text)
            % The notification bar: shown while it has something to say that
            % the operator has not dismissed.
            text = string(text);
            self.H.barText.Text = char(text);
            self.H.barText.Tooltip = char(text);
            g = self.H.root;
            if text == "" || text == self.BarDismissed_
                g.RowHeight{2} = 0;
            else
                g.RowHeight{2} = self.BAR_HEIGHT;
            end
        end

        function dismissBar_(self)
            self.BarDismissed_ = string(self.H.barText.Text);
            g = self.H.root;
            g.RowHeight{2} = 0;
        end

        function showWarnings_(self)
            if isempty(self.Study), return, end
            W = [self.Study.Catalog.Warnings; self.Study.Project.Warnings];
            if isempty(W)
                self.setStatus_("No warnings.");
                return
            end
            self.alert_(strjoin(W, newline), 'Warnings', 'info');
        end

        % ---- recent roots, prefs -----------------------------------------
        function rememberRoot_(self, root)
            R = string(self.getPref_('RecentRoots', strings(1, 0)));
            R = reshape(R, 1, []);
            R = [root R(~strcmp(epsych.BehaviorAnalysis.normKey(R), epsych.BehaviorAnalysis.normKey(root)))];
            R = R(1:min(end, self.MAX_RECENT));
            self.setPref_('RecentRoots', R);
            self.setPref_('LastRoot', char(root));
        end

        function restoreSubjectOverlay_(self)
            % The Subject tab's overlay as the operator last left it. A
            % remembered choice this release no longer reads is dropped
            % (logged), not fatal: it is only how the overlay looks.
            o = self.getPref_('SubjectOverlay', struct());
            if ~isstruct(o) || ~isscalar(o), return, end
            V = self.Views.Subject;
            names = intersect(string(fieldnames(o)), string(fieldnames(V.Overlay)), 'stable');
            for f = reshape(names, 1, [])
                try
                    args = {char(f), o.(f)};
                    V.setOverlay(args{:});
                catch ME
                    vprintf(2, 'epsych.BehaviorAnalysis: remembered overlay %s not applied (%s)', f, ME.message)
                end
            end
        end

        function v = getPref_(self, name, default)
            % Behind ispref: getpref(group, name, default) would CREATE the pref.
            v = default;
            if ispref(self.PREF_TAG, name)
                v = getpref(self.PREF_TAG, name);
            end
        end

        function setPref_(self, name, value)
            try
                setpref(self.PREF_TAG, name, value);
            catch ME
                vprintf(2, ME);
            end
        end

        % ---- closing -----------------------------------------------------
        function onCloseRequest_(self)
            if ~self.confirmDiscard_('Close')
                return
            end
            delete(self);
        end

        function ok = confirmDiscard_(self, what)
            % Save / Discard / Cancel for an unsaved project; true = go on.
            ok = true;
            if isempty(self.Study) || ~self.Study.Project.Dirty || ~self.isVisible_()
                return
            end
            c = uiconfirm(self.H.figure, sprintf(['The project for %s has unsaved changes ' ...
                '(hidden sessions, windows, groupings, settings or the checked sessions).'], ...
                self.Study.Root), what, 'Options', {'Save', 'Discard', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
            switch c
                case 'Save'
                    ok = self.saveProject();
                case 'Discard'
                    ok = true;
                otherwise
                    ok = false;
            end
        end

        % ---- status ------------------------------------------------------
        function onBusy_(self, evt)
            if evt.Message ~= ""
                self.setStatus_(evt.Message + "...");
                if self.isVisible_()
                    drawnow limitrate
                end
            end
        end

        function setStatus_(self, text)
            text = string(text);
            if isfield(self.H, 'status') && isgraphics(self.H.status)
                self.H.status.Text = char(strtok(text, newline));
                self.H.status.Tooltip = char(text);
            end
            vprintf(3, 'BehaviorAnalysis: %s', text);
        end

        function alert_(self, message, title, icon)
            % uialert throws on a hidden figure: log instead when hidden.
            message = string(message);
            self.setStatus_(message);
            if self.isVisible_()
                uialert(self.H.figure, char(message), title, 'Icon', icon);
            else
                vprintf(1, 'BehaviorAnalysis: %s: %s', title, message);
            end
        end

        function tf = isVisible_(self)
            tf = isfield(self.H, 'figure') && isgraphics(self.H.figure) && strcmp(self.H.figure.Visible, 'on');
        end

        function dlg = progress_(self, title, message)
            dlg = [];
            if self.isVisible_()
                dlg = uiprogressdlg(self.H.figure, 'Title', title, 'Message', message, 'Cancelable', 'on');
            end
        end

        function onKeyPress_(self, evt)
            mods = string(evt.Modifier);
            switch evt.Key
                case 'f5'
                    self.rescan();
                case 'f1'
                    self.openDocumentation_();
                case 'delete'
                    self.sessionAction_("hide");
                case 'return'
                    if isempty(mods)
                        self.sessionAction_("open");
                    end
                case 'f'
                    if all(ismember(["control" "shift"], mods))
                        self.figureMenu_();
                    end
            end
        end

        function openDocumentation_(self)
            doc = fullfile(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))), ...
                'documentation', 'behavior', 'BehaviorAnalysis_UserGuide.md');
            try
                if isfile(doc)
                    open(doc);
                else
                    web(EPsychInfo().meta.WikiURL, '-browser');
                end
            catch ME
                self.alert_(string(ME.message), 'Documentation', 'warning');
            end
        end

        function openLogFolder_(self)
            try
                L = granary.Logger.instance();
                L.flush();
                epsych.SubjectRoster.openLink(fileparts(char(L.LogFile)));
            catch ME
                self.alert_(string(ME.message), 'Open Log Folder', 'warning');
            end
        end

        function refreshMenus_(self)
            % The menus whose items depend on the data: Recent Roots,
            % Presets, Parameter and the three facet menus, plus enables.
            H_ = self.H;
            delete(H_.mnu_recent.Children);
            R = reshape(string(self.getPref_('RecentRoots', strings(1, 0))), 1, []);
            for r = R
                uimenu(H_.mnu_recent, 'Text', char(r), 'MenuSelectedFcn', @(~,~) self.openRoot(r));
            end
            H_.mnu_recent.Enable = matlab.lang.OnOffSwitchState(~isempty(R));

            has = ~isempty(self.Study);
            for m = ["mnu_rescan" "mnu_save" "mnu_export" "mnu_script" "mnu_figure" ...
                    "mnu_session" "mnu_analysis" "mnu_groups"]
                H_.(m).Enable = matlab.lang.OnOffSwitchState(has);
            end
            delete(H_.mnu_presets.Children);
            delete(H_.mnu_parameter.Children);
            delete(H_.mnu_groupby.Children);
            delete(H_.mnu_colorby.Children);
            delete(H_.mnu_xaxis.Children);
            if ~has, return, end

            P = self.Study.Project;
            uimenu(H_.mnu_presets, 'Text', 'Save as...', 'MenuSelectedFcn', @(~,~) self.savePresetAs_());
            uimenu(H_.mnu_presets, 'Text', 'Manage...', ...
                'MenuSelectedFcn', @(~,~) self.settingsDialog_(Section = "Presets"));
            first = true;
            for name = reshape(string([P.Presets.Name]), 1, [])
                uimenu(H_.mnu_presets, 'Text', char(name), 'Separator', matlab.lang.OnOffSwitchState(first), ...
                    'MenuSelectedFcn', @(~,~) self.applyPreset_(name));
                first = false;
            end

            s = self.Study.Settings;
            params = ["" self.parameterNames_()];
            for p = params
                txt = p;
                if p == "", txt = "(auto)"; end
                uimenu(H_.mnu_parameter, 'Text', char(txt), 'Checked', matlab.lang.OnOffSwitchState(s.Parameter == p), ...
                    'MenuSelectedFcn', @(~,~) self.setParameter_(p));
            end

            F = behavior.Facet.available(self.Study.sessions(IncludeHidden = true), ...
                reshape(string([P.Groupings.Name]), 1, []));
            roles = ["GroupBy" "ColorBy" "XAxis"];
            menus = {H_.mnu_groupby, H_.mnu_colorby, H_.mnu_xaxis};
            for r = 1:3
                cur = string(P.Facets.(roles(r)));
                for f = F
                    t = f.toText();
                    role = roles(r);
                    uimenu(menus{r}, 'Text', char(f.label()), 'Checked', matlab.lang.OnOffSwitchState(t == cur), ...
                        'MenuSelectedFcn', @(~,~) self.setFacet(role, t));
                end
            end
        end

        function setParameter_(self, p)
            s = self.Study.Settings;
            s.Parameter = p;
            self.applySettings(s);
        end

        function names = parameterNames_(self)
            % The union of every session's candidate parameters.
            names = strings(1, 0);
            if isempty(self.Study), return, end
            C = self.Study.Catalog.Sessions;
            if height(C) == 0 || ~ismember("Candidates", string(C.Properties.VariableNames))
                return
            end
            each = cell(1, height(C));
            for k = 1:height(C)
                c = C.Candidates{k};
                if istable(c) && height(c) > 0
                    each{k} = reshape(string(c.Field), 1, []);
                end
            end
            names = unique([strings(1, 0) each{:}], 'stable');
        end
    end
end


% ---------------------------------------------------------------------------
function t = localParseTypes(txt)
txt = strtrim(string(txt));
if txt == ""
    t = zeros(1, 0);
    return
end
parts = split(txt, {',', ' ', ';'});
parts = parts(strlength(parts) > 0);
t = reshape(str2double(parts), 1, []);
if any(~isfinite(t))
    error('epsych:BehaviorAnalysis:TrialTypes', ...
        'Exclude trial types takes numbers 0-5 separated by commas ("%s" is not).', txt);
end
end
