classdef SessionView < gui.behavior.View
    % gui.behavior.SessionView  One session: its staircase, its numbers, its fit, its notes.
    %
    % The Session tab of epsych.BehaviorAnalysis. The left side is the
    % session's psychophysics.Staircase drawn by the staircase itself
    % (Staircase.Plot), the right side what the analysis made of it: the
    % trial window in force (editable here, as a per-session override), the
    % reversal and fitted thresholds, the session metrics, the psychometric
    % function, QC flags and messages, and the operator's notes.
    %
    %   V = gui.behavior.SessionView(container, study);
    %   V.show(key);
    %
    % HOW THE STAIRCASE IS HOSTED. The axes sits ALONE in a 1x1 uigridlayout,
    % because the staircase's "Show Reversal Distribution" wraps its axes'
    % grid cell in a grid of its own and hands it back when switched off --
    % anything sharing that grid would be reflowed. The staircase object is
    % built by behavior.Session.staircase from the Study's Settings and the
    % session's window, so it IS the analysis the numbers came from; it is
    % owned here, and replaced (disablePlot, delete) whenever the session,
    % the settings or the window change.
    %
    % THE RIGHT-CLICK MENU IS ONE MORE EDITOR OF THE SETTINGS. The plot's
    % menu changes the staircase's ThresholdFromLastNReversals,
    % ThresholdFormula and ApplyWeightedCorrection, which recompute on their
    % own (they are SetObservable). This view listens to those three and
    % writes a change into behavior.Study.setSettings, so the Table, Subject
    % and Compare tabs follow -- the alternative, a plot whose threshold
    % disagrees with the table beside it, is exactly what an analysis tool
    % must not do. An offline staircase never restores remembered menu
    % choices over the caller's settings (psychophysics.Staircase, 2026-10-07),
    % so the Settings always win on a fresh show; the display-only choices
    % (steps, reversals, distribution) remain the operator's and persist
    % through the staircase's own preference.
    %
    % OPENING A PLOT ON ITS OWN. The psychometric fit has "Open in New
    % Figure" (gui.behavior.View.openInFigure, key "fit"). The staircase
    % has its own "Open in Separate Window" (gui.PopOut): a second
    % psychophysics.Staircase over the same trials, which keeps its menus
    % and its reversal distribution -- what a redraw into an ordinary
    % figure could not. plots() lists it as key "staircase", and
    % openInFigure("staircase") opens that window.
    %
    % See also: gui.behavior.View, behavior.Study, behavior.Session.staircase,
    %   psychophysics.Staircase, behavior.Plot

    properties (SetAccess = private)
        Key (1,1) string = ""
        Staircase = []     % the psychophysics.Staircase drawn, owned here
        Result = []        % the behavior.Session.analyze result shown
    end

    properties (Access = private)
        StairListeners_ = event.listener.empty
        StairSignature_ (1,1) string = ""         % key|settings hash|window the staircase was built for
        Mirroring_ (1,1) logical = false           % onStaircaseSetting_ is running
        SummaryLines_ (1,:) string = strings(1, 0)
    end

    properties (Constant, Access = private)
        MUTED (1,3) double = [0.35 0.38 0.42]
        WARN  (1,3) double = [0.72 0.42 0.02]
        PANEL_WIDTH = 380
    end

    methods
        function obj = SessionView(parent, study)
            obj@gui.behavior.View(parent, study);
        end

        function delete(obj)
            obj.releaseStaircase_();
            delete@gui.behavior.View(obj);
        end

        function build(obj)
            g = uigridlayout(obj.Parent, [1 2]);
            g.ColumnWidth = {'1x', obj.PANEL_WIDTH};
            g.Padding = [4 4 4 4];
            g.ColumnSpacing = 8;
            obj.H.root = g;

            % The staircase, alone in its grid (see the class comment).
            obj.H.stairGrid = uigridlayout(g, [1 1]);
            obj.H.stairGrid.Padding = [0 0 0 0];
            obj.H.stairAxes = uiaxes(obj.H.stairGrid);

            r = uigridlayout(g, [8 1]);
            r.RowHeight = {'fit', 'fit', 150, 170, '1x', 'fit', 110, 'fit'};
            r.Padding = [0 0 0 0];
            r.RowSpacing = 6;
            obj.H.panel = r;

            obj.H.title = uilabel(r, 'Text', 'No session', 'FontWeight', 'bold', ...
                'FontSize', 13, 'WordWrap', 'on');

            w = uigridlayout(r, [1 3]);
            w.ColumnWidth = {'fit', '1x', 'fit'};
            w.Padding = [0 0 0 0];
            uilabel(w, 'Text', 'Trial window');
            obj.H.window = uieditfield(w, 'text', 'Placeholder', 'settings', ...
                'Tooltip', ['This session''s trials: "all", "last 100", "3-83", "20+". Empty uses ' ...
                    'the analysis settings. Kept in the project file.'], ...
                'ValueChangedFcn', @(~,~) obj.onWindowEdited_());
            obj.H.windowHint = uilabel(w, 'Text', '', 'FontColor', obj.MUTED);

            obj.H.summary = uitextarea(r, 'Editable', 'off', 'Value', {''}, ...
                'Tooltip', 'What the analysis made of this session. Copy Values puts it on the clipboard.');
            obj.H.metrics = uitable(r, 'ColumnName', {'Metric', 'Value', 'Detail'}, ...
                'ColumnWidth', {120, 80, '1x'}, 'RowName', {}, 'RowStriping', 'on');
            obj.H.fitAxes = uiaxes(r);
            obj.H.flags = uilabel(r, 'Text', '', 'WordWrap', 'on', 'FontColor', obj.MUTED);
            obj.H.notes = uitextarea(r, 'Editable', 'off', 'Value', {''}, ...
                'Placeholder', 'No notes were recorded in this session');

            b = uigridlayout(r, [1 3]);
            b.ColumnWidth = {'1x', 'fit', 'fit'};
            b.Padding = [0 0 0 0];
            uilabel(b, 'Text', '');
            obj.H.btnCopy = uibutton(b, 'Text', 'Copy Values', ...
                'Tooltip', 'Copy the summary above as text', ...
                'ButtonPushedFcn', @(~,~) obj.copyValues());
            obj.H.btnReview = uibutton(b, 'Text', 'Review Session...', ...
                'Tooltip', 'Open this session in its behavior GUI (epsych.ReviewSession)', ...
                'ButtonPushedFcn', @(~,~) obj.review());
            obj.clear_();
        end

        function show(obj, key)
            % show(obj, key)
            % Display one session ("" clears the tab).
            arguments
                obj
                key (1,1) string = ""
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
                return     % nothing of this tab's changes with those
            end
            if obj.Key == ""
                obj.clear_();
                return
            end
            try
                row = obj.Study.Catalog.session(obj.Key);
            catch
                obj.Key = "";      % the session left the catalog
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
            obj.Result = R;

            % Rebuild the staircase only when what it was built from changed:
            % the session, the settings or the window. A ProjectChanged for a
            % comment elsewhere, or a settings change this view itself wrote
            % back from the plot menu, leaves the drawn staircase as it is.
            if isempty(obj.Staircase) || ~isvalid(obj.Staircase) || obj.signature_(R) ~= obj.StairSignature_
                obj.drawStaircase_(R);
            end
            obj.fillPanel_(row, R);
        end

        function copyValues(obj)
            % copyValues(obj)
            % Put the summary lines on the clipboard, for a notebook entry.
            if isempty(obj.SummaryLines_)
                obj.setStatus("Nothing to copy: no session is shown.");
                return
            end
            try
                clipboard('copy', char(strjoin(obj.SummaryLines_, newline)));
                obj.setStatus("Copied " + numel(obj.SummaryLines_) + " lines to the clipboard.");
            catch ME
                obj.setStatus("The clipboard is not available here: " + string(ME.message));
            end
        end

        function L = plots(obj)
            % L = plots(obj)
            % What can be opened on its own: the staircase (in its own
            % pop-out window) and the fit. See gui.behavior.View.plots.
            L = plots@gui.behavior.View(obj);
            if ~isempty(obj.Staircase) && isvalid(obj.Staircase)
                L = [struct('Key', "staircase", 'Name', obj.label_(obj.Result) + " · Staircase") L];
            end
        end

        function fig = openInFigure(obj, key, options)
            % fig = openInFigure(obj, key, Visible = true)
            % As gui.behavior.View.openInFigure; "staircase" opens the
            % staircase's own pop-out window (always shown) instead.
            arguments
                obj
                key (1,1) string
                options.Visible (1,1) logical = true
            end
            if key ~= "staircase"
                fig = openInFigure@gui.behavior.View(obj, key, Visible = options.Visible);
                return
            end
            fig = gobjects(0);
            S = obj.Staircase;
            if isempty(S) || ~isvalid(S)
                obj.setStatus("No staircase is shown to open.");
                return
            end
            S.popOut();
            fig = S.PopOutFigure;
        end

        function review(obj)
            % review(obj)
            % Open the session in its behavior GUI (epsych.ReviewSession).
            if obj.Key == ""
                return
            end
            try
                row = obj.Study.Catalog.session(obj.Key);
                epsych.ReviewSession(char(row.File));
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus("Review Session: " + string(ME.message));
            end
        end
    end

    methods (Access = private)
        function drawStaircase_(obj, R)
            obj.releaseStaircase_();
            ax = obj.ensureStairAxes_();
            if R.Parameter == "" || R.NumIncluded == 0 || ~any(R.Track.TrialIndex)
                cla(ax);
                title(ax, 'No staircase to show');
                text(ax, 0.5, 0.5, strjoin(R.Messages, newline), 'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'Color', obj.MUTED, 'Tag', 'SessionView:NoStaircase');
                return
            end
            try
                sess = obj.Study.session(obj.Key);
                S = sess.staircase(obj.Study.Settings, Window = R.Window);
                S.Plot(ax);
                obj.Staircase = S;
                obj.StairSignature_ = obj.signature_(R);
                for p = ["ThresholdFromLastNReversals" "ThresholdFormula" "ApplyWeightedCorrection"]
                    obj.StairListeners_(end+1) = addlistener(S, p, 'PostSet', ...
                        @(~,~) obj.onStaircaseSetting_());
                end
            catch ME
                vprintf(0, 1, ME);
                cla(ax);
                title(ax, 'The staircase could not be drawn');
                text(ax, 0.5, 0.5, string(ME.message), 'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'Color', obj.WARN, 'Tag', 'SessionView:NoStaircase');
            end
        end

        function ax = ensureStairAxes_(obj)
            % The staircase axes, recreated if the last object's teardown took it.
            ax = obj.H.stairAxes;
            if ~isgraphics(ax)
                delete(obj.H.stairGrid.Children);
                ax = uiaxes(obj.H.stairGrid);
                obj.H.stairAxes = ax;
            end
        end

        function onStaircaseSetting_(obj)
            % The plot's right-click menu changed an analysis setting: make it
            % the Study's, so every other tab follows.
            S = obj.Staircase;
            if isempty(S) || ~isvalid(S) || obj.Mirroring_
                return
            end
            s = obj.Study.Settings;
            st = s.Staircase;
            same = st.ThresholdFromLastNReversals == S.ThresholdFromLastNReversals ...
                && string(st.ThresholdFormula) == string(S.ThresholdFormula) ...
                && logical(st.ApplyWeightedCorrection) == logical(S.ApplyWeightedCorrection);
            if same
                return
            end
            st.ThresholdFromLastNReversals = S.ThresholdFromLastNReversals;
            st.ThresholdFormula = string(S.ThresholdFormula);
            st.ApplyWeightedCorrection = logical(S.ApplyWeightedCorrection);
            s.Staircase = st;
            % The drawn staircase already shows these settings: record them as
            % what it was built for, so the SettingsChanged refresh keeps it.
            obj.StairSignature_ = obj.Key + "|" + s.hash() + "|" + string(obj.Result.Window);
            obj.Mirroring_ = true;
            try
                obj.Study.setSettings(s);
                obj.setStatus(sprintf("Threshold: last %d reversals, %s%s -- from the plot menu, now the analysis setting for every session", ...
                    st.ThresholdFromLastNReversals, st.ThresholdFormula, ...
                    repmat(", weighted correction", 1, st.ApplyWeightedCorrection)));
            catch ME
                vprintf(0, 1, ME);
            end
            obj.Mirroring_ = false;
        end

        function releaseStaircase_(obj)
            try
                L = obj.StairListeners_;
                L = L(isvalid(L));
                if ~isempty(L), delete(L); end
            catch ME
                vprintf(2, ME);
            end
            obj.StairListeners_ = event.listener.empty;
            S = obj.Staircase;
            obj.Staircase = [];
            obj.StairSignature_ = "";
            if ~isempty(S) && isvalid(S)
                try
                    S.disablePlot();
                catch ME
                    vprintf(2, ME);
                end
                delete(S);
            end
        end

        function fillPanel_(obj, row, R)
            when = "";
            if isdatetime(R.Start) && ~isnat(R.Start)
                when = string(R.Start, 'yyyy-MM-dd HH:mm');
            end
            parts = [R.Subject, when, strjoin(R.Tags, " "), R.Project];
            parts = parts(strlength(parts) > 0);
            obj.H.title.Text = char(strjoin(parts, '  ·  '));

            w = obj.Study.windowFor(obj.Key);
            obj.H.window.Value = char(w);
            obj.H.window.Placeholder = char(obj.Study.Settings.Window);
            if w == ""
                obj.H.windowHint.Text = '(settings)';
            else
                obj.H.windowHint.Text = '(override)';
            end

            obj.SummaryLines_ = obj.summaryLines_(R);
            obj.H.summary.Value = cellstr(obj.SummaryLines_(:));

            M = R.MetricsSummary;
            if istable(M) && height(M) > 0 && all(ismember(["Label" "Text" "Detail"], string(M.Properties.VariableNames)))
                obj.H.metrics.Data = [cellstr(string(M.Label)), cellstr(string(M.Text)), cellstr(string(M.Detail))];
            else
                obj.H.metrics.Data = cell(0, 3);
            end

            obj.drawFit_(R);

            flags = reshape(string(R.QC), 1, []);
            msgs = reshape(string(R.Messages), 1, []);
            txt = strings(1, 0);
            if ~isempty(flags), txt(end+1) = "QC: " + strjoin(flags, ", "); end
            if ~isempty(msgs), txt(end+1) = strjoin(msgs, " "); end
            obj.H.flags.Text = char(strjoin(txt, newline));
            if isempty(flags)
                obj.H.flags.FontColor = obj.MUTED;
            else
                obj.H.flags.FontColor = obj.WARN;
            end

            notes = "";
            if ismember("NotesText", string(row.Properties.VariableNames))
                notes = string(row.NotesText);
            end
            obj.H.notes.Value = cellstr(splitlines(notes));
            obj.H.btnReview.Enable = matlab.lang.OnOffSwitchState(R.NumIncluded > 0 || numel(R.Excluded) > 0);
            obj.H.btnCopy.Enable = 'on';
        end

        function drawFit_(obj, R)
            F = R.Fit;
            unit = R.Unit;
            param = R.Parameter;
            obj.plotInto_("fit", obj.H.fitAxes, @(ax) localDrawFit(ax, F, unit, param), ...
                obj.label_(R) + " · Psychometric fit");
        end

        function t = label_(~, R)
            % "S1 · 2026-10-01 09:00": what a figure of this session is called.
            t = "Session";
            if isempty(R), return, end
            when = "";
            if isdatetime(R.Start) && ~isnat(R.Start)
                when = string(R.Start, 'yyyy-MM-dd HH:mm');
            end
            parts = [R.Subject, when];
            parts = parts(strlength(parts) > 0);
            if ~isempty(parts), t = strjoin(parts, " · "); end
        end

        function lines = summaryLines_(obj, R)
            s = obj.Study.Settings;
            unit = "";
            if strlength(R.Unit) > 0, unit = " " + R.Unit; end
            auto = "";
            if R.ParameterAuto, auto = " (chosen automatically)"; end
            lines = strings(1, 0);
            lines(end+1) = "Parameter: " + R.Parameter + auto;
            lines(end+1) = sprintf("Window: %s  |  included %d trials (%d stimulus, %d catch)", ...
                R.Window, R.NumIncluded, R.NumStimulus, R.NumCatch);
            used = min(R.ReversalCount, s.Staircase.ThresholdFromLastNReversals);
            lines(end+1) = sprintf("Reversal threshold: %s%s  (%s of last %d reversals, %d in all)", ...
                obj.num_(R.Threshold), unit, obj.pm_(R.ThresholdStd), used, R.ReversalCount);
            if isfinite(R.MedianBlockThreshold)
                lines(end+1) = sprintf("Sliding blocks: min %s, median %s, max %s%s", ...
                    obj.num_(R.MinBlockThreshold), obj.num_(R.MedianBlockThreshold), obj.num_(R.MaxBlockThreshold), unit);
            end
            W = R.Weighted;
            if isstruct(W) && ~isempty(W) && isfield(W, 'Valid') && W.Valid
                lines(end+1) = sprintf("Weighted threshold: %s%s (correction %+.3g, target p = %.2f)", ...
                    obj.num_(W.Threshold), unit, W.Correction, W.TargetProbability);
            end
            F = R.Fit;
            if isstruct(F) && ~isempty(F)
                ci = "";
                if isfield(F, 'CI') && isstruct(F.CI) && isfinite(F.CI.ThresholdLo)
                    ci = sprintf(" [%s, %s]", obj.num_(F.CI.ThresholdLo), obj.num_(F.CI.ThresholdHi));
                end
                if F.Converged && F.Identifiable && string(F.Engine) == "psignifit"
                    lines(end+1) = sprintf("Fitted threshold: %s%s%s  (psignifit %s, slope %s, width %s)", ...
                        obj.num_(F.Threshold), unit, ci, string(F.Shape), obj.num_(F.Beta), obj.num_(F.Width));
                elseif F.Converged && F.Identifiable
                    lines(end+1) = sprintf("Fitted threshold: %s%s%s  (%s, slope %s)", ...
                        obj.num_(F.Threshold), unit, ci, string(F.Shape), obj.num_(F.Beta));
                else
                    lines(end+1) = "Fitted threshold: not available (" + string(F.Message) + ")";
                end
            end
            M = R.Metrics;
            if isstruct(M) && ~isempty(M)
                lines(end+1) = sprintf("d' %s   A' %s   criterion %s", ...
                    obj.num_(M.DPrime), obj.num_(M.APrime), obj.num_(M.Criterion));
                lines(end+1) = sprintf("Hit %s   FA %s   Abort %s", ...
                    obj.pct_(M.Rate.Hit), obj.pct_(M.Rate.FalseAlarm), obj.pct_(M.Rate.Abort));
            end
            lines(end+1) = "Settings " + R.SettingsHash + "  |  " + R.Key;
        end

        function sig = signature_(obj, R)
            % What the drawn staircase depends on.
            sig = obj.Key + "|" + string(R.SettingsHash) + "|" + string(R.Window);
        end

        function clear_(obj)
            obj.releaseStaircase_();
            ax = obj.ensureStairAxes_();
            cla(ax);
            title(ax, '');
            xlabel(ax, '');
            ylabel(ax, '');
            obj.Result = [];
            obj.SummaryLines_ = strings(1, 0);
            obj.H.title.Text = 'No session';
            obj.H.window.Value = '';
            obj.H.window.Placeholder = 'settings';
            obj.H.windowHint.Text = '';
            obj.H.summary.Value = {''};
            obj.H.metrics.Data = cell(0, 3);
            cla(obj.H.fitAxes);
            title(obj.H.fitAxes, '');
            obj.forgetPlot_("fit");
            obj.H.flags.Text = '';
            obj.H.notes.Value = {''};
            obj.H.btnReview.Enable = 'off';
            obj.H.btnCopy.Enable = 'off';
        end

        function onWindowEdited_(obj)
            if obj.Key == ""
                return
            end
            txt = strtrim(string(obj.H.window.Value));
            try
                obj.Study.setWindow(obj.Key, txt);   % ProjectChanged -> refresh
            catch ME
                obj.setStatus("Trial window """ + txt + """ was not understood: " + string(ME.message));
                obj.H.window.Value = char(obj.Study.windowFor(obj.Key));
            end
        end
    end

    methods (Static, Access = private)
        function s = num_(x)
            if isempty(x) || ~isfinite(x)
                s = "n/a";
            else
                s = string(sprintf('%.4g', x));
            end
        end

        function s = pm_(x)
            if isempty(x) || ~isfinite(x)
                s = "";
            else
                s = string(sprintf(' ± %.2g', x));
            end
        end

        function s = pct_(x)
            if isempty(x) || ~isfinite(x)
                s = "n/a";
            else
                s = string(sprintf('%.0f%%', 100 * x));
            end
        end
    end
end


% ---------------------------------------------------------------------------
function H = localDrawFit(ax, F, unit, parameter)
% psignifit's own plotPsych when psignifit made the fit (the Fit tab has the
% rest of its plots); behavior.Plot's otherwise; the reason when neither can.
% A local function so the handle kept for Open in New Figure holds the fit,
% not the view.
H = struct();
try
    if isstruct(F) && ~isempty(F) && string(F.Engine) == "psignifit" ...
            && isstruct(F.Raw) && isfield(F.Raw, 'Fit')
        H = behavior.fit.PsignifitPlot.psych(ax, F, Unit = unit, Parameter = parameter);
        subtitle(ax, '');
    else
        H = behavior.Plot.psychometric(ax, F, Unit = unit);
    end
catch ME
    vprintf(2, 'gui.behavior.SessionView: fit plot not drawn: %s', ME.message);
    cla(ax);
    msg = "No psychometric plot";
    if isstruct(F) && isfield(F, 'Message') && strlength(string(F.Message)) > 0
        msg = string(F.Message);
    end
    text(ax, 0.5, 0.5, msg, 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Color', [0.35 0.38 0.42], 'Tag', 'SessionView:NoFit');
    title(ax, 'Psychometric function');
end
end
