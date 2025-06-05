classdef SlidingWindowPerformancePlot < handle

    properties (SetObservable)
        psychObj                  % Reference to main psychophysics object providing data

        window (1,1) {mustBePositive,mustBeInteger} = 20

        plotType (1,1) string {mustBeMember(plotType,["dPrime","HitRate","FARate","Bias"])} = "dPrime";

        palettename (1,1) string = "gem12"

        MarkerSize (1,1) {mustBePositive} = 10;
        Marker (1,1) char = '.'; % Allow user to set marker type

        LineStyle (1,:) char = 'none'; % Allow user to set line style

        % Add any other plot properties you want to expose here
        LineWidth (1,1) double = 1.5;
        Color % Optional: user can set a color or leave empty for default
    end
    
    properties (SetAccess = private)
        hAxes
        Data
        hl_NewData                       % Listener for data update events

        trialWindows
        HitRate
        FARate
        dPrime
        Bias

        trialBits
    end

    methods
    % SlidingWindowPerformancePlot Construct a SlidingWindowPerformancePlot object.
    %   OBJ = SlidingWindowPerformancePlot(POBJ, AX) creates a SlidingWindowPerformancePlot object
    %   associated with the given psychometric object POBJ and displays it in the
    %   specified (typically a UI figure or panel). 
    %
    %   Inputs:
    %       pObj      - (optional) Psychometric object to associate with the plot.
    %       ax        - (optional) axes
    %
    %   Outputs:
    %       obj       - Instance of the SlidingWindowPerformancePlot class.

        function obj = SlidingWindowPerformancePlot(pObj, ax)

            if nargin < 2 || isempty(ax), ax = gca; end
            
            obj.hAxes = ax;

            if nargin >= 1 && ~isempty(pObj), obj.psychObj = pObj; end


            obj.hl_NewData = listener(pObj.Helper,'NewData',@obj.update);

        end

        function delete(obj)
            % Destructor: cleans up the listener.
            try
                delete(obj.hl_NewData);
            end
        end


        function update(obj,src,event)
            obj.compute;
            obj.plot;
        end

        function plot(obj)
            %PLOT Plots the selected performance metric over trial windows.
            %   Plots d-prime, hit rate, false alarm rate, or bias as selected by
            %   obj.plotType, using the current trial windows and color palette.

            if isempty(obj.dPrime), return; end  % No data to plot

            P = obj.psychObj;

            cla(obj.hAxes);  % Clear axes

            % Prepare plot arguments
            plotArgs = { ...
                obj.hAxes, ...
                obj.trialWindows(:), ...
                obj.(obj.plotType), ...
                'Marker', obj.Marker, ...
                'MarkerSize', obj.MarkerSize, ...
                'LineStyle', obj.LineStyle, ...
                'LineWidth', obj.LineWidth ...
            };
            if ~isempty(obj.Color)
                plotArgs = [plotArgs, {'Color', obj.Color}];
            end

            % Plot the selected metric for each stimulus value
            plot(plotArgs{:});

            colororder(obj.hAxes, obj.palettename);  % Set color palette

            grid(obj.hAxes, 'on');  % Enable grid

            % Add legend for all but FARate (since it is not stimulus-specific)
            if obj.plotType ~= "FARate"
                luv = string(P.uniqueValues);
                legend(obj.hAxes, luv, ...
                    Location = "east")
            end

            % Set x-axis limits to cover all trial windows
            obj.hAxes.XLim = [0 obj.trialWindows(end) * 1.1];

            ylabel(obj.hAxes, obj.plotType)  % Y-axis label
            xlabel(obj.hAxes, 'trials')      % X-axis label
        end

        function compute(obj)
            %COMPUTE Calculates performance metrics over sliding trial windows.
            %   Computes hit rate, false alarm rate, d-prime, and bias for each
            %   window of trials, grouped by unique stimulus values.

            if isempty(obj.psychObj.DATA), return; end

            P = obj.psychObj;
            P.targetTrialType = epsych.BitMask.Undefined;

            uv = P.uniqueValues;           % Unique stimulus values
            vals = P.trialValues;          % Stimulus value for each trial
            
            RC = P.responseCodes;  % Response codes for all trials

            obj.trialBits = epsych.BitMask.Mask2Bits(RC); % Logical matrix of trial outcomes
            nTrials = size(obj.trialBits,1);

            bn = string(epsych.BitMask.list); % Bit names
            
            sttStim = string(P.ttStimulus);   % Name for stimulus trials
            sttCatch = string(P.ttCatch);     % Name for catch trials

            wvec = 1:nTrials-obj.window;      % Start indices for each window

            nStim = nan(length(wvec),length(uv)); % Number of stimulus trials per window/value
            nHit = nStim;                         % Number of hits per window/value

            nCatch = nan(size(wvec));             % Number of catch trials per window
            nFA = nCatch;                         % Number of false alarms per window

            iStim =  sttStim == bn;               % Index for stimulus trials in bitmask
            iCatch = sttCatch == bn;              % Index for catch trials in bitmask
            iHit = bn == "Hit";                   % Index for hit outcome in bitmask
            iFA = bn == "FalseAlarm";             % Index for false alarm outcome in bitmask

            k = 1;
            for w = wvec
                idx = w:w+obj.window-1;             % Indices for current window
                idx(idx>nTrials) = [];

                for i = 1:length(uv)
                    iv = intersect(idx,find(uv(i) == vals(:));  % Trials for this stimulus value
                    nStim(k,i) = sum(obj.trialBits(iv,iStim),1);         % Stimulus count
                    nHit(k,i)  = sum(obj.trialBits(iv,iStim & iHit),1);  % Hit count
                end

                nCatch(k) = sum(obj.trialBits(idx,iCatch),1);           % Catch count
                nFA(k)    = sum(obj.trialBits(idx,iFA),1);              % False alarm count
                k = k + 1;
            end

            obj.trialWindows = wvec;

            % Compute hit and false alarm rates
            obj.HitRate = nHit ./ nStim;
            obj.FARate = nFA ./ nCatch;

            % Compute d-prime
            obj.dPrime = obj.psychObj.d_prime(obj.HitRate,obj.FARate,obj.psychObj.infCorrection);

            % Compute bias
            obj.Bias = obj.psychObj.bias(obj.HitRate,obj.FARate,obj.psychObj.infCorrection);
            
        end

    end

end