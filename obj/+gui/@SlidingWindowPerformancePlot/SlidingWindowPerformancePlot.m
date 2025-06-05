classdef SlidingWindowPerformancePlot < handle

    properties (SetObservable)
        psychObj                  % Reference to main psychophysics object providing data

        window (1,1) {mustBePositive,mustBeInteger} = 20

        plotType (1,1) string {mustBeMember(plotType,["dPrime","HitRate","FARate","Bias"])} = "dPrime";

        palettename (1,1) string = "gem12"

        MarkerSize (1,1) {mustBePositive} = 10;
        Marker (1,1) char = '.'; % Allow user to set marker type

        LineStyle (1,:) char = '-'; % Allow user to set line style

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
        plotValues

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
            box(obj.hAxes,'on');

            % Add legend for all but FARate (since it is not stimulus-specific)
            if obj.plotType ~= "FARate"
                luv = string(obj.plotValues);
                h = legend(obj.hAxes, luv, ...
                    Location = "eastoutside");
                h.Title.String = obj.psychObj.Parameter.Name;
            end

            if obj.plotType == "dPrime"
                yline(obj.hAxes,1,'-k',HandleVisibility="off");
            end

            % Set x-axis limits to cover all trial windows
            obj.hAxes.XLim = [0 obj.trialWindows(end)];

            ylabel(obj.hAxes, obj.plotType)  % Y-axis label
            xlabel(obj.hAxes, 'trials')      % X-axis label
        end

        function compute(obj)
            %COMPUTE Calculates performance metrics over sliding trial windows.
            %   Computes hit rate, false alarm rate, d-prime, and bias for each
            %   window of trials, grouped by unique stimulus values.

            if isempty(obj.psychObj.DATA), return; end
            tic

            P = obj.psychObj;
            P.targetTrialType = epsych.BitMask.Undefined;

            vals = P.trialValues;          % Stimulus value for each trial
            
            RC = P.responseCodes;  % Response codes for all trials
            

            obj.trialBits = epsych.BitMask.Mask2Bits(RC); % Logical matrix of trial outcomes


            

            nTrials = size(obj.trialBits,1);

            bn = string(epsych.BitMask.list); % Bit names
            

            idxCatch = uint32(P.ttCatch);
            i = obj.trialBits(:,idxCatch);
            valCatch = unique(vals(i));
            uv = unique(vals);
            uv(ismember(uv,valCatch)) = [];

            wvec = 1:nTrials;      % Start indices for each window

            nStim = nan(length(wvec),length(uv)); % Number of stimulus trials per window/value
            nHit = nStim;                         % Number of hits per window/value

            nCatch = nan(size(wvec));             % Number of catch trials per window
            nFA = nCatch;                         % Number of false alarms per window

            iStim =  uint32(P.ttStimulus);               % Index for stimulus trials in bitmask
            iCatch = uint32(P.ttCatch);              % Index for catch trials in bitmask
            iHit = uint32(epsych.BitMask.Hit);                   % Index for hit outcome in bitmask
            iFA = uint32(epsych.BitMask.FalseAlarm);             % Index for false alarm outcome in bitmask

            k = 1;
            for w = wvec
                idx = 1:w;             % Indices for current window

                for i = 1:length(uv)
                    iv = intersect(idx,find(uv(i) == vals(:)));  % Trials for this stimulus value
                    if isempty(iv), continue; end
                    sn = sum(obj.trialBits(iv,iStim),1);         % Stimulus count
                    if ~isempty(sn), nStim(k,i) = sn; end
                    sh = sum(obj.trialBits(iv,iStim & iHit),1);  % Hit count
                    if ~isempty(sh), nHit(k,i) = sh; end
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
            FAR = repmat(obj.FARate(:),1,length(uv));
            obj.dPrime = obj.psychObj.d_prime(obj.HitRate,FAR,obj.psychObj.infCorrection);

            % Compute bias
            obj.Bias = obj.psychObj.bias(obj.HitRate,FAR,obj.psychObj.infCorrection);
            

            i = isnan(obj.HitRate);
            obj.dPrime(i) = nan;
            obj.Bias(i) = nan;

            obj.plotValues = uv;

            toc
        end

    end

end