classdef Detect < handle & matlab.mixin.SetGet
    % Detect   Class for analyzing psychophysical detection task data
    %
    %   The Detect class processes trial data from psychophysical experiments,
    %   decoding trial outcomes and computing performance metrics such as
    %   d-prime and bias. It utilizes information from the TRIALS structure
    %   and associated parameters to extract and analyze relevant trial data.
    %
    %   Detect Properties:
    %       TRIALS          - Structure containing trial data (RUNTIME.TRIALS)
    %       Parameter       - Parameter object defining trial parameters (hw.Parameter)
    %       infCorrection   - Correction bounds for infinite z-scores [lower upper]
    %       targetTrialType - Target trial type to analyze (epsych.BitMask)
    %
    %   Detect Dependent Properties:
    %       DATA            - Extracted trial data from TRIALS
    %       trialCount      - Number of trials matching targetTrialType
    %       trialType       - Array of trial types from DATA
    %       trialValues     - Parameter values for targetTrialType trials
    %       uniqueValues    - Unique parameter values in trialValues
    %       Count           - Struct with counts of trial outcomes (Hit, Miss, etc.)
    %       Rate            - Struct with rates of trial outcomes
    %       DPrime          - Computed d-prime values
    %       Bias            - Computed bias values
    %
    %   Detect Methods:
    %       Detect          - Constructor to initialize the class
    %       d_prime         - Static method to compute d-prime
    %       bias            - Static method to compute bias
    %       norminv         - Static method for bounded inverse normal transformation

    properties (SetObservable)
        % TRIALS - Structure containing trial data (RUNTIME.TRIALS)
        TRIALS

        % Parameter - Parameter object defining trial parameters (hw.Parameter)
        Parameter (1,1)

        % infCorrection - Correction bounds for infinite z-scores [lower upper]
        % Ensures that hit and false alarm rates are within (0,1) exclusive
        infCorrection (1,2) double {mustBeInRange(infCorrection,0,1,"exclusive")} = [0.01 0.99];

        % targetTrialType - Target trial type to analyze (epsych.BitMask)
        targetTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
        % targetTrialType (1,1) = 0; % SHOULD BE BITMASK, but isn't yet

        Bits (1,:) epsych.BitMask = epsych.BitMask.getResponses;
        BitColors (5,1) string = ["#dff7df","#fcdcdc","#d9f2ff","#fcdefc","#fcfcd4"];

        



        Helper = epsych.Helper
    end

    properties (Dependent)
        % DATA - Extracted trial data from TRIALS
        DATA

        % trialCount - Number of trials matching targetTrialType
        trialCount

        % trialType - Array of trial types from DATA
        trialType

        % trialValues - Parameter values for targetTrialType trials
        trialValues

        % uniqueValues - Unique parameter values in trialValues
        uniqueValues


        countUniqueValues

        % Count - Struct with counts of trial outcomes (Hit, Miss, etc.)
        Count

        % Rate - Struct with rates of trial outcomes (Hit, Miss, etc.)
        Rate

        % DPrime - Computed d-prime values
        DPrime

        % Bias - Computed bias values
        Bias


    end

    properties (SetAccess = protected)
        % decodedTrials - Decoded trial outcomes from psychophysics.decodeTrials
        decodedTrials
    end

    properties (Access = private)
        hl_NewData
    end

    methods
        function obj = Detect(TRIALS, Parameter, targetTrialType)
            % Detect Constructor to initialize the Detect class
            %
            %   obj = Detect(TRIALS, Parameter, targetTrialType) initializes
            %   the Detect object with the provided TRIALS structure,
            %   Parameter object, and targetTrialType. It also decodes the
            %   trial outcomes using psychophysics.decodeTrials.
            %
            %   Inputs:
            %       TRIALS          - Structure containing trial data
            %       Parameter       - Parameter object defining trial parameters
            %       targetTrialType - Target trial type to analyze
            %
            %   Outputs:
            %       obj - Initialized Detect object

            global RUNTIME

            if nargin >= 1 && ~isempty(TRIALS)
                obj.TRIALS = TRIALS;
            end
            if nargin >= 2 && ~isempty(Parameter)
                obj.Parameter = Parameter;
            end
            if nargin == 3 && ~isempty(targetTrialType)
                obj.targetTrialType = targetTrialType;
            end

            addlistener(RUNTIME.HELPER,'NewData',@obj.update_data);
        end


        function update_data(obj,src,event)
            obj.TRIALS = event.Data;
            vprintf(4,'psychophysics.Detect.update_data: Trial %d',obj.TRIALS.TrialIndex)
            obj.decodedTrials = psychophysics.decodeTrials(obj.TRIALS,obj.Parameter);
            evtdata = epsych.TrialsData(obj.TRIALS);
            obj.Helper.notify('NewData',evtdata);
        end



        function d = get.DATA(obj)
            % get.DATA Extracts trial data from TRIALS
            %
            %   d = obj.DATA returns the DATA field from the TRIALS structure.
            if isempty(obj.TRIALS)
                d = [];
            else
                d = obj.TRIALS.DATA;
            end
        end

        function tt = get.trialType(obj)
            % get.trialType Retrieves trial types from DATA
            %
            %   tt = obj.trialType returns an array of trial types extracted
            %   from the DATA structure.
            if isempty(obj.DATA)
                tt = [];
            else
                tt = [obj.DATA.TrialType];
                % convert number to BitMask
                tts = "TrialType_" + tt;
                tt = epsych.BitMask(tts);
            end
        end

        function n = get.trialCount(obj)
            % get.trialCount Counts trials matching targetTrialType
            %
            %   n = obj.trialCount returns the number of trials in DATA that
            %   match the specified targetTrialType.

            n = sum(obj.trialType == obj.targetTrialType);
        end

        function v = get.trialValues(obj)
            % get.trialValues Retrieves parameter values for targetTrialType
            %
            %   v = obj.trialValues returns the values of the parameter
            %   specified in obj.Parameter.validName for trials matching
            %   the targetTrialType.

            ind = obj.trialType == obj.targetTrialType;
            if any(ind)
                v = [obj.DATA.(obj.Parameter.validName)];
                v = v(ind);
            else
                v = [];
            end
        end

        function uv = get.uniqueValues(obj)
            % get.uniqueValues Identifies unique parameter values
            %
            %   uv = obj.uniqueValues returns the unique values present in
            %   obj.trialValues.

            uv = unique(obj.trialValues);
        end


        function n = get.countUniqueValues(obj)
            n = arrayfun(@(a) sum(obj.trialValues==a),obj.uniqueValues);
        end

        function c = get.Count(obj)
            % get.Count Computes counts of trial outcomes
            %
            %   c = obj.Count returns a struct array where each element
            %   corresponds to a unique parameter value and contains fields
            %   such as Hit, Miss, etc., representing the count of each
            %   outcome type.

           
            tv = obj.trialValues;
            uv = obj.uniqueValues;
            bm = epsych.BitMask.getDefined;
            x = [cellstr(bm), cell(size(bm))]';
            c = struct(x{:});
            c = repmat(c,length(uv),1);

            if isempty(c), return; end

            M = obj.decodedTrials.M;
            ind = obj.trialType == obj.targetTrialType;
            M = structfun(@(a) a(ind),M,'uni',0);
            for i = 1:length(uv)
                ind = uv(i) == tv;
                c(i) = structfun(@(a) sum(a(ind)), M, 'uni', 0);
            end
        end

        function r = get.Rate(obj)
            % get.Rate Computes rates of trial outcomes
            %
            %   r = obj.Rate returns a struct array where each element
            %   corresponds to a unique parameter value and contains fields
            %   representing the rate (proportion) of each outcome type.

            
            c = obj.Count;
            n = obj.countUniqueValues;

            bm = epsych.BitMask.getDefined;
            x = [cellstr(bm), cell(size(bm))]';
            r = struct(x{:});

            if isempty(c), return; end

            r = repmat(r,length(c),1);

            for i = 1:length(c)
                r(i) = structfun(@(a) a./n(i), c(i), 'uni', 0);
            end
        end

        function d = get.DPrime(obj)
            % get.DPrime Computes d-prime values
            %
            %   d = obj.DPrime returns the d-prime values computed from the
            %   Hit and FalseAlarm rates using the specified infCorrection
            %   bounds.

            r = obj.Rate;
            d = nan(size(r));
            if isempty(r(1).Hit), return; end
            for i = 1:numel(r)
                d(i) = psychophysics.Detect.d_prime(r(i).Hit, r(i).FalseAlarm, obj.infCorrection);
            end
        end

        function c = get.Bias(obj)
            % get.Bias Computes bias values
            %
            %   c = obj.Bias returns the bias values computed from the Hit
            %   and FalseAlarm rates using the specified infCorrection bounds.

            r = obj.Rate;
            c = psychophysics.Detect.bias(r.Hit, r.FalseAlarm, obj.infCorrection);
        end






    end

    methods (Static)
        function d = d_prime(hitRate, faRate, bounds)
            % d_prime Computes d-prime from hit and false alarm rates
            %
            %   d = d_prime(hitRate, faRate, bounds) computes the d-prime
            %   value using the provided hitRate and faRate, applying the
            %   specified bounds to avoid infinite z-scores.
            %
            %   Inputs:
            %       hitRate - Hit rate(s)
            %       faRate  - False alarm rate(s)
            %       bounds  - [lower upper] bounds for rate correction
            %
            %   Output:
            %       d - Computed d-prime value(s)

            arguments
                hitRate
                faRate
                bounds (1,2) double {mustBeInRange(bounds,0,1,"exclusive")} = [0.01 0.99]
            end
            d = psychophysics.Detect.norminv(hitRate, bounds) - psychophysics.Detect.norminv(faRate, bounds);
        end

        function c = bias(hitRate, faRate, bounds)
            % bias Computes bias from hit and false alarm rates
            %
            %   c = bias(hitRate, faRate, bounds) computes the bias value
            %   using the provided hitRate and faRate, applying the specified
            %   bounds to avoid infinite z-scores.
            %
            %   Inputs:
            %       hitRate - Hit rate(s)
            %       faRate  - False alarm rate(s)
            %       bounds  - [lower upper] bounds for rate correction
            %
            %   Output:
            %       c - Computed bias value(s)

            arguments
                hitRate
                faRate
                bounds (1,2) double {mustBeInRange(bounds,0,1,"exclusive")} = [0.01 0.99]
            end
            h = psychophysics.Detect.norminv(hitRate, bounds);
            f = psychophysics.Detect.norminv(faRate, bounds);
            c = -(h + f) ./ 2;
        end

        function n = norminv(r,bounds)
            arguments
                r
                bounds (1,2) double {mustBeInRange(bounds,0,1,"exclusive")} = [0.01 0.99]
            end
            r = max(min(r,bounds(2)),bounds(1));
            n = norminv(r);
        end
    end
end