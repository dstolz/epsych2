classdef SlidingWindowPerformancePlot < handle
    % SlidingWindowPerformancePlot - Live-updating performance plot for psychophysics data
    %
    %   This class visualizes behavioral performance metrics over time, based on
    %   trial-by-trial data from a connected psychophysics experiment object.
    %
    %   Metrics computed and plotted:
    %       - dPrime      : Sensitivity (signal detection theory)
    %       - HitRate     : Proportion of correct detections on stimulus trials
    %       - FARate      : False alarm rate on catch trials
    %       - Bias        : Response bias (criterion) estimate
    %
    %   The class supports plotting these metrics either cumulatively or over a
    %   fixed-size sliding window of recent trials.
    %
    %   Usage:
    %       obj = SlidingWindowPerformancePlot(pObj, ax);
    %
    %   Inputs:
    %       pObj - (optional) Psychophysics object providing trial data
    %       ax   - (optional) Axes object for plotting (default: gca)
    %
    %   Example:
    %       swp = SlidingWindowPerformancePlot(myPsychObj);
    %       swp.plotType = "HitRate";
    %       swp.windowSize = 50;  % Plot performance over last 50 trials
    %
    %   Note: This object attaches a listener to the psychObj's 'NewData' event
    %   and updates the plot automatically when new trials are added.

    properties (SetObservable)
        psychObj  % Reference to the main psychophysics object providing data

        plotType (1,1) string {mustBeMember(plotType,["dPrime","HitRate","FARate","Bias"])} = "dPrime";
        % Type of metric to plot. Options: 'dPrime', 'HitRate', 'FARate', 'Bias'

        palettename (1,1) string = "lines";  % Color palette for the lines

        MarkerSize (1,1) {mustBePositive} = 10;  % Marker size for plot points
        Marker (1,1) char = '.';               % Marker type (e.g. '.', 'o', etc.)

        LineStyle (1,:) char = ':';            % Line style for connecting points
        LineWidth (1,1) double = 1.5;          % Line width

        windowSize (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = 0;
        % Number of recent trials to include in each sliding window.
        %   If 0: Use cumulative data from start to current trial (default).
        %   If >0: Use only the last N trials as a sliding window.
    end

    properties (SetAccess = private)
        hAxes                               % Axes handle for plotting
        hLines %(:,1) matlab.graphics.primitive.Line  % Line object handles

        Data                                % Placeholder for future data struct
        hl_NewData                          % Listener for new data events

        plotValues                          % Unique stimulus values being plotted

        trialBits                           % Bitmask representation of trial outcomes

        % Struct for storing raw trial counts per value/window
        N = struct( ...
            'Stimulus', [], ...
            'Hit', [], ...
            'Catch', [], ...
            'FalseAlarm', [], ...
            'Values', [], ...
            'TrialIdx', [] ...
        );

        % Struct for storing computed rates
        Rate = struct( ...
            'Hit', [], ...
            'FalseAlarm', [] ...
        );

        dPrime = [];  % Matrix of d-prime values by trial
        Bias = [];    % Matrix of bias values by trial

        cm % colormap
    end

    methods
        % Constructor
        function obj = SlidingWindowPerformancePlot(pObj, ax)
            % Constructs the SlidingWindowPerformancePlot object and sets up plot.
            %
            %   Inputs:
            %       pObj - Psychometric object (optional)
            %       ax   - Axes for plotting (optional; defaults to gca)

            if nargin < 2 || isempty(ax), ax = gca; end
            obj.hAxes = ax;

            if nargin >= 1 && ~isempty(pObj), obj.psychObj = pObj; end

            obj.setup_plot;

            % Listen for new trial data
            obj.hl_NewData = listener(pObj.Helper, 'NewData', @obj.update);
        end

        function delete(obj)
            % Destructor: cleans up the data listener
            try
                delete(obj.hl_NewData);
            end
        end

        function update(obj, src, event)
            % Called automatically when new data arrives
            obj.compute;
            obj.plot;
        end

        function setup_plot(obj)
            % Initializes the plot with default line styles and appearance

            obj.cm = colormap(obj.palettename);

            % obj.hLines = matlab.graphics.primitive.Line;
            obj.hLines = [];
            
            grid(obj.hAxes, 'on');
            box(obj.hAxes, 'on');
            xlabel(obj.hAxes, 'Trials');


            % Add legend unless plotting non-stimulus-specific metric
            if obj.plotType == "FARate"
                legend(obj.hAxes, 'off');
            else
                h = legend(obj.hAxes, Location = "eastoutside");
                h.Title.String = obj.psychObj.Parameter.Name;
            end
        end

        function plot(obj)
            % Plots the selected performance metric across trials.
            % Automatically updates line objects for each unique stimulus value.

            vprintf(4, 'Plotting psychometric data');

            y = obj.(obj.plotType);
            if isempty(y), return; end  % No data yet

            % if isempty(obj.hLines) || ~isvalid(obj.hLines(1))
            %     obj.setup_plot;
            % end

            x = [obj.N.TrialIdx]'; % X-axis: Trial indices
            nStim = size(y, 2);  % Number of stimulus values


            if nStim > length(obj.hLines)  % Add new line objects if needed
                for i = length(obj.hLines)+1:nStim
                    obj.hLines(i) = line(obj.hAxes, nan, nan, ...
                        Color = obj.cm(i,:), ...
                        UserData = obj.plotValues(i)); 
                end
            end

            % Update existing lines
            % Map plot values to line handles
            ud = get(obj.hLines,'UserData');
            if iscell(ud), ud = cell2mat(ud); end
            for i = 1:nStim
                ind = obj.plotValues == ud(i);
                set(obj.hLines(ind),XData = x,YData = y(:,i),DisplayName = string(ud(i)));
            end

            % Update appearance
            addArgs = {'Marker', obj.Marker, ...
                       'MarkerSize', obj.MarkerSize, ...
                       'LineStyle', obj.LineStyle, ...
                       'LineWidth', obj.LineWidth};
            set(obj.hLines, addArgs{:});


            % Add reference line for d' = 1
            if obj.plotType == "dPrime"
                yline(obj.hAxes, 1, '--k', HandleVisibility = "off");
            end

            ylabel(obj.hAxes, obj.plotType);
        end

        function compute(obj)
            % Computes performance metrics based on the sliding or cumulative window.
            %
            %   This function calculates hit rate, false alarm rate, d-prime,
            %   and bias for the most recent trials based on `windowSize`.
            %
            %   If windowSize == 0:
            %       - Uses all trials from the beginning (cumulative).
            %   If windowSize > 0:
            %       - Uses only the last N trials up to the current trial index.

            if isempty(obj.psychObj.DATA), return; end
            vprintf(4, 'Computing psychometric data');

            P = obj.psychObj;
            P.targetTrialType = epsych.BitMask.Undefined;

            vals = P.trialValues;
            RC = P.responseCodes;
            if isempty(RC), return; end

            obj.trialBits = epsych.BitMask.Mask2Bits(RC);
            if isempty(obj.trialBits), return; end

            idxCatch = uint32(P.ttCatch);
            isCatch = obj.trialBits(:, idxCatch);
            valCatch = unique(vals(isCatch));
            uv = unique(vals,'stable');
            uv(ismember(uv, valCatch)) = [];  % Exclude catch-only values

            nStim = nan(1, length(uv));
            nHit = nStim;

            iStim  = uint32(P.ttStimulus);
            iCatch = uint32(P.ttCatch);
            iHit   = uint32(epsych.BitMask.Hit);
            iFA    = uint32(epsych.BitMask.FalseAlarm);

            tidx = P.trialIndex;

            % === SLIDING OR CUMULATIVE WINDOW ===
            if obj.windowSize == 0
                idx = 1:tidx;  % Cumulative
            else
                idx = max(tidx - obj.windowSize + 1, 1):tidx;  % Sliding
            end

            for i = 1:length(uv)
                iv = intersect(idx, find(uv(i) == vals(:)));

                if isempty(iv), continue; end

                sn = sum(obj.trialBits(iv, iStim), 1);
                if ~isempty(sn), nStim(i) = sn; end

                sh = sum(obj.trialBits(iv, iStim & iHit), 1);
                if ~isempty(sh), nHit(i) = sh; end
            end

            nCatch = sum(obj.trialBits(idx, iCatch), 1);
            nFA = sum(obj.trialBits(idx, iFA), 1);

            obj.N(tidx).Stimulus   = nStim;
            obj.N(tidx).Hit        = nHit;
            obj.N(tidx).Catch      = nCatch;
            obj.N(tidx).FalseAlarm = nFA;
            obj.N(tidx).Values     = uv;
            obj.N(tidx).TrialIdx   = tidx;

            nuv = unique([obj.N.Values],'stable');
            obj.plotValues = nuv;

            if isempty(obj.Rate.Hit), obj.Rate.Hit = nan; end

            if size(obj.Rate.Hit,2) < length(nuv)
                obj.Rate.Hit(:,end:length(nuv)) = nan;
            end

            ind = ismember(nuv, uv);

            HR = nHit ./ nStim;
            FAR = nFA ./ nCatch;

            obj.Rate.Hit(tidx, ind) = HR;
            obj.Rate.FalseAlarm(tidx) = FAR;

            d = P.d_prime(HR, FAR, P.infCorrection);
            d(isnan(HR)) = nan;
            obj.dPrime(tidx, ind) = d;

            % Optional: Bias computation (currently disabled)
            b = P.bias(obj.Rate.Hit, FAR, obj.psychObj.infCorrection);
            b(isnan([obj.N.Hit])) = nan;
            % obj.Bias(tidx, ind) = b;
        end
    end
end
