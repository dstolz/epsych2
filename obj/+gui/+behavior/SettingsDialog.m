classdef SettingsDialog < handle
    % gui.behavior.SettingsDialog  Every analysis setting, and the presets that name them.
    %
    % Opened from epsych.BehaviorAnalysis (Analysis > Settings..., the gear
    % tool, Preset > Manage...). Every behavior.Settings property is a row;
    % the sub-structs (Staircase, Fit, Metrics, QC, Compare, NAFC) are
    % sections. What is typed is checked as it is typed: a value the
    % Settings refuse, or a combination behavior.Settings.problems reports,
    % is shown under the grid and greys OK and Apply. Nothing reaches the
    % Study until Apply or OK, which hand the settings to OnApply (the
    % window's applySettings).
    %
    % The Presets list on the right saves the CURRENT (applied) settings and
    % Compare view under a name, applies, renames and deletes presets. They
    % live in the project file (behavior.Project.Presets).
    %
    %   D = gui.behavior.SettingsDialog(study, OnApply = @(s) app.applySettings(s));
    %   s = D.collect();            % what the controls say, as Settings
    %
    % See also: behavior.Settings, behavior.Project, epsych.BehaviorAnalysis

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
            if options.Section == "Presets" && options.Visible
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
            % Re-check the controls; OK and Apply follow.
            [s, why] = obj.collect();
            if isempty(s)
                obj.setProblems_(why);
            else
                obj.setProblems_(s.problems());
            end
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
                'Position', [200 120 860 640], 'Visible', matlab.lang.OnOffSwitchState(visible));
            f.CloseRequestFcn = @(~,~) delete(obj);
            f.UserData = obj;
            obj.H.figure = f;
            g = uigridlayout(f, [3 2]);
            g.RowHeight = {'1x', 'fit', 30};
            g.ColumnWidth = {'1x', 240};
            obj.H.root = g;

            grid = uigridlayout(g, [1 2], 'Scrollable', 'on');
            grid.ColumnWidth = {220, '1x'};
            grid.RowSpacing = 4;
            grid.Layout.Row = 1;
            grid.Layout.Column = 1;
            obj.H.grid = grid;
            obj.addRows_();

            p = uigridlayout(g, [6 1]);
            p.Layout.Row = [1 2];
            p.Layout.Column = 2;
            p.RowHeight = {'fit', '1x', 26, 26, 26, 26};
            p.Padding = [0 0 0 0];
            uilabel(p, 'Text', 'Presets', 'FontWeight', 'bold');
            obj.H.presets = uilistbox(p, 'Items', {}, ...
                'Tooltip', 'Named settings and Compare views, kept in the project file');
            uibutton(p, 'Text', 'Save Current as...', 'ButtonPushedFcn', @(~,~) obj.presetAction_("save"));
            uibutton(p, 'Text', 'Apply', 'ButtonPushedFcn', @(~,~) obj.presetAction_("apply"));
            uibutton(p, 'Text', 'Rename...', 'ButtonPushedFcn', @(~,~) obj.presetAction_("rename"));
            uibutton(p, 'Text', 'Delete', 'ButtonPushedFcn', @(~,~) obj.presetAction_("delete"));

            obj.H.problems = uilabel(g, 'Text', '', 'WordWrap', 'on', 'FontColor', [0.72 0.20 0.02]);
            obj.H.problems.Layout.Row = 2;
            obj.H.problems.Layout.Column = 1;

            b = uigridlayout(g, [1 6]);
            b.Layout.Row = 3;
            b.Layout.Column = [1 2];
            b.ColumnWidth = {'1x', 'fit', 100, 100, 100, 100};
            b.Padding = [0 0 0 0];
            obj.H.status = uilabel(b, 'Text', '', 'FontColor', [0.35 0.38 0.42]);
            uibutton(b, 'Text', 'Defaults', 'Tooltip', 'Fill in the default settings (Apply to use them)', ...
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
            r = obj.header_(r, "General");
            for name = top
                r = obj.row_(r, "", name, s.(name));
            end
            for G = obj.GROUPS
                r = obj.header_(r, G);
                st = s.(G);
                for name = reshape(string(fieldnames(st)), 1, [])
                    r = obj.row_(r, G, name, st.(name));
                end
            end
        end

        function r = header_(obj, r, text)
            r = r + 1;
            h = uilabel(obj.H.grid, 'Text', char(text), 'FontWeight', 'bold');
            h.Layout.Row = r;
            h.Layout.Column = [1 2];
        end

        function r = row_(obj, r, group, name, value)
            r = r + 1;
            lbl = uilabel(obj.H.grid, 'Text', char(name));
            lbl.Layout.Row = r;
            lbl.Layout.Column = 1;
            items = obj.choices_(group, name);
            cb = @(~,~) obj.check();
            if ~isempty(items)
                c = uidropdown(obj.H.grid, 'Items', cellstr(items), 'ValueChangedFcn', cb);
                kind = "choice";
            elseif islogical(value)
                c = uicheckbox(obj.H.grid, 'Text', '', 'ValueChangedFcn', cb);
                kind = "flag";
            elseif isstring(value)
                c = uieditfield(obj.H.grid, 'text', 'ValueChangedFcn', cb);
                kind = "text";
                if name == "Parameter", c.Placeholder = '(auto: each session''s best candidate)'; end
            else
                c = uieditfield(obj.H.grid, 'text', 'ValueChangedFcn', cb, ...
                    'Placeholder', '(find it)');
                kind = "number";
            end
            c.Layout.Row = r;
            c.Layout.Column = 2;
            if group == "NAFC" || (group == "" && name == "Analysis")
                c.Tooltip = 'Detection and NAFC analyses are planned for a later version';
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
            end
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
