classdef SettingsDialog < handle
    % gui.behavior.SettingsDialog  Every analysis setting, and the presets that name them.
    %
    % Opened from epsych.BehaviorAnalysis (Analysis > Settings..., the gear
    % tool, Preset > Manage..., Analysis > psignifit Settings...). Two pages:
    %
    %   Analysis  - every behavior.Settings property as a row, the
    %               sub-structs (Staircase, Fit, Metrics, QC, Compare, NAFC)
    %               as sections
    %   psignifit - the psignifit engine: whether psignifit is installed (and
    %               where, and how to get it when it is not), a switch that
    %               makes it the fitting engine, and every Settings.Psignifit
    %               option, each explained in its tooltip
    %
    % The engine switch on the psignifit page and the Fit.Engine row on the
    % Analysis page are one setting: the row is the record, and check() keeps
    % the switch showing it.
    %
    % What is typed is checked as it is typed: a value the Settings refuse,
    % or a combination behavior.Settings.problems reports, is shown under the
    % pages and greys OK and Apply. Nothing reaches the Study until Apply or
    % OK, which hand the settings to OnApply (the window's applySettings) --
    % and through it into the project file, presets included.
    %
    % The Presets list on the right saves the CURRENT (applied) settings and
    % Compare view under a name, applies, renames and deletes presets. They
    % live in the project file (behavior.Project.Presets).
    %
    %   D = gui.behavior.SettingsDialog(study, OnApply = @(s) app.applySettings(s));
    %   D = gui.behavior.SettingsDialog(study, Section = "psignifit");
    %   s = D.collect();            % what the controls say, as Settings
    %
    % See also: behavior.Settings, behavior.fit.Psignifit, behavior.Project,
    %   epsych.BehaviorAnalysis

    properties (SetAccess = private)
        Study
        H (1,1) struct = struct()
        Problems (:,1) string = strings(0, 1)    % what the controls' settings would bring
    end

    properties
        OnApply = []      % @(settings) -> ok
    end

    properties (Constant)
        FIGURE_TAG = 'EPsychBehaviorSettings'
        GROUPS = ["Staircase" "Fit" "Metrics" "QC" "Compare" "NAFC"]
        % The psignifit page, section by section.
        PSIGNIFIT_SECTIONS = struct( ...
            'Title', {"Model", "Threshold", "Asymptotes and overdispersion", "Data and grid"}, ...
            'Fields', {["Sigmoid" "ExpType" "ExpN" "EstimateType"], ...
                       ["ThresholdPC" "CriterionScale" "ConfidenceLevel" "CIMethod" "WidthAlpha"], ...
                       ["GammaMode" "GammaValue" "LambdaMode" "LambdaValue" "EtaMode" "EtaValue" "BetaPrior"], ...
                       ["StimulusRange" "PoolTolerance" "MaxBlocks" "Grid"]})
    end

    properties (Constant, Access = private)
        OK_COLOR = [0.10 0.45 0.20]
        WARN_COLOR = [0.72 0.20 0.02]
        MUTED = [0.35 0.38 0.42]
    end

    properties (Access = private)
        Fields_ = struct('Group', {}, 'Name', {}, 'Kind', {}, 'Control', {})
        Listener_ = []
    end

    methods
        function obj = SettingsDialog(study, options)
            arguments
                study (1,1) behavior.Study
                options.OnApply = []
                options.Section (1,1) string = ""
                options.Visible (1,1) logical = true
            end
            gui.behavior.SettingsDialog.closeOpen_(obj.FIGURE_TAG);
            obj.Study = study;
            obj.OnApply = options.OnApply;
            obj.build_(options.Visible);
            obj.load_(study.Settings);
            obj.fillPresets_();
            obj.Listener_ = addlistener(study, 'ProjectChanged', @(~,~) obj.fillPresets_());
            if lower(options.Section) == "psignifit"
                obj.showPage("psignifit");
            elseif options.Section == "Presets" && options.Visible
                focus(obj.H.presets);
            end
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

        function [s, why] = collect(obj)
            % [s, why] = collect(obj)
            % The settings the controls describe; s = [] and why = the
            % reason when a value is refused.
            why = "";
            s = obj.Study.Settings;
            try
                groups = struct();
                for k = 1:numel(obj.Fields_)
                    F = obj.Fields_(k);
                    v = obj.read_(F);
                    if F.Group == ""
                        s.(F.Name) = v;
                    else
                        groups.(F.Group).(F.Name) = v;
                    end
                end
                for g = reshape(string(fieldnames(groups)), 1, [])
                    s.(g) = groups.(g);
                end
            catch ME
                s = [];
                why = string(ME.message);
            end
        end

        function c = control(obj, group, name)
            % c = control(obj, group, name)
            % The control editing one setting (group "" for the top level).
            arguments
                obj
                group (1,1) string
                name (1,1) string
            end
            k = find([obj.Fields_.Group] == group & [obj.Fields_.Name] == name, 1);
            if isempty(k)
                error('gui:behavior:SettingsDialog:UnknownSetting', 'There is no setting %s.%s.', group, name);
            end
            c = obj.Fields_(k).Control;
        end

        function ok = apply(obj)
            % ok = apply(obj)
            % Hand the settings to OnApply (when they have no problem).
            ok = false;
            [s, why] = obj.collect();
            if isempty(s)
                obj.setProblems_(why);
                return
            end
            if isempty(obj.OnApply)
                obj.Study.setSettings(s);
                ok = true;
            else
                ok = logical(obj.OnApply(s));
            end
            if ok
                obj.H.status.Text = char("Applied: settings " + s.hash());
            end
        end

        function check(obj)
            % check(obj)
            % Re-check the controls; OK and Apply follow, and so do the
            % psignifit page's engine switch and its dependent fields.
            obj.syncPsignifitPage_();
            [s, why] = obj.collect();
            if isempty(s)
                obj.setProblems_(why);
            else
                obj.setProblems_(s.problems());
            end
        end

        function showPage(obj, name)
            % showPage(obj, "Analysis" | "psignifit")
            arguments
                obj
                name (1,1) string {mustBeMember(name, ["Analysis" "psignifit"])}
            end
            if name == "psignifit"
                obj.H.tabs.SelectedTab = obj.H.tabPsignifit;
            else
                obj.H.tabs.SelectedTab = obj.H.tabAnalysis;
            end
        end

        function setPsignifitEngine(obj, tf)
            % setPsignifitEngine(obj, tf)
            % What the psignifit page's switch does: Fit.Engine becomes
            % "psignifit" (true) or "builtin" (false). Nothing is applied.
            arguments
                obj
                tf (1,1) logical
            end
            words = ["builtin" "psignifit"];
            c = obj.control("Fit", "Engine");
            c.Value = char(words(tf + 1));
            obj.check();
        end

        function L = locatePsignifit(obj, folder)
            % L = locatePsignifit(obj)          % asks for the folder
            % L = locatePsignifit(obj, folder)
            % Use the psignifit in a folder, and remember it
            % (behavior.fit.Psignifit.setFolder). A folder that holds no
            % psignifit is reported on the page; nothing changes.
            arguments
                obj
                folder (1,1) string = ""
            end
            if folder == ""
                start = behavior.fit.Psignifit.locate().Folder;
                if start == "", start = string(pwd); end
                picked = uigetdir(char(start), 'Choose the psignifit folder (the one holding psignifit.m)');
                figure(obj.H.figure);
                if isequal(picked, 0)
                    L = behavior.fit.Psignifit.locate();
                    return
                end
                folder = string(picked);
            end
            try
                L = behavior.fit.Psignifit.setFolder(folder);
                obj.H.status.Text = char("psignifit: using " + L.Folder);
            catch ME
                L = behavior.fit.Psignifit.locate();
                obj.H.status.Text = char(string(ME.message));
            end
            obj.refreshPsignifitStatus_();
            obj.check();
        end

        function L = recheckPsignifit(obj)
            % L = recheckPsignifit(obj)
            % Look for psignifit again (after installing it).
            L = behavior.fit.Psignifit.locate(Refresh = true);
            obj.refreshPsignifitStatus_();
            obj.check();
        end
    end

    methods (Static, Access = private)
        function closeOpen_(tag)
            % One dialog of a kind: close one already open (its object too).
            figs = findall(groot, 'Type', 'figure', 'Tag', tag);
            for k = 1:numel(figs)
                u = figs(k).UserData;
                if isobject(u) && isvalid(u)
                    delete(u);
                elseif isgraphics(figs(k))
                    delete(figs(k));
                end
            end
        end
    end

    methods (Access = private)
        function build_(obj, visible)
            f = uifigure('Name', 'Analysis Settings', 'Tag', obj.FIGURE_TAG, ...
                'Position', [200 100 900 680], 'Visible', matlab.lang.OnOffSwitchState(visible));
            f.CloseRequestFcn = @(~,~) delete(obj);
            f.UserData = obj;
            obj.H.figure = f;
            g = uigridlayout(f, [3 2]);
            g.RowHeight = {'1x', 'fit', 30};
            g.ColumnWidth = {'1x', 240};
            obj.H.root = g;

            tg = uitabgroup(g);
            tg.Layout.Row = 1;
            tg.Layout.Column = 1;
            obj.H.tabs = tg;
            obj.H.tabAnalysis = uitab(tg, 'Title', 'Analysis');
            obj.H.tabPsignifit = uitab(tg, 'Title', 'psignifit');

            ga = uigridlayout(obj.H.tabAnalysis, [1 1]);
            ga.Padding = [4 4 4 4];
            grid = uigridlayout(ga, [1 2], 'Scrollable', 'on');
            grid.ColumnWidth = {220, '1x'};
            grid.RowSpacing = 4;
            obj.H.grid = grid;
            obj.addRows_();

            obj.buildPsignifitPage_();

            p = uigridlayout(g, [6 1]);
            p.Layout.Row = [1 2];
            p.Layout.Column = 2;
            p.RowHeight = {'fit', '1x', 26, 26, 26, 26};
            p.Padding = [0 0 0 0];
            uilabel(p, 'Text', 'Presets', 'FontWeight', 'bold');
            obj.H.presets = uilistbox(p, 'Items', {}, ...
                'Tooltip', 'Named settings (psignifit options included) and Compare views, kept in the project file');
            uibutton(p, 'Text', 'Save Current as...', 'ButtonPushedFcn', @(~,~) obj.presetAction_("save"));
            uibutton(p, 'Text', 'Apply', 'ButtonPushedFcn', @(~,~) obj.presetAction_("apply"));
            uibutton(p, 'Text', 'Rename...', 'ButtonPushedFcn', @(~,~) obj.presetAction_("rename"));
            uibutton(p, 'Text', 'Delete', 'ButtonPushedFcn', @(~,~) obj.presetAction_("delete"));

            obj.H.problems = uilabel(g, 'Text', '', 'WordWrap', 'on', 'FontColor', obj.WARN_COLOR);
            obj.H.problems.Layout.Row = 2;
            obj.H.problems.Layout.Column = 1;

            b = uigridlayout(g, [1 6]);
            b.Layout.Row = 3;
            b.Layout.Column = [1 2];
            b.ColumnWidth = {'1x', 'fit', 100, 100, 100, 100};
            b.Padding = [0 0 0 0];
            obj.H.status = uilabel(b, 'Text', '', 'FontColor', obj.MUTED);
            uibutton(b, 'Text', 'Defaults', 'Tooltip', 'Fill in the default settings on both pages (Apply to use them)', ...
                'ButtonPushedFcn', @(~,~) obj.defaults_());
            uilabel(b, 'Text', '');
            obj.H.btnApply = uibutton(b, 'Text', 'Apply', 'ButtonPushedFcn', @(~,~) obj.apply());
            obj.H.btnOK = uibutton(b, 'Text', 'OK', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~,~) obj.ok_());
            uibutton(b, 'Text', 'Cancel', 'ButtonPushedFcn', @(~,~) delete(obj));
        end

        function addRows_(obj)
            % One row per setting, a header row per sub-struct.
            s = behavior.Settings();
            top = ["Analysis" "Parameter" "Window" "ExcludeTest" "ExcludeTrialTypes" "IncludeAborts" ...
                "StimulusTrialType" "CatchTrialType"];
            nRows = numel(top) + 1;
            for G = obj.GROUPS
                nRows = nRows + 1 + numel(fieldnames(s.(G)));
            end
            obj.H.grid.RowHeight = repmat({22}, 1, nRows);
            r = 0;
            r = obj.header_(obj.H.grid, r, "General");
            for name = top
                r = obj.row_(obj.H.grid, r, "", name, s.(name));
            end
            for G = obj.GROUPS
                r = obj.header_(obj.H.grid, r, G);
                st = s.(G);
                for name = reshape(string(fieldnames(st)), 1, [])
                    r = obj.row_(obj.H.grid, r, G, name, st.(name));
                end
            end
        end

        function buildPsignifitPage_(obj)
            pg = uigridlayout(obj.H.tabPsignifit, [3 1]);
            pg.RowHeight = {'fit', 'fit', '1x'};
            pg.Padding = [8 8 8 4];
            pg.RowSpacing = 8;

            % ---- is it installed? ------------------------------------------
            st = uipanel(pg, 'Title', 'Installation');
            sg = uigridlayout(st, [4 1]);
            sg.RowHeight = {'fit', 'fit', 'fit', 26};
            sg.Padding = [8 6 8 6];
            sg.RowSpacing = 4;
            obj.H.psStatusGrid = sg;
            obj.H.psState = uilabel(sg, 'Text', '', 'FontWeight', 'bold', 'WordWrap', 'on');
            obj.H.psDetail = uilabel(sg, 'Text', '', 'WordWrap', 'on', 'FontColor', obj.MUTED);
            obj.H.psDirections = uitextarea(sg, 'Editable', 'off', 'Value', {''}, ...
                'Tooltip', 'How to install psignifit');
            bg = uigridlayout(sg, [1 4]);
            bg.ColumnWidth = {'fit', '1x', 130, 110};
            bg.Padding = [0 0 0 0];
            obj.H.psLink = uihyperlink(bg, 'Text', 'psignifit on GitHub', ...
                'URL', char(behavior.fit.Psignifit.URL), ...
                'Tooltip', char("Download psignifit: " + behavior.fit.Psignifit.URL));
            uilabel(bg, 'Text', '');
            obj.H.psLocate = uibutton(bg, 'Text', 'Locate Folder...', ...
                'Tooltip', 'Choose the folder holding psignifit.m; it is remembered (EPsych/PsignifitPath)', ...
                'ButtonPushedFcn', @(~,~) obj.locatePsignifit());
            obj.H.psRecheck = uibutton(bg, 'Text', 'Check Again', ...
                'Tooltip', 'Look for psignifit again, after installing it', ...
                'ButtonPushedFcn', @(~,~) obj.recheckPsignifit());

            % ---- use it ----------------------------------------------------
            eg = uigridlayout(pg, [1 2]);
            eg.ColumnWidth = {'fit', '1x'};
            eg.Padding = [0 0 0 0];
            obj.H.psEngine = uicheckbox(eg, 'Text', 'Fit with psignifit', 'FontWeight', 'bold', ...
                'Tooltip', ['Make psignifit the fitting engine (Fit.Engine on the Analysis page). ' ...
                    'Off: the built-in maximum-likelihood fit.'], ...
                'ValueChangedFcn', @(src,~) obj.setPsignifitEngine(src.Value));
            obj.H.psEngineHint = uilabel(eg, 'Text', '', 'FontColor', obj.MUTED, 'WordWrap', 'on');

            % ---- the options ----------------------------------------------
            grid = uigridlayout(pg, [1 2], 'Scrollable', 'on');
            grid.ColumnWidth = {170, '1x'};
            grid.RowSpacing = 4;
            obj.H.psGrid = grid;
            sections = obj.PSIGNIFIT_SECTIONS;
            defaults = behavior.Settings().Psignifit;
            nRows = numel(sections) + numel([sections.Fields]) + 1;
            grid.RowHeight = repmat({22}, 1, nRows);
            r = 0;
            for k = 1:numel(sections)
                r = obj.header_(grid, r, sections(k).Title);
                for name = sections(k).Fields
                    r = obj.row_(grid, r, "Psignifit", name, defaults.(name));
                end
            end
            r = r + 1;
            note = uilabel(grid, 'Text', ['Staircase data are adaptive: psignifit recommends stating ' ...
                'StimulusRange as the levels the psychometric function could span.'], ...
                'FontColor', obj.MUTED, 'WordWrap', 'on');
            note.Layout.Row = r;
            note.Layout.Column = [1 2];
            grid.RowHeight{r} = 34;

            obj.refreshPsignifitStatus_();
        end

        function refreshPsignifitStatus_(obj)
            % What the Installation panel says, from behavior.fit.Psignifit.
            if ~isvalid(obj) || ~isgraphics(obj.H.psState), return, end
            L = behavior.fit.Psignifit.locate();
            if behavior.fit.Psignifit.available()
                ver = "";
                if L.Version ~= "", ver = " (commit " + L.Version + ")"; end
                obj.H.psState.Text = char("psignifit is installed" + ver + ".");
                obj.H.psState.FontColor = obj.OK_COLOR;
                obj.H.psDetail.Text = char(L.Folder + "  --  found " + L.Source + ".");
                obj.H.psDirections.Value = {''};
                obj.H.psDirections.Visible = 'off';
                g = obj.H.psStatusGrid;
                g.RowHeight{3} = 0;
            else
                obj.H.psState.Text = 'psignifit is not installed on this computer.';
                obj.H.psState.FontColor = obj.WARN_COLOR;
                looked = L.Searched;
                if isempty(looked)
                    obj.H.psDetail.Text = 'Not on the MATLAB path.';
                else
                    obj.H.psDetail.Text = char("Not on the MATLAB path; also looked in " + strjoin(looked, ", ") + ".");
                end
                obj.H.psDirections.Value = cellstr(behavior.fit.Psignifit.directions());
                obj.H.psDirections.Visible = 'on';
                g = obj.H.psStatusGrid;
                g.RowHeight{3} = 124;
            end
        end

        function syncPsignifitPage_(obj)
            % The engine switch shows Fit.Engine; options that do not apply
            % to the choices made are greyed (and still saved).
            if ~isfield(obj.H, 'psEngine') || ~isgraphics(obj.H.psEngine), return, end
            engine = string(obj.control("Fit", "Engine").Value);
            obj.H.psEngine.Value = engine == "psignifit";
            enabled = logical(obj.control("Fit", "Enabled").Value);
            if ~enabled
                obj.H.psEngineHint.Text = 'Fitting is off (Fit.Enabled on the Analysis page).';
            elseif engine == "psignifit"
                obj.H.psEngineHint.Text = 'Every session is fitted with psignifit using the options below.';
            else
                obj.H.psEngineHint.Text = 'The built-in fit is in use; these options are kept for when psignifit is chosen.';
            end

            v = @(name) string(obj.control("Psignifit", name).Value);
            expType = v("ExpType");
            on = struct( ...
                'ExpN',        expType == "nAFC", ...
                'GammaMode',   expType == "YesNo", ...
                'GammaValue',  expType == "YesNo" && v("GammaMode") == "fixed", ...
                'LambdaValue', v("LambdaMode") == "fixed", ...
                'EtaValue',    v("EtaMode") == "fixed");
            for name = reshape(string(fieldnames(on)), 1, [])
                c = obj.control("Psignifit", name);
                c.Enable = matlab.lang.OnOffSwitchState(on.(name));
            end
        end

        function r = header_(~, grid, r, text)
            r = r + 1;
            h = uilabel(grid, 'Text', char(text), 'FontWeight', 'bold');
            h.Layout.Row = r;
            h.Layout.Column = [1 2];
        end

        function r = row_(obj, grid, r, group, name, value)
            r = r + 1;
            lbl = uilabel(grid, 'Text', char(name));
            lbl.Layout.Row = r;
            lbl.Layout.Column = 1;
            items = obj.choices_(group, name);
            cb = @(~,~) obj.check();
            if ~isempty(items)
                c = uidropdown(grid, 'Items', cellstr(items), 'ValueChangedFcn', cb);
                kind = "choice";
            elseif islogical(value)
                c = uicheckbox(grid, 'Text', '', 'ValueChangedFcn', cb);
                kind = "flag";
            elseif isstring(value)
                c = uieditfield(grid, 'text', 'ValueChangedFcn', cb);
                kind = "text";
                if name == "Parameter", c.Placeholder = '(auto: each session''s best candidate)'; end
            else
                placeholder = '(find it)';
                if group == "Psignifit", placeholder = '(the levels tested)'; end
                c = uieditfield(grid, 'text', 'ValueChangedFcn', cb, 'Placeholder', placeholder);
                kind = "number";
            end
            c.Layout.Row = r;
            c.Layout.Column = 2;
            if group == "NAFC" || (group == "" && name == "Analysis")
                c.Tooltip = 'Detection and NAFC analyses are planned for a later version';
            elseif group == "Psignifit"
                tip = obj.psignifitTip_(name);
                c.Tooltip = char(tip);
                lbl.Tooltip = char(tip);
            elseif group == "Fit" && name == "Engine"
                c.Tooltip = ['builtin: maximum-likelihood fit (the options in this section). ' ...
                    'psignifit: Bayesian fit (options on the psignifit page).'];
            end
            obj.Fields_(end+1) = struct('Group', group, 'Name', name, 'Kind', kind, 'Control', c);
        end

        function items = choices_(~, group, name)
            % Text settings with a fixed set of values.
            items = strings(1, 0);
            switch group + "." + name
                case ".Analysis",                   items = ["Staircase" "Detection" "NAFC"];
                case "Staircase.Direction",         items = ["Down" "Up"];
                case "Staircase.ThresholdFormula",  items = ["Mean" "GeometricMean"];
                case "Fit.Engine",                  items = ["builtin" "psignifit"];
                case "Fit.Shape",                   items = ["Logistic" "Normal" "Weibull"];
                case "Fit.CriterionScale",          items = ["relative" "absolute"];
                case "Metrics.CorrectionMode",      items = ["none" "clamp" "halfcell" "loglinear"];
                case "Psignifit.Sigmoid",           items = behavior.Settings.PSIGNIFIT_SIGMOIDS;
                case "Psignifit.ExpType",           items = ["YesNo" "nAFC" "equalAsymptote"];
                case "Psignifit.EstimateType",      items = ["MAP" "mean"];
                case "Psignifit.CriterionScale",    items = ["relative" "absolute"];
                case "Psignifit.CIMethod",          items = ["percentiles" "stripes" "project"];
                case "Psignifit.GammaMode",         items = ["estimate" "fixed" "catch"];
                case "Psignifit.LambdaMode",        items = ["estimate" "fixed"];
                case "Psignifit.EtaMode",           items = ["estimate" "fixed"];
                case "Psignifit.Grid",              items = ["standard" "coarse"];
            end
        end

        function tip = psignifitTip_(~, name)
            % What each psignifit option does, and the psignifit option it sets.
            switch name
                case "Sigmoid"
                    tip = ['The shape of the psychometric function (sigmoidName). norm: cumulative ' ...
                        'Gaussian, psignifit''s default; logistic; gumbel and rgumbel: asymmetric; tdist: ' ...
                        'heavy-tailed; logn and weibull: fitted on a log axis, positive levels only. ' ...
                        'A staircase whose Direction is Up is fitted with the decreasing (neg_) form.'];
                case "ExpType"
                    tip = ['The experiment (expType). YesNo: guess and lapse rates both free -- detection. ' ...
                        'nAFC: the guess rate is fixed at 1/ExpN. equalAsymptote: the guess rate equals ' ...
                        'the lapse rate.'];
                case "ExpN"
                    tip = 'The number of alternatives in an nAFC experiment (expN).';
                case "EstimateType"
                    tip = ['The point estimate taken from the posterior (estimateType): MAP, the maximum ' ...
                        'a posteriori (default), or mean, the posterior mean.'];
                case "ThresholdPC"
                    tip = ['Where the threshold is read. Relative: the proportion of the way from the ' ...
                        'lower to the upper asymptote (threshPC; 0.5 is midway). Absolute: the ' ...
                        'proportion yes (or correct) itself.'];
                case "CriterionScale"
                    tip = ['relative: psignifit''s own threshold at ThresholdPC, with its credible ' ...
                        'interval. absolute: the level at which the fitted function reaches ThresholdPC ' ...
                        '(getThreshold; psignifit notes that interval is approximate).'];
                case "ConfidenceLevel"
                    tip = 'The credible interval''s level (confP). psignifit warns above 0.95.';
                case "CIMethod"
                    tip = ['How credible intervals are found (CImethod): percentiles (default), stripes, ' ...
                        'or project.'];
                case "WidthAlpha"
                    tip = ['The width is the span from WidthAlpha to 1 - WidthAlpha of the unscaled ' ...
                        'function (widthalpha; default 0.05).'];
                case "GammaMode"
                    tip = ['The guess rate (lower asymptote, gamma) of a YesNo fit: estimate it, fix it ' ...
                        'at GammaValue, or fix it at the session''s false-alarm rate on catch trials ' ...
                        '(estimated instead when a session has none).'];
                case "GammaValue"
                    tip = 'The guess rate, when GammaMode is fixed.';
                case "LambdaMode"
                    tip = 'The lapse rate (one minus the upper asymptote, lambda): estimate it, or fix it at LambdaValue.';
                case "LambdaValue"
                    tip = 'The lapse rate, when LambdaMode is fixed.';
                case "EtaMode"
                    tip = ['Overdispersion (eta), the extra trial-to-trial variance psignifit''s ' ...
                        'beta-binomial model allows: estimate it, or fix it at EtaValue (0 is a binomial observer).'];
                case "EtaValue"
                    tip = 'Overdispersion, when EtaMode is fixed.';
                case "BetaPrior"
                    tip = ['How strongly the prior favours a binomial observer (betaPrior; default 10). ' ...
                        'Larger allows less overdispersion.'];
                case "StimulusRange"
                    tip = ['Two levels bracketing where the psychometric function could lie ' ...
                        '(stimulusRange), e.g. "0 60". Empty: the levels tested. A staircase samples ' ...
                        'adaptively, and psignifit recommends stating this so its priors cover the whole function.'];
                case "PoolTolerance"
                    tip = 'Merge levels at most this far apart before fitting (poolxTol; in the parameter''s units).';
                case "MaxBlocks"
                    tip = 'psignifit pools the data when there are more levels than this (nblocks; default 25).';
                case "Grid"
                    tip = ['The posterior grid. standard: psignifit''s default (seconds per session). ' ...
                        'coarse: about half the points per parameter -- roughly ten times faster, for ' ...
                        'nearly the same estimates.'];
                otherwise
                    tip = '';
            end
            tip = string(tip);
        end

        function load_(obj, s)
            for k = 1:numel(obj.Fields_)
                F = obj.Fields_(k);
                if F.Group == ""
                    v = s.(F.Name);
                else
                    v = s.(F.Group).(F.Name);
                end
                switch F.Kind
                    case "choice"
                        F.Control.Value = char(v);
                    case "flag"
                        F.Control.Value = logical(v);
                    case "text"
                        F.Control.Value = char(v);
                    case "number"
                        F.Control.Value = char(strjoin(compose("%.10g", reshape(double(v), 1, [])), " "));
                end
            end
            obj.check();
        end

        function v = read_(~, F)
            switch F.Kind
                case {"choice" "text"}
                    v = string(F.Control.Value);
                case "flag"
                    v = logical(F.Control.Value);
                case "number"
                    t = strtrim(string(F.Control.Value));
                    if t == ""
                        v = [];       % "find it" in a group; no trial types at the top
                    else
                        parts = split(t, {',', ' ', ';'});
                        parts = parts(strlength(parts) > 0);
                        v = reshape(str2double(parts), 1, []);
                        if any(isnan(v))
                            error('gui:behavior:SettingsDialog:NotANumber', ...
                                '%s: "%s" is not a number.', F.Name, t);
                        end
                    end
            end
        end

        function setProblems_(obj, p)
            p = reshape(string(p), [], 1);
            obj.Problems = p;
            if isempty(p)
                obj.H.problems.Text = '';
            else
                obj.H.problems.Text = char(strjoin(p, newline));
            end
            ok = matlab.lang.OnOffSwitchState(isempty(p));
            obj.H.btnApply.Enable = ok;
            obj.H.btnOK.Enable = ok;
        end

        function ok_(obj)
            if obj.apply()
                delete(obj);
            end
        end

        function defaults_(obj)
            obj.load_(behavior.Settings());
            obj.H.status.Text = 'Defaults filled in; Apply to use them.';
        end

        % ---- presets ---------------------------------------------------------
        function fillPresets_(obj)
            if ~isvalid(obj) || ~isgraphics(obj.H.presets), return, end
            names = reshape(string([obj.Study.Project.Presets.Name]), 1, []);
            obj.H.presets.Items = cellstr(names);
        end

        function presetAction_(obj, what)
            P = obj.Study.Project;
            name = string(obj.H.presets.Value);
            if what ~= "save" && (isempty(obj.H.presets.Items) || name == "")
                obj.H.status.Text = 'Choose a preset first.';
                return
            end
            try
                switch what
                    case "save"
                        a = inputdlg('Save the applied settings and Compare view as:', 'Save Preset', [1 50]);
                        if isempty(a) || strtrim(string(a{1})) == "", return, end
                        obj.Study.savePreset(string(a{1}), View = rmfield(P.Facets, 'Modified'));
                        obj.H.status.Text = char("Saved preset " + strtrim(string(a{1})));
                    case "apply"
                        s = obj.Study.applyPreset(name);
                        obj.load_(s);
                        obj.H.status.Text = char("Applied preset " + name);
                        return     % applyPreset announced it
                    case "rename"
                        a = inputdlg('New name:', 'Rename Preset', [1 50], {char(name)});
                        if isempty(a), return, end
                        obj.Study.renamePreset(name, string(a{1}));
                    case "delete"
                        obj.Study.deletePreset(name);
                end
            catch ME
                obj.H.status.Text = char(string(ME.message));
            end
        end
    end
end
