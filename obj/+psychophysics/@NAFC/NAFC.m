classdef NAFC < psychophysics.Psych & gui.PopOut
    % A = psychophysics.NAFC(RUNTIME, Parameter)
    % A = psychophysics.NAFC(DATA, Parameter)
    % A = psychophysics.NAFC(..., Name=Value)
    % N-alternative forced choice analysis with customizable plotting.
    %
    % NAFC scores tasks in which the subject must pick one of N alternatives
    % on every trial -- 2AFC side discriminations, 4AFC spatial tasks, and so
    % on. It computes, over the whole session and per unique value of the
    % tracked Parameter:
    %
    %   - the proportion correct (against a 1/N chance level)
    %   - the choice function: P(chose k) for every alternative, which for a
    %     2AFC over a signed stimulus IS the psychometric function
    %   - the confusion matrix (correct alternative x chosen alternative)
    %   - each alternative's overall choice proportion and bias re 1/N
    %   - answered / aborted / no-response / invalid trial counts
    %
    % SCORING AN N-AFC TRIAL
    %   Every alternative is a response, so no outcome name may carry the
    %   side. CorrectReject and FalseAlarm belong to detection -- they name
    %   what a subject does when there is nothing to respond to -- and are
    %   NOT used in an N-AFC. What was chosen and whether it was right are
    %   recorded as separate bits (epsych.BitMask.getResponses lists the
    %   outcome bits; epsych.BitMask.getChoices the choice bits):
    %
    %     Choice_k    which alternative was chosen, k = 0..5. Set on every
    %                 trial the subject answered, and only those.
    %     Hit         the chosen alternative was the correct one.
    %     Miss        the subject chose, but chose wrong.
    %     Abort       a response arrived before the response window opened.
    %     (no bit)    no response at all: Undefined. No outcome bit and no
    %                 Choice bit, which is what distinguishes it from Miss.
    %     TrialType_k the trial's category -- stimulus, catch, remind, or
    %                 whatever else the paradigm defines. A property of the
    %                 trial, independent of the response.
    %     Reward / Punish are experimental design, not scoring: include them
    %                 when the paradigm delivers one, omit them otherwise.
    %
    %   So a rightward choice is Choice_1 + Hit when right was correct and
    %   Choice_1 + Miss when it was not. Correct is Hit and only Hit, which
    %   is what makes proportion correct read the same for every N.
    %
    % Where the data comes from:
    %   Choice   - Choice_0..Choice_5 bits decoded from RespCode by default,
    %       or a DATA field named by ChoiceField holding the 0-based chosen
    %       alternative (negative = no answer). A field supports any N;
    %       the bits stop at 6 alternatives.
    %   Correct  - the DATA field named by CorrectField (default TrialType),
    %       else TrialType_* bits from RespCode. The bit fallback works only
    %       where the trial's category IS the correct alternative, as in the
    %       examples/two_afc left-target / right-target trials; a paradigm
    %       whose trial types are stimulus/catch/remind must name a field.
    %   Value    - the tracked Parameter, as in every psychophysics.Psych.
    %
    %   Note that NAFC derives correctness from Choice vs Correct, never
    %   from the Hit/Miss bits, so it also scores a session whose rig wrote
    %   only the Choice_* bits (an on-board state machine that cannot see
    %   which alternative was correct: see teensy.Templates.twoAFC).
    %
    % Like every psychophysics.Psych subclass it works online (construct with
    % a Runtime and it follows NewData events) or offline (construct with a
    % saved DATA struct array).
    %
    % Plotting is optional and customizable. Plot() draws into its own window
    % or any axes you pass, and afterwards redraws itself on every refresh:
    %
    %   PlotType     - "choice" (one curve per alternative), "performance"
    %       (proportion correct vs value), or "confusion" (matrix heatmap).
    %       Switchable from the plot's right-click menu.
    %   ChoiceColors / ChoiceLabels - per-alternative line colors and legend
    %       names ("Left"/"Right" instead of "Choice 0"/"Choice 1").
    %   ShowChance   - dashed reference line at 1/N on the curve plots.
    %   MarkerSize, LineWidth, PerformanceColor, ChanceColor - styling.
    %
    % The plot's right-click menu also offers "Open in Separate Window" (see
    % gui.PopOut): a second NAFC over the same trials with graphics of its
    % own, so restyling or closing the pop-out leaves the embedded plot alone.
    %
    % Example:
    %   A = psychophysics.NAFC(RUNTIME, Parameter, NumAlternatives=2, ...
    %       ChoiceField="ChoiceSide", ChoiceLabels=["Left","Right"], Plot=true);
    %   A = psychophysics.NAFC(DATA, 'SignedContrast');
    %   A.Plot();                          % own window, default PlotType
    %   A.Plot(ax, PlotType="confusion");  % embed in an existing axes
    %   A.PlotType = "performance";        % live plots redraw immediately
    %   disp(A.Results.CorrectRate)
    %
    % See documentation/psychophysics/psychophysics_NAFC.md and the 2AFC
    % tutorial (examples/two_afc), whose behavior GUI embeds this analysis.
    %
    % See also psychophysics.Psych, psychophysics.SessionMetrics,
    % psychophysics.Detection, gui.PopOut

    properties (SetObservable)
        % NumAlternatives - Number of response alternatives. 0 (default)
        % auto-detects from the data (largest alternative seen + 1, at least
        % 2); a value >= 2 fixes N, and choices outside 0..N-1 are counted
        % in Results.NumInvalid rather than silently rescaling chance.
        NumAlternatives (1,1) double {mustBeInteger, mustBeNonnegative} = 0

        % ChoiceField - DATA field holding the 0-based chosen alternative
        % (negative = no answer). Empty: decode Choice_* bits from RespCode.
        ChoiceField (1,1) string = ""

        % CorrectField - DATA field holding the 0-based correct alternative.
        % When absent from DATA, TrialType_* bits from RespCode are used.
        CorrectField (1,1) string = "TrialType"

        % ChoiceLabels - Display names per alternative, e.g. ["Left","Right"].
        % Shorter-than-N lists are padded with "Choice k".
        ChoiceLabels (1,:) string = string.empty(1,0)

        % ChoiceColors - Hex color per alternative for the choice curves and
        % confusion columns. Empty: the toolbox Choice_* palette, cycled.
        ChoiceColors (1,:) string = string.empty(1,0)

        PerformanceColor (1,1) string = "#0f7c8a"  % proportion-correct curve
        ChanceColor      (1,1) string = "#999999"  % 1/N reference line

        MarkerSize (1,1) double {mustBePositive} = 42
        LineWidth  (1,1) double {mustBePositive} = 1.5

        ShowChance (1,1) logical = true  % draw the 1/N reference on curve plots
    end

    properties (SetObservable, AbortSet)
        % PlotType - Which picture the plot draws; switchable at runtime and
        % from the plot's right-click menu. See the class help.
        PlotType (1,1) string {mustBeMember(PlotType,["choice","performance","confusion"])} = "choice"
    end

    properties (SetAccess = protected)
        Results = []  % Computed NAFC outputs; see emptyResults_ for the fields
    end

    properties (Access = private)
        % Plot state (optional).
        plotEnabled_ (1,1) logical = false
        plotAxes_ = []
        plotFigure_ = []
        plotOwnsFigure_ (1,1) logical = false
        plotListeners_ = event.listener.empty
        plotContextMenu_ = []
    end

    methods
        function obj = NAFC(source, Parameter, options)
            % A = psychophysics.NAFC(RUNTIME, Parameter)
            % A = psychophysics.NAFC(DATA, Parameter)
            % A = psychophysics.NAFC(..., Name=Value)
            % Construct an NAFC analysis for online or offline data.
            %
            % Parameters:
            %   RUNTIME         - Runtime object with EVENTS for online mode.
            %   DATA            - Per-trial struct array for offline mode.
            %   Parameter       - hw.Parameter object, or in offline mode a
            %                     DATA field name. May be empty: the session
            %                     summaries and confusion matrix need no
            %                     tracked value, only the by-value curves do.
            %   NumAlternatives - Fixed N, or 0 to auto-detect (default).
            %   ChoiceField     - DATA field with the chosen alternative;
            %                     "" (default) decodes Choice_* bits.
            %   CorrectField    - DATA field with the correct alternative
            %                     (default "TrialType").
            %   ChoiceLabels    - Display names per alternative.
            %   ChoiceColors    - Hex color per alternative.
            %   ExcludedTrials  - Logical mask or 1-based indices to drop.
            %   Plot            - Enable plotting now (default false).
            %   PlotAxes        - Axes to draw into; own figure when empty.
            %   PlotType        - Initial plot type (default "choice").
            %   ShowChance      - Draw the 1/N reference (default true).
            %
            % Returns:
            %   obj - Configured psychophysics.NAFC instance.
            arguments
                source = []
                Parameter = []
                options.NumAlternatives (1,1) double {mustBeInteger, mustBeNonnegative} = 0
                options.ChoiceField (1,1) string = ""
                options.CorrectField (1,1) string = "TrialType"
                options.ChoiceLabels (1,:) string = string.empty(1,0)
                options.ChoiceColors (1,:) string = string.empty(1,0)
                options.ExcludedTrials = []
                options.Plot (1,1) logical = false
                options.PlotAxes = []
                options.PlotType (1,1) string {mustBeMember(options.PlotType,["choice","performance","confusion"])} = "choice"
                options.ShowChance (1,1) logical = true
            end

            obj = obj@psychophysics.Psych(source, Parameter, ExcludedTrials=options.ExcludedTrials);

            obj.NumAlternatives = options.NumAlternatives;
            obj.ChoiceField     = options.ChoiceField;
            obj.CorrectField    = options.CorrectField;
            obj.ChoiceLabels    = options.ChoiceLabels;
            obj.ChoiceColors    = options.ChoiceColors;
            obj.ShowChance      = options.ShowChance;
            obj.PlotType        = options.PlotType;

            obj.refresh();

            if options.Plot
                obj.Plot(options.PlotAxes, PlotType=options.PlotType);
            end
        end

        function delete(obj)
            % delete(obj)
            % Release plot graphics and listeners before base teardown.
            obj.disablePlot();
            delete@psychophysics.Psych(obj);
        end

        function set.PlotType(obj, value)
            % obj.PlotType = value
            % Switch the picture; a live plot redraws immediately.
            obj.PlotType = value;
            obj.refreshPlot();
        end

        function Plot(obj, ax, options)
            % obj.Plot()
            % obj.Plot(ax)
            % obj.Plot(ax, PlotType="confusion", ShowChance=false)
            % Enable plotting. With empty ax a new uifigure/uiaxes is created
            % and owned; the plot then redraws itself on every refresh (each
            % NewData event in online mode).
            %
            % Parameters:
            %   ax         - Target axes. When empty, a new figure is created.
            %   PlotType   - "choice", "performance", or "confusion".
            %                The default is obj.PlotType.
            %   ShowChance - Draw the 1/N reference. The default is obj.ShowChance.
            arguments
                obj
                ax = []
                options.PlotType (1,1) string {mustBeMember(options.PlotType,["choice","performance","confusion"])} = obj.PlotType
                options.ShowChance (1,1) logical = obj.ShowChance
            end

            obj.disablePlot();

            obj.ShowChance = options.ShowChance;

            if isempty(ax)
                fig = uifigure('Name', obj.plotWindowTitle_());
                fig.CloseRequestFcn = @(src,~) obj.onPlotFigureClose_(src);
                layout = uigridlayout(fig, [1 1]);
                layout.RowHeight   = {'1x'};
                layout.ColumnWidth = {'1x'};
                ax = uiaxes(layout);
                obj.plotFigure_ = fig;
                obj.plotOwnsFigure_ = true;
            else
                obj.plotFigure_ = ancestor(ax, 'figure');
                obj.plotOwnsFigure_ = false;
            end

            obj.plotAxes_ = ax;
            obj.plotEnabled_ = true;

            obj.attachPlotDestructionListeners_();
            obj.applyAxesStyle_();
            obj.createPlotContextMenu_();

            % Assigning through the property keeps the setter's redraw path;
            % AbortSet means an unchanged type falls through to the explicit
            % update below.
            obj.PlotType = options.PlotType;
            obj.updatePlot_();
        end

        function disablePlot(obj)
            % disablePlot(obj)
            % Disable plotting and release graphics/listeners.
            obj.plotEnabled_ = false;

            if ~isempty(obj.plotListeners_)
                L = obj.plotListeners_;
                L = L(isvalid(L));
                if ~isempty(L)
                    delete(L);
                end
                obj.plotListeners_ = event.listener.empty;
            end

            if ~isempty(obj.plotContextMenu_) && isvalid(obj.plotContextMenu_)
                delete(obj.plotContextMenu_);
            end
            obj.plotContextMenu_ = [];

            if ~isempty(obj.plotAxes_) && isvalid(obj.plotAxes_)
                cla(obj.plotAxes_);
                legend(obj.plotAxes_, 'off');
            end

            if obj.plotOwnsFigure_ && ~isempty(obj.plotFigure_) && isvalid(obj.plotFigure_)
                delete(obj.plotFigure_);
            end

            obj.plotAxes_ = [];
            obj.plotFigure_ = [];
            obj.plotOwnsFigure_ = false;
        end

        function refreshPlot(obj)
            % refreshPlot(obj)
            % Re-render the plot from current results (no-op when disabled).
            % Call after changing style properties outside the context menu.
            if ~obj.plotEnabled_
                return
            end
            obj.updatePlot_();
        end

        function labels = alternativeLabels(obj)
            % labels = alternativeLabels(obj)
            % Display name for every alternative: ChoiceLabels padded with
            % "Choice k" out to the current NumAlternatives.
            %
            % Returns:
            %   labels - 1xN string array.
            n = obj.currentN_();
            labels = strings(1, n);
            for k = 1:n
                if k <= numel(obj.ChoiceLabels) && strlength(obj.ChoiceLabels(k)) > 0
                    labels(k) = obj.ChoiceLabels(k);
                else
                    labels(k) = sprintf("Choice %d", k-1);
                end
            end
        end

        function colors = alternativeColors(obj)
            % colors = alternativeColors(obj)
            % Hex color for every alternative: ChoiceColors padded from the
            % toolbox Choice_* palette, cycled past its end.
            %
            % Returns:
            %   colors - 1xN string array of hex colors.
            n = obj.currentN_();
            palette = epsych.BitMask.getDefaultColors(epsych.BitMask.getChoices);
            palette = reshape(string(palette), 1, []);
            colors = strings(1, n);
            for k = 1:n
                if k <= numel(obj.ChoiceColors) && strlength(obj.ChoiceColors(k)) > 0
                    colors(k) = obj.ChoiceColors(k);
                else
                    colors(k) = palette(mod(k-1, numel(palette)) + 1);
                end
            end
        end
    end

    methods (Access = protected)
        function recomputeResults_(obj)
            % Recompute session and by-value NAFC statistics from DATA.
            R = obj.emptyResults_();

            n = obj.trialCount;
            if n == 0
                obj.Results = R;
                return
            end

            included = ~obj.excludedTrialMask_();
            choice   = obj.choiceValues_(n);
            correct  = obj.correctValues_(n);
            values   = obj.stimulusValues_(n);

            N = obj.resolveNumAlternatives_(choice, correct);
            R.NumAlternatives = N;
            R.ChanceLevel = 1 / N;

            % A choice outside 0..N-1 with a fixed N is a recording error,
            % not an extra alternative: count it, drop it, keep chance at 1/N.
            invalid = included & (choice > N-1 | correct > N-1);
            R.NumInvalid = sum(invalid);
            if R.NumInvalid > 0
                vprintf(2, 'psychophysics.NAFC: %d trials carry an alternative outside 0..%d and were dropped', ...
                    R.NumInvalid, N-1);
            end
            included = included & ~invalid;

            answered = included & ~isnan(choice);
            scored   = answered & ~isnan(correct);

            R.Choice = choice;
            R.CorrectAlternative = correct;
            R.Included = included;

            isCorrect = nan(1, n);
            isCorrect(scored) = double(choice(scored) == correct(scored));
            R.IsCorrect = isCorrect;

            R.NumTrials   = sum(included);
            R.NumAnswered = sum(answered);

            % Two ways to leave a trial unanswered, and they are not the same
            % failure: an Abort is a response that came too early, so the bit
            % is the only record of it, while a trial that simply lapsed
            % carries no outcome bit at all (Undefined). A session whose rig
            % wrote no response codes reports every unanswered trial as a
            % no-response, which is the safe reading.
            R.NumUnanswered  = R.NumTrials - R.NumAnswered;
            R.NumAborted     = sum(included & ~answered & obj.abortMask_(n));
            R.NumNoResponse  = R.NumUnanswered - R.NumAborted;
            R.AbortRate      = obj.ratio_(R.NumAborted, R.NumTrials);
            R.NoResponseRate = obj.ratio_(R.NumNoResponse, R.NumTrials);

            R.ChoiceTotals = zeros(1, N);
            for k = 1:N
                R.ChoiceTotals(k) = sum(answered & choice == k-1);
            end
            R.ChoiceProportion = nan(1, N);
            R.ChoiceBias = nan(1, N);
            if R.NumAnswered > 0
                R.ChoiceProportion = R.ChoiceTotals / R.NumAnswered;
                R.ChoiceBias = R.ChoiceProportion - R.ChanceLevel;
            end

            R.PercentCorrect = obj.ratio_(sum(isCorrect(scored)), sum(scored));

            % Confusion: rows = correct alternative, columns = chosen.
            R.ConfusionCount = zeros(N, N);
            for c = 1:N
                rowMask = scored & correct == c-1;
                for k = 1:N
                    R.ConfusionCount(c,k) = sum(rowMask & choice == k-1);
                end
            end
            rowN = sum(R.ConfusionCount, 2);
            R.ConfusionRate = nan(N, N);
            hasRow = rowN > 0;
            R.ConfusionRate(hasRow,:) = R.ConfusionCount(hasRow,:) ./ rowN(hasRow);

            % By-value curves need a value on the trial; sessions tracking no
            % parameter simply leave these empty.
            byValue = answered & ~isnan(values);
            uv = unique(values(byValue));
            R.Values = reshape(uv, 1, []);
            nv = numel(uv);
            R.NumByValue     = zeros(1, nv);
            R.CorrectCount   = zeros(1, nv);
            R.CorrectRate    = nan(1, nv);
            R.ChoiceCount    = zeros(N, nv);
            R.ChoiceRate     = nan(N, nv);
            for i = 1:nv
                vMask = byValue & values == uv(i);
                R.NumByValue(i) = sum(vMask);
                for k = 1:N
                    R.ChoiceCount(k,i) = sum(vMask & choice == k-1);
                end
                R.ChoiceRate(:,i) = R.ChoiceCount(:,i) / R.NumByValue(i);

                sMask = vMask & scored;
                R.CorrectCount(i) = sum(isCorrect(sMask));
                R.CorrectRate(i)  = obj.ratio_(R.CorrectCount(i), sum(sMask));
            end

            obj.Results = R;
        end

        function afterRefresh_(obj)
            % Redraw the plot after every recompute when enabled.
            if obj.plotEnabled_
                obj.updatePlot_();
            end
        end

        function c = popOutHostContainer_(obj)
            % Axes this analysis is plotted into (gui.PopOut).
            c = obj.plotAxes_;
        end

        function h = createPopOut_(obj, container)
            % A second NAFC over the same trials, plotted in its own window.
            % A sibling analysis rather than a second view of this one: the
            % plot's settings (type, chance line, colors) are properties of
            % the analysis, so sharing it would make a change in the pop-out
            % rewrite the embedded plot as well.
            layout = uigridlayout(container, [1 1]);
            layout.RowHeight   = {'1x'};
            layout.ColumnWidth = {'1x'};
            layout.Padding     = [2 2 2 2];
            ax = uiaxes(layout);

            source = obj.RUNTIME;
            if isempty(source), source = obj.DATA; end

            h = psychophysics.NAFC(source, obj.Parameter, ...
                NumAlternatives = obj.NumAlternatives, ...
                ChoiceField     = obj.ChoiceField, ...
                CorrectField    = obj.CorrectField, ...
                ChoiceLabels    = obj.ChoiceLabels, ...
                ChoiceColors    = obj.ChoiceColors, ...
                ExcludedTrials  = obj.ExcludedTrials, ...
                PlotType        = obj.PlotType, ...
                ShowChance      = obj.ShowChance);

            props = {'PerformanceColor','ChanceColor','MarkerSize','LineWidth', ...
                'StimulusTrialType','CatchTrialType','Bits','BitColors'};
            for k = 1:numel(props)
                h.(props{k}) = obj.(props{k});
            end

            % Online, a fresh analysis holds no trials until the next
            % NewData; hand it the session so far so the window opens on the
            % same picture instead of an empty axes.
            if ~isempty(obj.RUNTIME)
                h.DATA = obj.DATA;
            end
            h.refresh();

            h.Plot(ax);
        end
    end

    methods (Access = private)
        function ch = choiceValues_(obj, n)
            % Chosen alternative per trial: NaN = no answer. From ChoiceField
            % when configured (negative sentinel = no answer), else from
            % Choice_* bits in the response code.
            ch = nan(1, n);

            if strlength(obj.ChoiceField) > 0
                v = obj.dataFieldValues_(char(obj.ChoiceField));
                if isempty(v), return; end
                v = double(v);
                v(v < 0) = NaN;
                m = min(n, numel(v));
                ch(1:m) = v(1:m);
                return
            end

            ch = obj.bitIndexValues_(n, epsych.BitMask.getChoices);
        end

        function cv = correctValues_(obj, n)
            % Correct alternative per trial: the CorrectField values when the
            % field exists (negative = unknown), else TrialType_* bits.
            cv = nan(1, n);

            fieldName = char(obj.CorrectField);
            if ~isempty(fieldName) && ~isempty(obj.DATA) && isfield(obj.DATA, fieldName)
                v = double(obj.dataFieldValues_(fieldName));
                if ~isempty(v)
                    v(v < 0) = NaN;
                    m = min(n, numel(v));
                    cv(1:m) = v(1:m);
                end
                return
            end

            cv = obj.bitIndexValues_(n, epsych.BitMask.getTrialTypes);
        end

        function m = abortMask_(obj, n)
            % Trials carrying the Abort bit, padded/trimmed to n. All false
            % when the session recorded no response codes.
            m = false(1, n);
            rc = obj.responseCodes;
            if isempty(rc), return; end

            a = reshape(logical(bitget(uint32(rc), uint32(epsych.BitMask.Abort))), 1, []);
            k = min(n, numel(a));
            m(1:k) = a(1:k);
        end

        function idx = bitIndexValues_(obj, n, bits)
            % 0-based index per trial from a family of one-hot bits in the
            % response code; the lowest set bit wins, no bit set stays NaN.
            idx = nan(1, n);
            rc = obj.responseCodes;
            if isempty(rc), return; end

            M = epsych.BitMask.decode(rc);
            for k = 1:numel(bits)
                m = reshape(logical(M.(char(bits(k)))), 1, []);
                if numel(m) < n
                    m(end+1:n) = false;
                else
                    m = m(1:n);
                end
                m = m & isnan(idx);
                idx(m) = k - 1;
            end
        end

        function v = stimulusValues_(obj, n)
            % Tracked parameter value per trial; all-NaN with no Parameter,
            % which limits the analysis to the session-level statistics.
            v = nan(1, n);
            if isempty(obj.Parameter), return; end

            x = obj.dataFieldValues_(obj.parameterFieldName_());
            if isempty(x), return; end
            x = double(x);
            m = min(n, numel(x));
            v(1:m) = x(1:m);
        end

        function N = resolveNumAlternatives_(obj, choice, correct)
            % Fixed by the property when >= 2, else the largest alternative
            % the data mentions plus one, and never fewer than 2.
            if obj.NumAlternatives >= 2
                N = obj.NumAlternatives;
                return
            end
            N = max([2, max(choice, [], 'omitnan') + 1, max(correct, [], 'omitnan') + 1]);
        end

        function n = currentN_(obj)
            % NumAlternatives as the plot and labels should use it now.
            if ~isempty(obj.Results) && obj.Results.NumAlternatives >= 2
                n = obj.Results.NumAlternatives;
            elseif obj.NumAlternatives >= 2
                n = obj.NumAlternatives;
            else
                n = 2;
            end
        end

        function t = plotWindowTitle_(obj)
            t = sprintf('%dAFC', obj.currentN_());
            if strlength(obj.ParameterName) > 0
                t = sprintf('%s | %s', t, char(obj.ParameterName));
            end
        end
    end

    methods (Access = private)
        % Plot helper methods (implemented as separate files in @NAFC)
        attachPlotDestructionListeners_(obj)
        onPlotFigureClose_(obj, fig)
        applyAxesStyle_(obj)
        createPlotContextMenu_(obj)
        updatePlot_(obj)
        drawChoicePlot_(obj, ax, R)
        drawPerformancePlot_(obj, ax, R)
        drawConfusionPlot_(obj, ax, R)
        drawChanceLine_(obj, ax, chance)
    end

    methods (Static, Access = private)
        function R = emptyResults_()
            % Result skeleton, so every field exists before the first trial.
            R = struct( ...
                'NumAlternatives',    2, ...
                'ChanceLevel',        0.5, ...
                'NumTrials',          0, ...
                'NumAnswered',        0, ...
                'NumUnanswered',      0, ...
                'NumAborted',         0, ...
                'NumNoResponse',      0, ...
                'NumInvalid',         0, ...
                'AbortRate',          NaN, ...
                'NoResponseRate',     NaN, ...
                'PercentCorrect',     NaN, ...
                'Choice',             zeros(1,0), ...
                'CorrectAlternative', zeros(1,0), ...
                'IsCorrect',          zeros(1,0), ...
                'Included',           false(1,0), ...
                'ChoiceTotals',       zeros(1,2), ...
                'ChoiceProportion',   nan(1,2), ...
                'ChoiceBias',         nan(1,2), ...
                'ConfusionCount',     zeros(2,2), ...
                'ConfusionRate',      nan(2,2), ...
                'Values',             zeros(1,0), ...
                'NumByValue',         zeros(1,0), ...
                'CorrectCount',       zeros(1,0), ...
                'CorrectRate',        zeros(1,0), ...
                'ChoiceCount',        zeros(2,0), ...
                'ChoiceRate',         zeros(2,0));
        end

        function r = ratio_(num, den)
            if den == 0
                r = NaN;
            else
                r = double(num) ./ double(den);
            end
        end
    end
end
