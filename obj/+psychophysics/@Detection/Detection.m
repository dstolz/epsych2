classdef Detection < handle & matlab.mixin.SetGet
    % Detection   Class for analyzing psychophysical detection task data
    %
    %   Processes trial data from a running session (RUNTIME.TRIALS), decoding
    %   trial outcome bitmasks and computing signal detection metrics (hit and
    %   false alarm rates, d-prime, A-prime, bias) grouped by unique stimulus
    %   values.
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
    %       APrime          - Nonparametric A' per unique stimulus value
    %       Bias            - Response bias per unique stimulus value
    %       Hit_Rate        - Hit rate per unique stimulus value
    %       FA_Rate         - Catch-trial false alarm rate (replicated per value)
    %
    %   Detection Methods:
    %       Detection       - Constructor to initialize the class
    %       d_prime         - Static method to compute d-prime
    %       a_prime         - Static method to compute nonparametric A'
    %       bias            - Static method to compute bias
    %       norminv         - Static method for bounded inverse normal transformation
    %
    %   Used by gui.components.PsychPlot, gui.components.Performance, and gui.components.SlidingWindowPerformancePlot.

    properties (SetObservable)
        % TRIALS - Structure containing trial data (RUNTIME.TRIALS)
        TRIALS

        % Parameter - Parameter object defining trial parameters (hw.Parameter)
        Parameter (1,1)

        % infCorrection - Correction bounds for infinite z-scores [lower upper]
        % Ensures that hit and false alarm rates are within (0,1) exclusive
        infCorrection (1,2) double {mustBeInRange(infCorrection,0,1,"exclusive")} = [0.05 0.95];

        % IncludeAborts - Count aborted trials against Hit_Rate and FA_Rate,
        % as failures to respond. False by default, so the rates describe the
        % trials the subject answered; see
        % psychophysics.Metrics.rateDenominator.
        IncludeAborts (1,1) logical = false

        % targetTrialType - Target trial type to analyze (epsych.BitMask)
        targetTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0

        ttStimulus (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
        ttCatch    (1,1) epsych.BitMask = epsych.BitMask.TrialType_1

        BitsInUse (1,:) epsych.BitMask = epsych.BitMask.getResponses % [Hit Miss CR FA Abort]
        BitColors (5,1) string = ["#dff7df","#fcdcdc","#d9f2ff","#fcdefc","#fcfcd4"];
    end

    properties (SetAccess = private)
        % Events - Event broadcaster this analysis re-broadcasts NewData on
        Events = epsych.EventHub

        % M - Logical arrays for each decoded bitmask flag
        M
        % N - Counts of each decoded bitmask flag
        N

        RUNTIME
    end

    properties (Dependent, Hidden)
        % Helper - Deprecated alias for Events; remove once paradigm GUIs migrate
        Helper
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

        % APrime - Nonparametric sensitivity A' per unique stimulus value
        APrime      (1,:) double

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

        % ParameterValues - Alias for uniqueValues (used by gui.components.PsychPlot)
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

            obj.hl_NewData = addlistener(RUNTIME.EVENTS,'NewData',@obj.update_data);
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
            obj.Events.notify('NewData',evtdata);
        end



        function value = get.Helper(obj), value = obj.Events; end

        function d = get.DATA(obj)
            % get.DATA Extracts trial data from TRIALS
            if isempty(obj.TRIALS)
                d = [];
            else
                d = obj.TRIALS.DATA;
                if isempty(d), return; end
                % The runtime stores plain values (ep_TimerFcn_RunTime
                % collects valueOnly=true); legacy records stored the
                % hw.Parameter handles themselves, so unwrap only those.
                fn = fieldnames(d);
                for i = 1:numel(d)
                    for j = 1:numel(fn)
                        p = d(i).(fn{j});
                        if isa(p, 'hw.Parameter')
                            d(i).(fn{j}) = [p.Value];
                        end
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
            %
            % 'ResponseCode' is the older name for the same field and is still
            % what many saved sessions carry. Reading only 'RespCode' made such
            % a session analyze as ZERO trials -- silently, because every
            % count, rate and d' then comes back empty rather than erroring,
            % so the failure looks like a subject who never responded.
            % psychophysics.Psych.responseCodes, BestPEST and MLP already
            % resolve the pair; Detection is not a Psych subclass and needs its
            % own. RespCode wins where a file carries both, which is the
            % order every other resolver uses.
            if isempty(obj.DATA)
                rc = uint32([]);
            elseif isfield(obj.DATA, 'RespCode')
                rc = uint32([obj.DATA.RespCode]);
            elseif isfield(obj.DATA, 'ResponseCode')
                rc = uint32([obj.DATA.ResponseCode]);
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
            %
            %   Hit / (Hit + Miss) at each value, so an aborted trial does
            %   not depress the rate. Set IncludeAborts to score aborts as
            %   failures to respond instead. Note this is NOT [obj.Rate.Hit],
            %   which is the proportion of every trial at that value.
            obj.targetTrialType = obj.ttStimulus;
            c = obj.Count;
            if isempty(c), r = []; return; end
            r = psychophysics.Metrics.rate([c.Hit], ...
                psychophysics.Metrics.rateDenominator([c.Hit] + [c.Miss], ...
                    [c.Abort], obj.IncludeAborts));
        end

        function r = get.Miss_Rate(obj)
            % The complement of the hit rate. With IncludeAborts this is the
            % proportion that were not hits rather than the miss rate proper,
            % since aborts are then in the denominator too.
            r = 1 - obj.Hit_Rate;
        end

        function r = get.FA_Rate(obj)
            % get.FA_Rate Catch-trial false alarm rate, replicated to match
            % the number of unique stimulus values for plotting
            %
            %   FA / (FA + CR) over every catch trial in the session; see
            %   Hit_Rate for the aborts policy.
            obj.targetTrialType = obj.ttCatch;
            c = obj.Count;
            if isempty(c)
                far = [];
            else
                far = psychophysics.Metrics.rate(sum([c.FalseAlarm]), ...
                    psychophysics.Metrics.rateDenominator( ...
                        sum([c.FalseAlarm]) + sum([c.CorrectReject]), ...
                        sum([c.Abort]), obj.IncludeAborts));
            end

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

        function a = get.APrime(obj)
            % get.APrime Nonparametric sensitivity A' per unique stimulus value
            %
            %   Computed from the Hit rate at each unique stimulus value and
            %   the overall catch-trial FalseAlarm rate. Unlike DPrime this
            %   needs no infCorrection: A' is defined at rates of 0 and 1.

            obj.targetTrialType = obj.ttCatch;
            CT = obj.Rate;
            FAR = CT(1).FalseAlarm;

            obj.targetTrialType = obj.ttStimulus;
            r = obj.Rate;
            a = nan(1,numel(r));
            if isempty(r) || isempty(r(1).Hit), return; end
            for i = 1:numel(r)
                a(i) = psychophysics.Detection.a_prime(r(i).Hit, FAR);
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
            %
            %   Kept for compatibility, including its [0.01 0.99] default.
            %   psychophysics.Metrics.dprime is the implementation and the
            %   one to call in new code, where the correction is named rather
            %   than implied by a pair of bounds, and where the trial-count
            %   dependent corrections are available.

            arguments
                hitRate
                faRate
                bounds (1,2) double {mustBeInRange(bounds,0,1,"exclusive")} = [0.01 0.99]
            end
            d = psychophysics.Metrics.dprime(hitRate, faRate, Correction="clamp", Bounds=bounds);
        end

        function a = a_prime(hitRate, faRate)
            % a_prime Computes the nonparametric sensitivity index A'
            %
            %   a = a_prime(hitRate, faRate) returns Grier's (1971) A' from
            %   the hit and false alarm rates. See
            %   psychophysics.Metrics.aprime, which owns the formula and
            %   documents it; this is kept because A' is public API.

            arguments
                hitRate double
                faRate  double
            end
            a = psychophysics.Metrics.aprime(hitRate, faRate);
        end

        function c = bias(hitRate, faRate, bounds)
            % bias Computes bias (criterion) from hit and false alarm rates
            %
            %   c = bias(hitRate, faRate, bounds) computes the bias value
            %   using the provided hitRate and faRate, applying the specified
            %   bounds to avoid infinite z-scores.
            %
            %   Kept for compatibility. psychophysics.Metrics.criterion is
            %   the implementation, and the unambiguous name -- "bias" also
            %   names beta and B''.

            arguments
                hitRate
                faRate
                bounds (1,2) double {mustBeInRange(bounds,0,1,"exclusive")} = [0.01 0.99]
            end
            c = psychophysics.Metrics.criterion(hitRate, faRate, Correction="clamp", Bounds=bounds);
        end

        function n = norminv(r,bounds)
            % norminv Bounded inverse normal CDF
            %
            %   Kept for compatibility. psychophysics.Metrics.z is the
            %   implementation, and needs no Statistics Toolbox.
            %
            %   One behavior change: an undefined rate now yields NaN. The
            %   max/min clamp this replaced dropped NaN -- min(NaN,0.99) is
            %   0.99 -- so a missing rate silently became a bound.

            arguments
                r
                bounds (1,2) double {mustBeInRange(bounds,0,1,"exclusive")} = [0.01 0.99]
            end
            r = psychophysics.Metrics.correctRates(r, r, Correction="clamp", Bounds=bounds);
            n = psychophysics.Metrics.z(r);
        end
    end
end
