classdef SlidingWindowPerformancePlot < handle

    properties (SetObservable)
        psychObj                  % Reference to main psychophysics object providing data

        plotType (1,1) string {mustBeMember(plotType,["dPrime","HitRate","FARate","Bias"])} = "dPrime";

        palettename (1,1) string = "gem12"

        MarkerSize (1,1) {mustBePositive} = 10;
        Marker (1,1) char = '.'; % Allow user to set marker type

        LineStyle (1,:) char = '-'; % Allow user to set line style

        % Add any other plot properties you want to expose here
        LineWidth (1,1) double = 1.5;
    end

    properties (SetAccess = private)
        hAxes
        hLines (:,1) matlab.graphics.primitive.Line
        
        Data
        hl_NewData                       % Listener for data update events


        plotValues

        trialBits

        N = struct( ...
            'Stimulus', [], ...    % Number of stimulus trials per window/value
            'Hit', [], ...         % Number of hits per window/value
            'Catch', [], ...       % Number of catch trials per window/value
            'FalseAlarm', [], ...  % Number of false alarms per window/value
            'Values', [], ...      % Stimulus values
            'TrialIdx', [] ...     % Index for the current trial
            )


        Rate = struct( ...
            'Hit', [], ...         % Hit rate per window/value
            'FalseAlarm', [] ...   % False alarm rate per window
            )

        dPrime = [];  % D-prime values per window/value
        Bias = [];    % Bias values per window/value
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

            obj.setup_plot;

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

        function setup_plot(obj)
            addArgs = {'Marker', obj.Marker, ...
                'MarkerSize', obj.MarkerSize, ...
                'LineStyle', obj.LineStyle, ...
                'LineWidth', obj.LineWidth};

            obj.hLines = line(obj.hAxes,nan,nan,addArgs{:});

            colororder(obj.hAxes, obj.palettename);  % Set color palette


            grid(obj.hAxes, 'on');
            box(obj.hAxes,'on');

            xlabel(obj.hAxes, 'trials')      % X-axis label
        end

        function plot(obj)
            %PLOT Plots the selected performance metric over trial windows.
            %   Plots d-prime, hit rate, false alarm rate, or bias as selected by
            %   obj.plotType, using the current trial windows and color palette.

            y = obj.(obj.plotType);
            if isempty(y), return; end  % No data to plot

            if isempty(obj.hLines) || ~isvalid(obj.hLines(1))
                obj.setup_plot;
            end
            
            x = [obj.N.TrialIdx]';

            n = size(y,2);
            if n > length(obj.hLines)
                k = n - length(obj.hLines);
                obj.hLines(end+1:n) = repmat(line(obj.hAxes,nan,nan),1,k);
            end

            for i = 1:n
                obj.hLines(i).XData = x;
                obj.hLines(i).YData = y(:,i);
                obj.hLines(i).DisplayName = string(obj.plotValues(i));
            end


            addArgs = {'Marker', obj.Marker, ...
                'MarkerSize', obj.MarkerSize, ...
                'LineStyle', obj.LineStyle, ...
                'LineWidth', obj.LineWidth};

            set(obj.hLines,addArgs{:})


            % Add legend for all but FARate (since it is not stimulus-specific)
            if obj.plotType ~= "FARate"
                h = legend(obj.hAxes, Location = "eastoutside");
                h.Title.String = obj.psychObj.Parameter.Name;
            end

            if obj.plotType == "dPrime"
                yline(obj.hAxes,1,'-k',HandleVisibility="off");
            end

            ylabel(obj.hAxes, obj.plotType)  % Y-axis label
        end

        function compute(obj)
            %COMPUTE Calculates performance metrics over sliding trial windows.
            %   Computes hit rate, false alarm rate, d-prime, and bias for each
            %   window of trials, grouped by unique stimulus values.

            if isempty(obj.psychObj.DATA), return; end

            P = obj.psychObj;
            P.targetTrialType = epsych.BitMask.Undefined;

            vals = P.trialValues;          % Stimulus value for each trial

            RC = P.responseCodes;  % Response codes for all trials

            if isempty(RC), return; end  % No response codes to process


            obj.trialBits = epsych.BitMask.Mask2Bits(RC); % Logical matrix of trial outcomes


            if isempty(obj.trialBits), return; end  % No valid trials to process

            % Get unique stimulus values
            idxCatch = uint32(P.ttCatch);
            i = obj.trialBits(:,idxCatch);
            valCatch = unique(vals(i));
            uv = unique(vals);
            uv(ismember(uv,valCatch)) = [];


            nStim = nan(1,length(uv)); % Number of stimulus trials per value
            nHit = nStim;              % Number of hits per value

            iStim  = uint32(P.ttStimulus);              % Index for stimulus trials in bitmask
            iCatch = uint32(P.ttCatch);                 % Index for catch trials in bitmask
            iHit   = uint32(epsych.BitMask.Hit);        % Index for hit outcome in bitmask
            iFA    = uint32(epsych.BitMask.FalseAlarm); % Index for false alarm outcome in bitmask

            tidx = P.trialIndex;  % Current trial index from psychObj

            idx = 1:tidx;
            for i = 1:length(uv)
                iv = intersect(idx,find(uv(i) == vals(:)));  % Trials for this stimulus value

                if isempty(iv), continue; end % Skip if no trials for this value

                sn = sum(obj.trialBits(iv,iStim),1);         % Stimulus count
                if ~isempty(sn), nStim(i) = sn; end

                sh = sum(obj.trialBits(iv,iStim & iHit),1);  % Hit count
                if ~isempty(sh), nHit(i) = sh; end
            end


            nCatch = sum(obj.trialBits(idx,iCatch),1);           % Catch count
            nFA    = sum(obj.trialBits(idx,iFA),1);              % False alarm count


            obj.N(tidx).Stimulus   = nStim;  % Store number of stimulus trials
            obj.N(tidx).Hit        = nHit;   % Store number of hits
            obj.N(tidx).Catch      = nCatch; % Store number of catch trials
            obj.N(tidx).FalseAlarm = nFA;    % Store number of false alarms
            obj.N(tidx).Values     = uv;     % Store unique values
            obj.N(tidx).TrialIdx   = tidx;   % Store current trial index

            nuv = unique([obj.N.Values]);
            obj.plotValues = nuv;

            if size(obj.Rate.Hit,2) < length(nuv)
                obj.Rate.Hit(:,end:length(nuv)) = nan;
            end
            
            ind = ismember(nuv,uv);
            
            HR = nHit ./ nStim;  % Hit rate for each stimulus value
            FAR = nFA ./ nCatch; % False alarm rate for the catch trials

            obj.Rate.Hit(tidx,ind) = HR;
            obj.Rate.FalseAlarm(tidx) = FAR;

            % Compute d-prime
            d = P.d_prime(HR,FAR,obj.P.infCorrection);
            i = isnan(HR);
            d(i) = nan;  % Set d-prime to NaN where Hit is NaN
            obj.dPrime(tidx,ind) = d;


            
            % Compute bias
            b = P.bias(obj.HitRate,FAR,obj.psychObj.infCorrection);
            i = isnan([obj.N.Hit]);
            b(i) = nan;  % Set bias to NaN where Hit is NaN
            obj.Bias(tidx,ind) = b;
        end


    end

end