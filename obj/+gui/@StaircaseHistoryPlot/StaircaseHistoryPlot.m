classdef StaircaseHistoryPlot < handle
    % StaircaseHistoryPlot Plot staircase values against trial index.
    %
    %   gui.StaircaseHistoryPlot renders stimulusValues from a
    %   psychophysics.Staircase object on the target axes and updates the
    %   graphics when the attached event source emits NewData. The plot can
    %   show the full history, inferred step directions, and reversal
    %   markers when those values are available from the staircase object.
    %
    %   P = gui.StaircaseHistoryPlot(staircaseObj)
    %   P = gui.StaircaseHistoryPlot(staircaseObj, ax)
    %
    %   2026-03-10

    properties
        ax (1,1)

        staircaseObj

        LineColor   (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(LineColor,1)} = [0.15 0.35 0.75]
        StepColor   (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(StepColor,1)} = [0.90 0.35 0.10]
        NeutralColor (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(NeutralColor,1)} = [0.60 0.60 0.60]
        ReversalColor (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(ReversalColor,1)} = [0.10 0.10 0.10]

        MarkerSize (1,1) double {mustBePositive} = 40
        StepMarkerSize (1,1) double {mustBePositive} = 72
        ReversalMarkerSize (1,1) double {mustBePositive} = 110

        ShowSteps (1,1) logical = true
        ShowReversals (1,1) logical = true
    end

    properties (SetAccess = private)
        LineH
        ScatterH
        StepH
        ReversalH

        hl_NewData = event.listener.empty
    end

    properties (Dependent)
        ParameterName
    end

    methods
        function obj = StaircaseHistoryPlot(staircaseObj, ax)
            % StaircaseHistoryPlot Construct a staircase history plot.
            %
            %   P = gui.StaircaseHistoryPlot(staircaseObj)
            %   P = gui.StaircaseHistoryPlot(staircaseObj, ax)
            %
            %   staircaseObj is a psychophysics.Staircase object. ax is
            %   the target axes. When ax is empty, the current axes are
            %   used.
            %
            %   2026-03-10
            arguments
                staircaseObj {mustBeA(staircaseObj,'psychophysics.Staircase')}
                ax (1,1) = []
            end
            
            if isempty(ax), ax = gca; end

            obj.ax = ax;
            obj.staircaseObj = staircaseObj;
            obj.setup_axes();
        end

        function delete(obj)
            % Destructor: cleans up the listener.
            obj.detach_listener();
        end

        function n = get.ParameterName(obj)
            n = obj.get_parameter_name();
        end

        function set.staircaseObj(obj, sObj)
            assert(isa(sObj, 'psychophysics.Staircase'), ...
                'gui.StaircaseHistoryPlot:set.staircaseObj', ...
                'staircaseObj must be a psychophysics.Staircase object');

            obj.detach_listener();
            obj.staircaseObj = sObj;
            obj.attach_listener();
            obj.update_plot();
        end

        function update_plot(obj, ~, ~)
            % Update the staircase history visualization from current data.
            vprintf(4, 'Updating StaircaseHistoryPlot')

            if isempty(obj.ax) || ~isvalid(obj.ax)
                return
            end

            [x, y, c, xStep, yStep, cStep, xRev, yRev] = obj.get_plot_data();
            obj.ensure_graphics();

            set(obj.LineH, 'XData', x, 'YData', y);
            set(obj.ScatterH, 'XData', x, 'YData', y, ...
                'SizeData', obj.MarkerSize, 'CData', c);

            if obj.ShowSteps
                set(obj.StepH, 'Visible', 'on', 'XData', xStep, 'YData', yStep, ...
                    'SizeData', obj.StepMarkerSize, 'CData', cStep);
            else
                set(obj.StepH, 'Visible', 'off', 'XData', nan, 'YData', nan);
            end

            if obj.ShowReversals
                set(obj.ReversalH, 'Visible', 'on', 'XData', xRev, 'YData', yRev, ...
                    'SizeData', obj.ReversalMarkerSize);
            else
                set(obj.ReversalH, 'Visible', 'off', 'XData', nan, 'YData', nan);
            end

            obj.update_axes_limits(x, y);
            obj.update_labels();
        end
    end

    methods (Access = private)
        function attach_listener(obj)
            source = [];

            if isprop(obj.staircaseObj, 'Helper')
                source = obj.staircaseObj.Helper;
            elseif isprop(obj.staircaseObj, 'Source')
                source = obj.staircaseObj.Source;
            end

            if isempty(source)
                return
            end

            obj.hl_NewData = addlistener(source, 'NewData', @obj.update_plot);
        end

        function detach_listener(obj)
            if ~isempty(obj.hl_NewData)
                delete(obj.hl_NewData);
                obj.hl_NewData = event.listener.empty;
            end
        end

        function setup_axes(obj)
            grid(obj.ax, 'on');
            box(obj.ax, 'on');
            xlabel(obj.ax, 'Trial Index', 'Interpreter', 'none');
            ylabel(obj.ax, char(obj.ParameterName), 'Interpreter', 'none');
        end

        function ensure_graphics(obj)
            if isempty(obj.LineH) || ~isvalid(obj.LineH)
                obj.LineH = line(obj.ax, nan, nan, ...
                    'Color', obj.LineColor, ...
                    'LineWidth', 1.5, ...
                    'Marker', 'none');
            end

            if isempty(obj.ScatterH) || ~isvalid(obj.ScatterH)
                obj.ScatterH = scatter(obj.ax, nan, nan, obj.MarkerSize, ...
                    'filled', ...
                    'Marker', 'o', ...
                    'MarkerEdgeColor', 'none');
            end

            if isempty(obj.StepH) || ~isvalid(obj.StepH)
                obj.StepH = scatter(obj.ax, nan, nan, obj.StepMarkerSize, ...
                    'filled', ...
                    'Marker', 's', ...
                    'MarkerEdgeColor', 'none', ...
                    'Visible', 'off');
            end

            if isempty(obj.ReversalH) || ~isvalid(obj.ReversalH)
                obj.ReversalH = scatter(obj.ax, nan, nan, obj.ReversalMarkerSize, ...
                    'Marker', 'o', ...
                    'MarkerEdgeColor', obj.ReversalColor, ...
                    'MarkerFaceColor', 'none', ...
                    'LineWidth', 1.25, ...
                    'Visible', 'off');
            end

            uistack(obj.ScatterH, 'top');
            uistack(obj.StepH, 'top');
            uistack(obj.ReversalH, 'top');
        end

        function [x, y, c, xStep, yStep, cStep, xRev, yRev] = get_plot_data(obj)
            x = nan(0,1);
            y = nan(0,1);
            c = zeros(0,3);
            xStep = nan(0,1);
            yStep = nan(0,1);
            cStep = zeros(0,3);
            xRev = nan(0,1);
            yRev = nan(0,1);

            trialValue = obj.columnize(obj.staircaseObj.stimulusValues);
            if isempty(trialValue)
                return
            end

            trialIndex = 1:obj.staircaseObj.trialCount;
            direction = obj.staircaseObj.StepDirection;
            reversalIdx = obj.staircaseObj.ReversalIdx;

            valid = ~isnan(trialIndex) & ~isnan(trialValue);
            if ~any(valid)
                return
            end

            x = trialIndex(valid);
            y = trialValue(valid);
            c = obj.direction_colors(direction(valid));

            stepMask = valid & ~isnan(direction) & direction ~= 0;
            if any(stepMask)
                xStep = trialIndex(stepMask);
                yStep = trialValue(stepMask);
                cStep = obj.direction_colors(direction(stepMask));
            end

            if ~isempty(reversalIdx)
                xRev = trialIndex(reversalIdx);
                yRev = trialValue(reversalIdx);
            end
        end

        function update_axes_limits(obj, x, y)
            if isempty(x)
                return
            end

            if numel(x) == 1
                xlim_ = [x(1)-1 x(1)+1];
            else
                xlim_ = [min(x) max(x)];
            end

            yMin = min(y, [], 'omitnan');
            yMax = max(y, [], 'omitnan');
            if isempty(yMin) || isempty(yMax) || any(isnan([yMin yMax]))
                return
            end

            if yMin == yMax
                pad = max(abs(yMin) * 0.05, 0.01);
            else
                pad = max((yMax - yMin) * 0.08, 0.01);
            end

            ylim_ = [yMin - pad yMax + pad];

            set(obj.ax, 'XLim', xlim_, 'YLim', ylim_);
        end

        function update_labels(obj)
            ylabel(obj.ax, char(obj.ParameterName), 'Interpreter', 'none');
            xlabel(obj.ax, 'Trial Index', 'Interpreter', 'none');

            nPlotted = numel(obj.columnize(obj.staircaseObj.stimulusValues));
            subtitle(obj.ax, sprintf('# Plotted Trials = %d', nPlotted));

            [titleText, hasTitle] = obj.get_title_text();
            if hasTitle
                title(obj.ax, titleText);
                obj.ax.TitleHorizontalAlignment = 'right';
            else
                title(obj.ax, '');
            end
        end

        function [titleText, hasTitle] = get_title_text(obj)
            titleText = '';
            hasTitle = false;

            if ~isprop(obj.staircaseObj, 'TRIALS') || isempty(obj.staircaseObj.TRIALS)
                return
            end

            trials = obj.staircaseObj.TRIALS;

            subjectName = trials.Subject.Name;

            boxID = trials.BoxID;

                
            if isempty(boxID)
                titleText = char(subjectName);
            elseif strlength(subjectName) == 0
                titleText = sprintf('[%d]', boxID);
            else
                titleText = sprintf('%s [%d]', subjectName, boxID);
            end

            hasTitle = true;
        end

        function c = direction_colors(obj, direction)
            n = numel(direction);
            c = repmat(obj.NeutralColor, n, 1);

            if n == 0
                return
            end

            if isstring(direction) || ischar(direction)
                direction = string(direction);
                isUp = lower(direction) == "up";
                isDown = lower(direction) == "down";
            else
                isUp = direction > 0;
                isDown = direction < 0;
            end

            c(isUp,:) = repmat(obj.StepColor, nnz(isUp), 1);
            c(isDown,:) = repmat(obj.LineColor, nnz(isDown), 1);
        end

        function n = get_parameter_name(obj)
            n = "Staircase Value";

            if isempty(obj.staircaseObj) || ~isprop(obj.staircaseObj, 'Parameter')
                return
            end

            parameter = obj.staircaseObj.Parameter;
            if isempty(parameter)
                return
            end

            if isprop(parameter, 'Name')
                n = string(parameter.Name);
            end
        end

        function x = get_trial_indices(obj, nTrials)
            x = (1:nTrials).';

            if ~isprop(obj.staircaseObj, 'responseCodes') || ~isprop(obj.staircaseObj, 'StimulusTrialType')
                return
            end

            responseCodes = obj.columnize(obj.staircaseObj.responseCodes);
            if isempty(responseCodes)
                return
            end

            try
                decoded = epsych.BitMask.decode(responseCodes);
            catch
                return
            end

            if ~isstruct(decoded) || ~isfield(decoded, 'TrialType')
                return
            end

            stimMask = decoded.TrialType == obj.staircaseObj.StimulusTrialType;
            stimIdx = find(stimMask(:));
            if numel(stimIdx) < nTrials
                return
            end

            x = stimIdx(1:nTrials);
        end

        function direction = get_step_direction(obj, nTrials)
            direction = nan(nTrials, 1);

            if ~isprop(obj.staircaseObj, 'StepDirection')
                return
            end

            rawDirection = obj.columnize(obj.staircaseObj.StepDirection);
            if isempty(rawDirection)
                return
            end

            nCopy = min(nTrials, numel(rawDirection));
            direction(1:nCopy) = rawDirection(1:nCopy);
        end

        function reversalIdx = get_reversal_indices(obj, nTrials)
            reversalIdx = zeros(0,1);

            if ~isprop(obj.staircaseObj, 'ReversalIdx')
                return
            end

            reversalIdx = obj.columnize(obj.staircaseObj.ReversalIdx);
            if isempty(reversalIdx)
                reversalIdx = zeros(0,1);
                return
            end

            reversalIdx = reversalIdx(~isnan(reversalIdx));
            reversalIdx = round(reversalIdx);
            reversalIdx = reversalIdx(reversalIdx >= 1 & reversalIdx <= nTrials);
        end

        function values = columnize(~, values)
            if isempty(values)
                values = nan(0,1);
            else
                values = values(:);
            end
        end
    end
end