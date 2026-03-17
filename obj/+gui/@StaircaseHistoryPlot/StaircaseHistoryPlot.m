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
        h_line
        h_points
        h_thrreg
        h_thrline
        StepH
        ReversalUpH
        ReversalDownH

        hl_NewData = event.listener.empty

        staircaseObj
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
            obj.detach_listener();
            obj.hl_NewData = addlistener(staircaseObj.Helper, 'NewData', @(src, event)obj.update_plot(src, event));
            obj.update_plot();
            
        end

        function delete(obj)
            % Destructor: cleans up the listener.
            obj.detach_listener();
        end

        function n = get.ParameterName(obj)
            n = obj.staircaseObj.Parameter.Name;
        end


        function update_plot(obj, ~, ~)
            % Update the staircase history visualization from current data.
            vprintf(4, 'Updating StaircaseHistoryPlot')

            if isempty(obj.ax) || ~isvalid(obj.ax)
                return
            end

            [x, y, c, xStep, yStep, cStep, xRevUp, yRevUp, xRevDown, yRevDown] = obj.get_plot_data();

            if isempty(obj.h_line) || ~isvalid(obj.h_line), return; end


            set(obj.h_line, 'XData', x, 'YData', y);
            set(obj.h_points, 'XData', x, 'YData', y, ...
                'SizeData', obj.MarkerSize, 'CData', c);

            if obj.ShowSteps
                set(obj.StepH, 'Visible', 'on', 'XData', xStep, 'YData', yStep, ...
                    'SizeData', obj.StepMarkerSize, 'CData', cStep);
            else
                set(obj.StepH, 'Visible', 'off', 'XData', nan, 'YData', nan);
            end

            if obj.ShowReversals
                set(obj.ReversalUpH, 'Visible', 'on', 'XData', xRevUp, 'YData', yRevUp, ...
                    'SizeData', obj.ReversalMarkerSize);
                set(obj.ReversalDownH, 'Visible', 'on', 'XData', xRevDown, 'YData', yRevDown, ...
                    'SizeData', obj.ReversalMarkerSize);
            else
                set(obj.ReversalUpH, 'Visible', 'off', 'XData', nan, 'YData', nan);
                set(obj.ReversalDownH, 'Visible', 'off', 'XData', nan, 'YData', nan);
            end

            if ~isempty(obj.staircaseObj.Threshold)
                ridx = obj.staircaseObj.ReversalIdx;
                xThr = ridx(max(1,length(ridx)-obj.staircaseObj.ThresholdFromLastNReversals));
                xThr(2) = ridx(end);
                yThr = [1 1]*obj.staircaseObj.Threshold;
                set(obj.h_thrline,'XData',xThr,'YData',yThr)

                yThrStd = obj.staircaseObj.ThresholdStd;
                set(obj.h_thrreg,'XData',[xThr(1) xThr(2) xThr(2) xThr(1)], ...
                    'YData',[yThr(1)-yThrStd, yThr(2)-yThrStd, yThr(2)+yThrStd, yThr(1)+yThrStd])
            end

            axis(obj.ax,'normal')
            obj.update_labels();
        end
    end

    methods (Access = private)

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

            hold(obj.ax,'on')

            obj.h_thrreg = patch(obj.ax,nan,nan,[0.85 0.85 0.85], ...
                EdgeColor='none', ...
                FaceAlpha=0.5);
            
            obj.h_thrline = line(obj.ax, nan, nan, ...
                'Color', [0.25 0.25 0.25], ...
                'LineWidth', 2, ...
                'LineStyle', '-', ...
                'Marker', 'none');

            obj.h_line = line(obj.ax, nan, nan, ...
                'Color', obj.LineColor, ...
                'LineWidth', 1.5, ...
                'Marker', 'none');


            obj.h_points = scatter(obj.ax, nan, nan, obj.MarkerSize, ...
                'filled', ...
                'Marker', 'o', ...
                'MarkerEdgeColor', 'none');


            obj.StepH = scatter(obj.ax, nan, nan, obj.StepMarkerSize, ...
                'filled', ...
                'Marker', 's', ...
                'MarkerEdgeColor', 'none', ...
                'Visible', 'off');


            obj.ReversalUpH = scatter(obj.ax, nan, nan, obj.ReversalMarkerSize, ...
                'Marker', '^', ...
                'MarkerEdgeColor', obj.ReversalColor, ...
                'MarkerFaceColor', obj.ReversalColor, ...
                'LineWidth', 1, ...
                'Visible', 'off');


            obj.ReversalDownH = scatter(obj.ax, nan, nan, obj.ReversalMarkerSize, ...
                'Marker', 'v', ...
                'MarkerEdgeColor', obj.ReversalColor, ...
                'MarkerFaceColor', obj.ReversalColor, ...
                'LineWidth', 1, ...
                'Visible', 'off');
            hold(obj.ax,'off')


        end


        function [x, y, c, xStep, yStep, cStep, xRevUp, yRevUp, xRevDown, yRevDown] = get_plot_data(obj)
            x = nan;
            y = nan;
            c = zeros(1,3);
            xStep = nan;
            yStep = nan;
            cStep = zeros(1,3);
            xRevUp = nan;
            yRevUp = nan;
            xRevDown = nan;
            yRevDown = nan;

            trialValue = obj.columnize(obj.staircaseObj.stimulusValues);
            if isempty(trialValue)
                return
            end

            trialIndex  = obj.columnize(1:obj.staircaseObj.trialCount);
            direction   = obj.columnize(obj.staircaseObj.StepDirection);
            reversalIdx = obj.columnize(obj.staircaseObj.ReversalIdx);

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

            reversalIdx = reversalIdx(~isnan(reversalIdx));
            reversalIdx = reversalIdx(reversalIdx >= 1 & reversalIdx <= numel(direction));
            if ~isempty(reversalIdx)
                reversalDir = direction(reversalIdx+1);

                upMask = reversalDir > 0;
                if any(upMask)
                    xRevUp = trialIndex(reversalIdx(upMask));
                    yRevUp = trialValue(reversalIdx(upMask));
                end

                downMask = reversalDir < 0;
                if any(downMask)
                    xRevDown = trialIndex(reversalIdx(downMask));
                    yRevDown = trialValue(reversalIdx(downMask));
                end
            end
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
            titleParts = {};

            if isprop(obj.staircaseObj, 'TRIALS') && ~isempty(obj.staircaseObj.TRIALS)
                trials = obj.staircaseObj.TRIALS;

                subjectName = "";
                if isprop(trials, 'Subject') && ~isempty(trials.Subject) && isprop(trials.Subject, 'Name')
                    subjectName = string(trials.Subject.Name);
                end

                boxID = [];
                if isprop(trials, 'BoxID')
                    boxID = trials.BoxID;
                end

                if isempty(boxID)
                    if strlength(subjectName) > 0
                        titleParts{end+1} = char(subjectName); %#ok<AGROW>
                    end
                elseif strlength(subjectName) == 0
                    titleParts{end+1} = sprintf('[%d]', boxID); %#ok<AGROW>
                else
                    titleParts{end+1} = sprintf('%s [%d]', subjectName, boxID); %#ok<AGROW>
                end
            end

            if isprop(obj.staircaseObj, 'ReversalCount') && ~isempty(obj.staircaseObj.ReversalCount)
                reversalCount = obj.staircaseObj.ReversalCount;
                if isscalar(reversalCount) && isfinite(reversalCount)
                    titleParts{end+1} = sprintf('Reversals: %d', reversalCount); %#ok<AGROW>
                end
            end

            if isprop(obj.staircaseObj, 'Threshold') && ~isempty(obj.staircaseObj.Threshold)
                threshold = obj.staircaseObj.Threshold;
                if isscalar(threshold) && isfinite(threshold)
                    configuredReversals = [];
                    if isprop(obj.staircaseObj, 'ThresholdFromLastNReversals')
                        configuredReversals = obj.staircaseObj.ThresholdFromLastNReversals;
                    end

                    actualReversals = [];
                    if isprop(obj.staircaseObj, 'ReversalCount')
                        actualReversals = obj.staircaseObj.ReversalCount;
                    end

                    if isscalar(configuredReversals) && isfinite(configuredReversals)
                        if isscalar(actualReversals) && isfinite(actualReversals)
                            nUsed = min(actualReversals, configuredReversals);
                            titleParts{end+1} = sprintf('Threshold (%d/%d rev): %.3f', nUsed, configuredReversals, threshold); %#ok<AGROW>
                        else
                            titleParts{end+1} = sprintf('Threshold (last %d rev): %.3f', configuredReversals, threshold); %#ok<AGROW>
                        end
                    else
                        titleParts{end+1} = sprintf('Threshold: %.3f', threshold); %#ok<AGROW>
                    end
                end
            end

            hasTitle = ~isempty(titleParts);
            if hasTitle
                titleText = strjoin(titleParts, ' | ');
            else
                titleText = '';
            end
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






        function values = columnize(~, values)
            if isempty(values)
                values = nan;
            else
                values = values(:);
            end
        end
    end
end