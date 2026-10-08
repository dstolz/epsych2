classdef FitView < gui.behavior.View
    % gui.behavior.FitView  One session's psychometric fit, drawn by psignifit where it can be.
    %
    % The Fit tab of epsych.BehaviorAnalysis. It follows the session shown on
    % the Session tab and shows what the fit made of it, larger and in more
    % detail than the Session tab's panel has room for:
    %
    %   - the psychometric function: psignifit's own plotPsych for a psignifit
    %     fit (data, function, asymptotes, threshold and its credible
    %     interval), behavior.Plot.psychometric for the built-in one
    %   - every parameter with its estimate and interval, the slope at the
    %     threshold, the deviance, where the guess rate came from, and every
    %     warning psignifit raised
    %   - psignifit's marginal posteriors (plotMarginal) for threshold, width,
    %     lapse, guess and overdispersion, and a joint posterior of any two
    %     (plot2D)
    %   - psignifit's whole-figure plots in windows of their own: every pair
    %     (plotBayes), the priors (plotPrior), the model checks (plotsModelfit)
    %
    % It computes nothing: the fit is behavior.Study.result's, so the number
    % here is the Table tab's and the generated script's. The joint posterior
    % needs psignifit's whole grid, which the stored fit does not keep
    % (behavior.fit.Psignifit.posterior refits it: seconds on the standard
    % grid), so it is drawn only while "Joint posterior" is ticked.
    %
    % Like the Subject, Compare and Table tabs it redraws only while in
    % front, and marks itself stale otherwise; it redraws only when the
    % session, the settings or the window it was drawn for changed.
    %
    %   V = gui.behavior.FitView(container, study);
    %   V.show(key);
    %
    % See also: gui.behavior.View, gui.behavior.SessionView,
    %   behavior.fit.PsignifitPlot, behavior.fit.Psignifit

    properties (SetAccess = private)
        Key (1,1) string = ""
        Result = []        % the behavior.Session.analyze result shown
        Active (1,1) logical = true
    end

    properties
        OnSettings = []    % @() open Analysis Settings on the psignifit page
    end

    properties (Access = private)
        Stale_ (1,1) logical = false
        Signature_ (1,1) string = ""
    end

    properties (Constant, Access = private)
        MUTED (1,3) double = [0.35 0.38 0.42]
        WARN  (1,3) double = [0.72 0.42 0.02]
        PANEL_WIDTH = 400
        POSTERIOR_HEIGHT = 230
    end

    methods
        function obj = FitView(parent, study)
            obj@gui.behavior.View(parent, study);
        end

        function build(obj)
            g = uigridlayout(obj.Parent, [2 2]);
            g.ColumnWidth = {'1x', obj.PANEL_WIDTH};
            g.RowHeight = {'1x', obj.POSTERIOR_HEIGHT};
            g.Padding = [4 4 4 4];
            g.ColumnSpacing = 8;
            obj.H.root = g;

            obj.H.psychAxes = uiaxes(g);
            obj.H.psychAxes.Layout.Row = 1;
            obj.H.psychAxes.Layout.Column = 1;

            r = uigridlayout(g, [6 1]);
            r.Layout.Row = 1;
            r.Layout.Column = 2;
            r.RowHeight = {'fit', 'fit', '1x', 110, 'fit', 'fit'};
            r.Padding = [0 0 0 0];
            r.RowSpacing = 6;
            obj.H.panel = r;
            obj.H.title = uilabel(r, 'Text', 'No session', 'FontWeight', 'bold', 'FontSize', 13, 'WordWrap', 'on');
            obj.H.engine = uilabel(r, 'Text', '', 'FontColor', obj.MUTED, 'WordWrap', 'on');
            obj.H.table = uitable(r, 'ColumnName', {'Parameter', 'Estimate', 'Low', 'High'}, ...
                'ColumnWidth', {150, 'auto', 'auto', 'auto'}, 'RowName', {}, 'RowStriping', 'on', ...
                'Tooltip', 'Low and High bound the credible (psignifit) or confidence (built-in) interval');
            obj.H.notes = uitextarea(r, 'Editable', 'off', 'Value', {''}, ...
                'Tooltip', 'Why a fit is missing or doubtful, and every warning psignifit raised');

            b = uigridlayout(r, [2 2]);
            b.RowHeight = {26, 26};
            b.Padding = [0 0 0 0];
            b.RowSpacing = 4;
            obj.H.btnBayes = uibutton(b, 'Text', 'All Pairs (plotBayes)...', ...
                'Tooltip', 'psignifit''s joint posterior of every pair of parameters, in its own window (refits the grid)', ...
                'ButtonPushedFcn', @(~,~) obj.openWindow("bayes"));
            obj.H.btnPriors = uibutton(b, 'Text', 'Priors (plotPrior)...', ...
                'Tooltip', 'psignifit''s priors and the functions they allow, in their own window', ...
                'ButtonPushedFcn', @(~,~) obj.openWindow("priors"));
            obj.H.btnChecks = uibutton(b, 'Text', 'Model Checks...', ...
                'Tooltip', 'psignifit''s plotsModelfit: the fit, deviance residuals by level and by block, and the deviance', ...
                'ButtonPushedFcn', @(~,~) obj.openWindow("checks"));
            obj.H.btnSettings = uibutton(b, 'Text', 'psignifit Settings...', ...
                'Tooltip', 'The psignifit page of Analysis Settings: installation, engine and options', ...
                'ButtonPushedFcn', @(~,~) obj.openSettings_());
            obj.H.hint = uilabel(r, 'Text', '', 'FontColor', obj.MUTED, 'WordWrap', 'on');

            % ---- posteriors --------------------------------------------------
            p = uigridlayout(g, [2 6]);
            p.Layout.Row = 2;
            p.Layout.Column = [1 2];
            p.RowHeight = {24, '1x'};
            p.ColumnWidth = repmat({'1x'}, 1, 6);
            p.Padding = [0 0 0 0];
            p.ColumnSpacing = 4;
            p.RowSpacing = 2;
            obj.H.posterior = p;
            lbl = uilabel(p, 'Text', 'Marginal posteriors (plotMarginal): the shaded band is the credible interval, the dashed line the prior', ...
                'FontColor', obj.MUTED);
            lbl.Layout.Row = 1;
            lbl.Layout.Column = [1 4];
            obj.H.marginalLabel = lbl;
            c = uigridlayout(p, [1 4]);
            c.Layout.Row = 1;
            c.Layout.Column = [5 6];
            c.ColumnWidth = {'fit', '1x', 'fit', '1x'};
            c.Padding = [0 0 0 0];
            c.ColumnSpacing = 4;
            names = cellstr(behavior.fit.Psignifit.PARAMETERS);
            obj.H.chkPair = uicheckbox(c, 'Text', 'Joint posterior', 'Value', false, ...
                'Tooltip', 'Draw psignifit''s plot2D of the two parameters chosen (refits the grid: seconds per session)', ...
                'ValueChangedFcn', @(~,~) obj.drawPair_());
            obj.H.ddPairY = uidropdown(c, 'Items', names, 'Value', 'threshold', ...
                'Tooltip', 'Parameter on the y axis', 'ValueChangedFcn', @(~,~) obj.drawPair_());
            uilabel(c, 'Text', 'vs');
            obj.H.ddPairX = uidropdown(c, 'Items', names, 'Value', 'width', ...
                'Tooltip', 'Parameter on the x axis', 'ValueChangedFcn', @(~,~) obj.drawPair_());
            obj.H.marginalAxes = gobjects(1, 5);
            for k = 1:5
                ax = uiaxes(p);
                ax.Layout.Row = 2;
                ax.Layout.Column = k;
                obj.H.marginalAxes(k) = ax;
            end
            obj.H.pairAxes = uiaxes(p);
            obj.H.pairAxes.Layout.Row = 2;
            obj.H.pairAxes.Layout.Column = 6;
            obj.clear_();
        end

        function setActive(obj, tf)
            obj.Active = tf;
            if tf && obj.Stale_
                obj.refresh("show");
            end
        end

        function show(obj, key)
            % show(obj, key)
            % Follow one session ("" clears the tab).
            arguments
                obj
                key (1,1) string = ""
            end
            if key ~= obj.Key
                obj.Signature_ = "";
            end
            obj.Key = key;
            obj.refresh("show");
        end

        function refresh(obj, reason)
            % refresh(obj, reason)
            % Redraw for a Study event, or for "show".
            arguments
                obj
                reason (1,1) string = "show"
            end
            if ~isvalid(obj) || ~isfield(obj.H, 'root') || ~isgraphics(obj.H.root)
                return
            end
            if any(reason == ["SelectionChanged" "ResultsChanged"])
                return
            end
            if ~obj.Active
                obj.Stale_ = true;
                return
            end
            obj.Stale_ = false;
            if obj.Key == ""
                obj.clear_();
                return
            end
            try
                row = obj.Study.Catalog.session(obj.Key);
            catch
                obj.Key = "";
                obj.clear_();
                return
            end
            try
                R = obj.Study.result(obj.Key);
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus("Could not analyse " + obj.Key + ": " + string(ME.message));
                return
            end
            sig = obj.Key + "|" + string(R.SettingsHash) + "|" + string(R.Window);
            if sig == obj.Signature_
                return     % a comment or a grouping elsewhere changed nothing here
            end
            obj.Result = R;
            obj.Signature_ = sig;
            obj.draw_(row, R);
        end

        function figs = openWindow(obj, which)
            % figs = openWindow(obj, "bayes" | "priors" | "checks")
            % One of psignifit's whole-figure plots of the shown fit, in its
            % own window.
            arguments
                obj
                which (1,1) string {mustBeMember(which, ["bayes" "priors" "checks"])}
            end
            figs = gobjects(0);
            F = obj.fit_();
            if isempty(F), return, end
            try
                switch which
                    case "bayes"
                        obj.setStatus("Refitting the posterior grid for plotBayes...");
                        drawnow
                        figs = behavior.fit.PsignifitPlot.bayes(F);
                    case "priors"
                        figs = behavior.fit.PsignifitPlot.priors(F);
                    case "checks"
                        figs = behavior.fit.PsignifitPlot.modelChecks(F);
                end
                obj.setStatus(sprintf("psignifit opened %d window(s).", numel(figs)));
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus("psignifit: " + string(ME.message));
            end
        end
    end

    methods (Access = private)
        function draw_(obj, row, R)
            F = R.Fit;
            isPs = obj.isPsignifit_(F);
            obj.H.title.Text = char(obj.titleText_(row, R));
            obj.H.engine.Text = char(obj.engineText_(F));

            if isPs
                behavior.fit.PsignifitPlot.psych(obj.H.psychAxes, F, Unit = R.Unit, Parameter = R.Parameter);
            else
                try
                    behavior.Plot.psychometric(obj.H.psychAxes, F, Unit = R.Unit);
                catch ME
                    vprintf(2, 'gui.behavior.FitView: fit plot not drawn: %s', ME.message);
                    cla(obj.H.psychAxes, 'reset');
                end
                title(obj.H.psychAxes, 'Psychometric function (built-in fit)', 'FontWeight', 'normal');
            end

            obj.H.table.Data = obj.parameterRows_(F);
            notes = strings(0, 1);
            if strlength(string(F.Message)) > 0
                notes(end+1) = string(F.Message);
            end
            W = reshape(string(F.Warnings), [], 1);
            if ~isempty(W)
                notes = [notes; "psignifit warned:"; "- " + W];
            end
            if isempty(notes), notes = ""; end
            obj.H.notes.Value = cellstr(notes);

            hasRaw = isPs && isfield(F.Raw, 'Fit');
            on = matlab.lang.OnOffSwitchState(hasRaw);
            obj.H.btnBayes.Enable = on;
            obj.H.btnPriors.Enable = on;
            obj.H.btnChecks.Enable = on;
            obj.H.chkPair.Enable = on;
            obj.H.ddPairX.Enable = on;
            obj.H.ddPairY.Enable = on;

            if hasRaw
                obj.H.root.RowHeight{2} = obj.POSTERIOR_HEIGHT;
                obj.H.hint.Text = '';
                for k = 1:5
                    try
                        behavior.fit.PsignifitPlot.marginal(obj.H.marginalAxes(k), F, k, Unit = R.Unit);
                    catch ME
                        vprintf(2, 'gui.behavior.FitView: marginal %d not drawn: %s', k, ME.message);
                    end
                end
                obj.drawPair_();
            else
                obj.H.root.RowHeight{2} = 0;
                if isPs
                    obj.H.hint.Text = 'psignifit made no fit of this session; the reason is above.';
                elseif R.Fit.Engine == "builtin" && obj.Study.Settings.Fit.Enabled
                    obj.H.hint.Text = ['Posterior distributions, priors and model checks come from psignifit: ' ...
                        'tick "Fit with psignifit" in psignifit Settings....'];
                else
                    obj.H.hint.Text = '';
                end
            end
        end

        function drawPair_(obj)
            ax = obj.H.pairAxes;
            F = obj.fit_();
            if isempty(F) || ~obj.isPsignifit_(F) || ~isfield(F.Raw, 'Fit')
                return
            end
            if ~obj.H.chkPair.Value
                cla(ax, 'reset');
                text(ax, 0.5, 0.5, {'Tick "Joint posterior"', 'to draw plot2D', '(refits the grid)'}, ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center', 'Color', obj.MUTED, ...
                    'Tag', 'FitView:PairHint');
                ax.XTick = [];
                ax.YTick = [];
                return
            end
            obj.setStatus("Refitting the posterior grid for the joint posterior...");
            drawnow
            try
                behavior.fit.PsignifitPlot.pair(ax, F, string(obj.H.ddPairY.Value), string(obj.H.ddPairX.Value));
                obj.setStatus("Joint posterior (plot2D): " + obj.H.ddPairY.Value + " against " + obj.H.ddPairX.Value + ".");
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus("Joint posterior: " + string(ME.message));
            end
        end

        function F = fit_(obj)
            F = [];
            if ~isempty(obj.Result) && isfield(obj.Result, 'Fit')
                F = obj.Result.Fit;
            end
        end

        function tf = isPsignifit_(~, F)
            tf = isstruct(F) && ~isempty(F) && string(F.Engine) == "psignifit" ...
                && isstruct(F.Raw) && isfield(F.Raw, 'Fit');
        end

        function D = parameterRows_(obj, F)
            % Name, estimate, interval: one row per parameter.
            n = @(x) obj.num_(x);
            if obj.isPsignifit_(F)
                res = F.Raw;
                ci = res.conf_Intervals(:, :, 1);
                lin = @(x) x;
                if res.options.logspace, lin = @exp; end
                names = ["Threshold (psignifit)" "Width" "Lapse rate (lambda)" "Guess rate (gamma)" "Overdispersion (eta)"];
                D = cell(5, 4);
                for k = 1:5
                    est = res.Fit(k);
                    lo = ci(k, 1);
                    hi = ci(k, 2);
                    if k == 1
                        est = lin(est); lo = lin(lo); hi = lin(hi);
                    end
                    name = names(k);
                    if numel(res.marginals{k}) <= 1
                        name = name + " (fixed)";
                        lo = NaN; hi = NaN;
                    end
                    D(k, :) = {char(name), n(est), n(lo), n(hi)};
                end
                if string(res.CriterionScale) == "absolute"
                    D(end+1, :) = {sprintf('Threshold at p = %g', res.Criterion), n(F.Threshold), ...
                        n(F.CI.ThresholdLo), n(F.CI.ThresholdHi)};
                end
                D(end+1, :) = {'Slope at threshold', n(F.Beta), '', ''};
                D(end+1, :) = {'Deviance', n(F.Deviance), '', ''};
                D(end+1, :) = {'Guess rate from', char(string(res.GammaSource)), '', ''};
            else
                D = { ...
                    'Threshold', n(F.Threshold), n(F.CI.ThresholdLo), n(F.CI.ThresholdHi); ...
                    'Alpha (location)', n(F.Alpha), '', ''; ...
                    'Beta (slope)', n(F.Beta), '', ''; ...
                    'Guess rate (gamma)', n(F.Gamma), '', ''; ...
                    'Lapse rate (lambda)', n(F.Lambda), '', ''; ...
                    'Deviance', n(F.Deviance), '', ''};
            end
            D(end+1, :) = {'Levels / trials', sprintf('%d / %d', numel(F.Levels), sum(F.NumTotal)), '', ''};
        end

        function t = titleText_(~, row, R)
            when = "";
            if isdatetime(R.Start) && ~isnat(R.Start)
                when = string(R.Start, 'yyyy-MM-dd HH:mm');
            end
            parts = [R.Subject, when, strjoin(R.Tags, " ")];
            parts = parts(strlength(parts) > 0);
            t = strjoin(parts, "  ·  ");
            if t == "", t = string(row.FileName); end
        end

        function t = engineText_(obj, F)
            s = obj.Study.Settings;
            if ~s.Fit.Enabled
                t = "Fitting is off (Analysis Settings > Fit.Enabled).";
            elseif string(F.Engine) == "psignifit"
                P = s.Psignifit;
                t = sprintf("psignifit: %s sigmoid, %s, %s estimate, threshold at %g (%s), %s grid", ...
                    string(F.Shape), P.ExpType, P.EstimateType, P.ThresholdPC, P.CriterionScale, P.Grid);
                L = behavior.fit.Psignifit.locate();
                if L.Version ~= "", t = t + ", commit " + L.Version; end
                t = t + ".";
            else
                t = sprintf("Built-in maximum-likelihood fit: %s, threshold at %g (%s).", ...
                    s.Fit.Shape, s.Fit.ThresholdCriterion, s.Fit.CriterionScale);
            end
        end

        function openSettings_(obj)
            if isempty(obj.OnSettings)
                gui.behavior.SettingsDialog(obj.Study, Section = "psignifit");
            else
                obj.OnSettings();
            end
        end

        function clear_(obj)
            obj.Result = [];
            obj.Signature_ = "";
            obj.H.title.Text = 'No session';
            obj.H.engine.Text = '';
            cla(obj.H.psychAxes, 'reset');
            obj.H.table.Data = cell(0, 4);
            obj.H.notes.Value = {''};
            for ax = [obj.H.marginalAxes obj.H.pairAxes]
                cla(ax, 'reset');
            end
            for h = [obj.H.btnBayes obj.H.btnPriors obj.H.btnChecks]
                h.Enable = 'off';
            end
            obj.H.hint.Text = 'Select a session in the browser to see its fit.';
        end
    end

    methods (Static, Access = private)
        function s = num_(x)
            if isempty(x) || ~isnumeric(x) || ~isfinite(x)
                s = '';
            else
                s = sprintf('%.4g', x);
            end
        end
    end
end
