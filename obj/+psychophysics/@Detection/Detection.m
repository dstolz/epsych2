classdef Detection < handle & matlab.mixin.SetGet
    % Detection   Class for analyzing psychophysical detection task data
    %
    %   Processes trial data from a running session (RUNTIME.TRIALS), decoding
    %   trial outcome bitmasks and computing signal detection metrics (hit and
    %   false alarm rates, d-prime, bias) grouped by unique stimulus values.
    %
    %   Detection Properties:
    %       TRIALS          - Structure containing trial data (RUNTIME.TRIALS)
    %       Parameter       - Parameter object defining trial parameters (hw.Parameter)
    %       infCorrection   - Correction bounds for infinite z-scores [lower upper]
    %       targetTrialType - Target trial type to analyze (epsych.BitMask)
    %       ttStimulus      - Trial type representing stimulus trials
    %       ttCatch         - Trial type representing catch trials
    %
    %   Detection Dependent Properties:
    %       DATA            - Extracted trial data from TRIALS
    %       trialValues     - Parameter values for targetTrialType trials
    %       uniqueValues    - Unique parameter values in trialValues
    %       Count           - Struct with counts of trial outcomes per unique value
    %       Rate            - Struct with rates of trial outcomes per unique value
    %       DPrime          - d-prime per unique stimulus value (catch-trial FAR)
    %       Bias            - Response bias per unique stimulus value
    %       Hit_Rate        - Hit rate per unique stimulus value
    %       FA_Rate         - Catch-trial false alarm rate (replicated per value)
    %
    %   Detection Methods:
    %       Detection       - Constructor to initialize the class
    %       d_prime         - Static method to compute d-prime
    %       bias            - Static method to compute bias
    %       norminv         - Static method for bounded inverse normal transformation
    %
    %   Used by gui.PsychPlot, gui.Performance, and gui.SlidingWindowPerformancePlot.

    properties (SetObservable)
        % TRIALS - Structure containing trial data (RUNTIME.TRIALS)
        TRIALS

        % Parameter - Parameter object defining trial parameters (hw.Parameter)
        Parameter (1,1)

        % infCorrection - Correction bounds for infinite z-scores [lower upper]
        % Ensures that hit and false alarm rates are within (0,1) exclusive
        infCorrection (1,2) double {mustBeInRange(infCorrection,0,1,"exclusive")} = [0.05 0.95];

        % targetTrialType - Target trial type to analyze (epsych.BitMask)
        targetTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0

        ttStimulus (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
        ttCatch    (1,1) epsych.BitMask = epsych.BitMask.TrialType_1

        BitsInUse (1,:) epsych.BitMask = epsych.BitMask.getResponses % [Hit Miss CR FA Abort]
        BitColors (5,1) string = ["#dff7df","#fcdcdc","#d9f2ff","#fcdefc","#fcfcd4"];
    end

    properties (SetAccess = private)
        % Helper - Global helper object for event handling
        Helper = epsych.Helper

        % M - Logical arrays for each decoded bitmask flag
        M
        % N - Counts of each decoded bitmask flag
        N

        RUNTIME
    end

    properties (Dependent)
        % DATA - Extracted trial data from TRIALS
        DATA

        % responseCodes - Response codes from TRIALS.DATA
        responseCodes (1,:) uint32

        % trialIndex - Current trial index from TRIALS
        trialIndex

        % trialCount - Number of trials matching targetTrialType
        trialCount

        % trialTypes - Trial types from DATA as epsych.BitMask values
        trialTypes

        % trialValues - Parameter values for targetTrialType trials
        trialValues

        % uniqueValues - Unique parameter values in trialValues
        uniqueValues

        % countUniqueValues - Counts of unique parameter values in trialValues
        countUniqueValues

        % Count - Struct with counts of trial outcomes (Hit, Miss, etc.)
        Count

        % Rate - Struct with rates of trial outcomes (Hit, Miss, etc.)
        Rate

        % DPrime - d-prime per unique stimulus value
        DPrime      (1,:) double

        % Bias - Response bias per unique stimulus value
        Bias        (1,:) double

        Hit_Rate    (1,:) double
        Miss_Rate   (1,:) double
        FA_Rate     (1,:) double
        CR_Rate     (1,:) double

        Hit_Ind     (1,:) logical
        Miss_Ind    (1,:) logical
        FA_Ind      (1,:) logical
        CR_Ind      (1,:) logical

        % TrialType - Numeric trial types from DATA
        TrialType   (1,:) double

        NumTrials   (1,1) uint16
        Trial_Index (1,1) double

        ResponsesEnum (1,:) epsych.BitMask
        ResponsesChar (1,:) cell

        ValidParameters (1,:) cell

        % ParameterName - Name of the analyzed parameter; settable to any
        % member of ValidParameters to change the independent variable
        ParameterName (1,:) char

        % ParameterValues - Alias for uniqueValues (used by gui.PsychPlot)
        ParameterValues (1,:)

        SUBJECT
    end

    properties (Access = private)
        hl_NewData

        % ParameterName_ - Optional override of the analyzed DATA field
        ParameterName_ (1,:) char = ''
    end

    methods
        function obj = Detection(RUNTIME, Parameter, targetTrialType)
            % Detection Constructor to initialize the Detection class
            %
            %   obj = Detection(RUNTIME, Parameter, targetTrialType)
            %
            %   Inputs:
            %       RUNTIME         - Runtime structure containing trial data
            %       Parameter       - Parameter object defining trial parameters
            %       targetTrialType - Target trial type to analyze
            arguments
                RUNTIME
                Parameter (1,1)  %hw.Parameter
                targetTrialType (1,1) epsych.BitMask = epsych.BitMask.Undefined
            end

            obj.RUNTIME = RUNTIME;
            obj.Parameter = Parameter;
            obj.targetTrialType = targetTrialType;

            obj.hl_NewData = addlistener(RUNTIME.HELPER,'NewData',@obj.update_data);
        end

        function delete(obj)
            % Destructor: cleans up the listener.
            try
                delete(obj.hl_NewData);
            catch ME
                vprintf(0,1,ME);
            end
        end

        function update_data(obj,~,event)
            obj.TRIALS = event.Data;
            vprintf(4,'psychophysics.Detection.update_data: Trial %d',obj.TRIALS.TrialIndex)
            % Decode response codes into M and N
            % M contains logical arrays for each bitmask flag
            % N contains counts of each bitmask flag
            [obj.M,obj.N] = epsych.BitMask.decode(obj.responseCodes);
            evtdata = epsych.TrialsData(obj.TRIALS);
            obj.Helper.notify('NewData',evtdata);
        end



        function d = get.DATA(obj)
            % get.DATA Extracts trial data from TRIALS
            if isempty(obj.TRIALS)
                d = [];
            else
                d = obj.TRIALS.DATA;
                if isempty(d), return; end
                fn = fieldnames(d);
                for i = 1:numel(d)
                    for j = 1:numel(fn)
                        p = d(i).(fn{j});
                        d(i).(fn{j}) = [p.Value];
                    end
                end
            end
        end

        function ti = get.trialIndex(obj)
            % get.trialIndex Retrieves the current trial index
            if isempty(obj.TRIALS)
                ti = [];
            else
                ti = obj.TRIALS.TrialIndex;
            end
        end

        function i = get.Trial_Index(obj)
            if isempty(obj.TRIALS)
                i = 1;
            else
                i = obj.TRIALS.TrialIndex;
            end
        end

        function rc = get.responseCodes(obj)
            % get.responseCodes Retrieves response codes from DATA
            if isempty(obj.DATA)
                rc = uint32([]);
            elseif isfield(obj.DATA, 'RespCode')
                rc = uint32([obj.DATA.RespCode]);
            else
                rc = uint32([]);
            end
        end

        function r = get.ResponsesEnum(obj)
            r = epsych.BitMask.Mask2Bits(obj.responseCodes);
        end

        function c = get.ResponsesChar(obj)
            [~,b] = epsych.BitMask.Mask2Bits(obj.responseCodes);
            c = cellfun(@cellstr,b,'uni',0);
        end

        function tt = get.TrialType(obj)
            if isempty(obj.DATA)
                tt = [];
            else
                tt = [obj.DATA.TrialType];
            end
        end

        function tt = get.trialTypes(obj)
            % get.trialTypes Trial types from DATA as epsych.BitMask values
            if isempty(obj.DATA)
                tt = [];
            else
                tt = epsych.BitMask("TrialType_" + [obj.DATA.TrialType]);
            end
        end

        function n = get.trialCount(obj)
            % get.trialCount Counts trials matching targetTrialType
            if obj.targetTrialType == epsych.BitMask.Undefined
                n = length(obj.trialTypes);
            else
                n = sum(obj.trialTypes == obj.targetTrialType);
            end
        end

        function n = get.NumTrials(obj)
            n = length(obj.DATA);
        end

        function v = get.trialValues(obj)
            % get.trialValues Retrieves parameter values for targetTrialType
            if obj.targetTrialType == epsych.BitMask.Undefined
                ind = true(size(obj.trialTypes));
            else
                ind = obj.trialTypes == obj.targetTrialType;
            end
            if any(ind)
                v = [obj.DATA.(obj.parameterField)];
                v = v(ind);
            else
                v = [];
            end
        end

        function uv = get.uniqueValues(obj)
            % get.uniqueValues Identifies unique parameter values
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

            M_ = obj.M;
            if obj.targetTrialType ~= epsych.BitMask.Undefined
                ind = obj.trialTypes == obj.targetTrialType;
                M_ = structfun(@(a) a(ind),M_,'uni',0);
            end
            for i = 1:length(uv)
                ind = uv(i) == tv;
                c(i) = structfun(@(a) sum(a(ind)), M_, 'uni', 0);
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

        % Ind ------------------------------------------------------
        function r = get.Hit_Ind(obj)
            r = logical(bitget(obj.responseCodes,epsych.BitMask.Hit));
        end

        function r = get.Miss_Ind(obj)
            r = logical(bitget(obj.responseCodes,epsych.BitMask.Miss));
        end

        function r = get.FA_Ind(obj)
            r = logical(bitget(obj.responseCodes,epsych.BitMask.FalseAlarm));
        end

        function r = get.CR_Ind(obj)
            r = logical(bitget(obj.responseCodes,epsych.BitMask.CorrectReject));
        end

        % Rate ----------------------------------------------------
        function r = get.Hit_Rate(obj)
            % get.Hit_Rate Hit rate per unique stimulus value
            obj.targetTrialType = obj.ttStimulus;
            r = [obj.Rate.Hit];
        end

        function r = get.Miss_Rate(obj)
            r = 1 - obj.Hit_Rate;
        end

        function r = get.FA_Rate(obj)
            % get.FA_Rate Catch-trial false alarm rate, replicated to match
            % the number of unique stimulus values for plotting
            obj.targetTrialType = obj.ttCatch;
            CT = obj.Rate;
            far = CT(1).FalseAlarm;

            obj.targetTrialType = obj.ttStimulus;
            n = max(numel(obj.uniqueValues),1);
            if isempty(far)
                r = nan(1,n);
            else
                r = repmat(far,1,n);
            end
        end

        function r = get.CR_Rate(obj)
            r = 1 - obj.FA_Rate;
        end

        function d = get.DPrime(obj)
            % get.DPrime d-prime per unique stimulus value
            %
            %   Computed from the Hit rate at each unique stimulus value and
            %   the overall catch-trial FalseAlarm rate, using the specified
            %   infCorrection bounds.

            obj.targetTrialType = obj.ttCatch;
            % this is kludgy and should be reworked
            CT = obj.Rate;
            FAR = CT(1).FalseAlarm;

            obj.targetTrialType = obj.ttStimulus;
            r = obj.Rate;
            d = nan(size(r));
            if isempty(r(1).Hit), return; end
            for i = 1:numel(r)
                x = psychophysics.Detection.d_prime(r(i).Hit, FAR, obj.infCorrection);
                if isempty(x), x = inf; end
                d(i) = x;
            end
        end

        function c = get.Bias(obj)
            % get.Bias Response bias per unique stimulus value
            obj.targetTrialType = obj.ttCatch;
            CT = obj.Rate;

            obj.targetTrialType = obj.ttStimulus;
            r = obj.Rate;
            c = psychophysics.Detection.bias([r.Hit], CT(1).FalseAlarm, obj.infCorrection);
        end

        % Parameter -------------------------------------------------
        function p = get.ValidParameters(obj)
            if isempty(obj.TRIALS)
                p = [];
            else
                p = fieldnames(obj.DATA);
                p(~ismember(p,obj.TRIALS.writeparams)) = [];
            end
        end

        function n = get.ParameterName(obj)
            if isempty(obj.ParameterName_)
                n = obj.Parameter.Name;
            else
                n = obj.ParameterName_;
            end
        end

        function set.ParameterName(obj,n)
            vp = obj.ValidParameters;
            assert(isempty(vp) || ismember(n,vp), ...
                'psychophysics:Detection:invalidParameter', ...
                '"%s" is not a member of ValidParameters',n);
            obj.ParameterName_ = n;
        end

        function v = get.ParameterValues(obj)
            v = obj.uniqueValues;
        end

        function s = get.SUBJECT(obj)
            if isempty(obj.TRIALS)
                s = [];
            else
                s = obj.TRIALS.Subject;
            end
        end
    end

    methods (Access = private)
        function n = parameterField(obj)
            % DATA field name of the analyzed parameter
            if isempty(obj.ParameterName_)
                n = obj.Parameter.validName;
            else
                n = obj.ParameterName_;
            end
        end
    end

    methods (Static)
        function d = d_prime(hitRate, faRate, bounds)
            % d_prime Computes d-prime from hit and false alarm rates
            %
            %   d = d_prime(hitRate, faRate, bounds) computes the d-prime
            %   value using the provided hitRate and faRate, applying the
            %   specified bounds to avoid infinite z-scores.

            arguments
                hitRate
                faRate
                bounds (1,2) double {mustBeInRange(bounds,0,1,"exclusive")} = [0.01 0.99]
            end
            d = psychophysics.Detection.norminv(hitRate, bounds) - psychophysics.Detection.norminv(faRate, bounds);
        end

        function c = bias(hitRate, faRate, bounds)
            % bias Computes bias (criterion) from hit and false alarm rates
            %
            %   c = bias(hitRate, faRate, bounds) computes the bias value
            %   using the provided hitRate and faRate, applying the specified
            %   bounds to avoid infinite z-scores.

            arguments
                hitRate
                faRate
                bounds (1,2) double {mustBeInRange(bounds,0,1,"exclusive")} = [0.01 0.99]
            end
            h = psychophysics.Detection.norminv(hitRate, bounds);
            f = psychophysics.Detection.norminv(faRate, bounds);
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
