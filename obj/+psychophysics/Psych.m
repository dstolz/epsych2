classdef (Abstract) Psych < handle & matlab.mixin.SetGet
    % P = psychophysics.Psych(SOURCE, Parameter)
    % P = psychophysics.Psych(SOURCE, Parameter, ExcludedTrials=value)
    % psychophysics.Psych Abstract base for behavioral-paradigm analyses.
    % See documentation/psychophysics_Psych.md for subclassing and usage details.
    % psychophysics.Psych centralizes the shared data lifecycle used by
    % online and offline behavioral analyses. It supports construction from
    % either a Runtime object that emits NewData events or a saved DATA
    % struct array for offline review.
    %
    % Subclasses implement paradigm-specific recomputation while this base
    % class manages trial-data storage, response-code extraction, trial-type
    % masking, excluded-trial handling, and rebroadcasting updates through a
    % local Helper instance.
    %
    % Key properties:
    %   Parameter - Parameter object for online use, or a DATA field name for
    %       offline analysis.
    %   RUNTIME - Runtime object in online mode.
    %   DATA - Cached per-trial data array.
    %   ExcludedTrials - Logical mask or 1-based trial indices excluded from
    %       subclass analysis.
    %   Results - Paradigm-specific analysis outputs defined by subclasses.
    %
    % Example:
    %   % Subclasses call the base constructor from their own constructor.
    %   obj = obj@psychophysics.Psych(RUNTIME, Parameter, ExcludedTrials=[]);
    %
    % Returns:
    %   P - Abstract psychophysics.Psych subclass instance.

    properties (Abstract, SetAccess = protected)
        Results  % Paradigm-specific computed outputs
    end

    properties (SetObservable)
        Parameter = []  % Parameter object or offline DATA field name tracked by the analysis
    end

    properties (SetAccess = protected)
        RUNTIME = []  % Runtime object containing trial data and event infrastructure
        Helper = epsych.Helper  % Helper object for event broadcasting
        DATA = []  % Trial data array extracted from runtime events or offline input
    end

    properties (Dependent)
        responseCodes  % Response codes extracted from DATA
        trialCount  % Total number of trials in DATA
        ExcludedTrials  % Trial exclusions as a logical mask or 1-based trial indices
        ParameterName  % Convenience accessor for labels and plot titles
    end

    properties (Access = protected)
        hl_NewData = event.listener.empty
        excludedTrials_ = zeros(1,0)
    end

    methods
        function obj = Psych(source, Parameter, options)
            % obj = psychophysics.Psych(source, Parameter)
            % obj = psychophysics.Psych(source, Parameter, ExcludedTrials=value)
            % Initialize shared online/offline analysis state.
            % Parameters:
            %   source - Runtime object for online updates, or DATA struct array for offline analysis.
            %   Parameter - Parameter object, or in offline mode a DATA field name.
            %   ExcludedTrials - Logical mask or 1-based trial indices to exclude.
            arguments
                source = []
                Parameter = []
                options.ExcludedTrials = []
            end

            obj.configureSource_(source);
            obj.Parameter = obj.normalizeParameter_(Parameter);
            obj.excludedTrials_ = obj.normalizeExcludedTrialsValue_(options.ExcludedTrials);

            if ~isempty(obj.RUNTIME)
                obj.hl_NewData = addlistener(obj.RUNTIME.HELPER, 'NewData', @obj.update_data);
            end
        end

        function delete(obj)
            % delete(obj)
            % Destroy the analysis object and release runtime listeners.
            % Parameters:
            %   obj - psychophysics.Psych subclass instance.
            if ~isempty(obj.hl_NewData)
                listeners = obj.hl_NewData;
                listeners = listeners(isvalid(listeners));
                if ~isempty(listeners)
                    delete(listeners);
                end
                obj.hl_NewData = event.listener.empty;
            end
        end

        function refresh(obj)
            % refresh(obj)
            % Recompute subclass analysis outputs and notify listeners when online.
            % Parameters:
            %   obj - psychophysics.Psych subclass instance.
            obj.recomputeResults_();
            obj.afterRefresh_();
            obj.notifyDataUpdate_([]);
        end

        function update_data(obj, ~, event)
            % update_data(obj, ~, event)
            % Update cached DATA from a runtime NewData event.
            % Parameters:
            %   obj - psychophysics.Psych subclass instance.
            %   event - Event payload containing event.Data.DATA.
            obj.DATA = event.Data.DATA;
            vprintf(4, '%s received NewData event with %d trials', class(obj), numel(obj.DATA));

            obj.recomputeResults_();
            obj.afterRefresh_();
            obj.notifyDataUpdate_(event.Data);
        end

        function rc = get.responseCodes(obj)
            % rc = obj.responseCodes
            % Return response codes extracted from obj.DATA.
            % Parameters:
            %   obj - psychophysics.Psych subclass instance.
            % Returns:
            %   rc - Row vector of response codes, or empty when unavailable.
            fieldName = obj.resolveDataFieldName_(["RespCode", "ResponseCode"]);
            if strlength(fieldName) == 0
                rc = uint32([]);
                return
            end

            rc = obj.dataFieldValues_(fieldName);
            if isempty(rc)
                rc = uint32([]);
                return
            end

            rc = uint32(rc);
        end

        function n = get.trialCount(obj)
            % n = obj.trialCount
            % Return the total number of trials in obj.DATA.
            % Parameters:
            %   obj - psychophysics.Psych subclass instance.
            % Returns:
            %   n - Number of trials currently stored in DATA.
            n = numel(obj.DATA);
        end

        function value = get.ExcludedTrials(obj)
            % value = obj.ExcludedTrials
            % Return configured trial exclusions.
            % Parameters:
            %   obj - psychophysics.Psych subclass instance.
            % Returns:
            %   value - Logical exclusion mask or 1-based trial indices.
            value = obj.excludedTrials_;
        end

        function set.ExcludedTrials(obj, value)
            % obj.ExcludedTrials = value
            % Exclude trials from subclass analysis.
            % Parameters:
            %   obj - psychophysics.Psych subclass instance.
            %   value - Empty, logical mask, or 1-based trial indices.
            normalizedValue = obj.normalizeExcludedTrialsValue_(value);
            if isequaln(obj.excludedTrials_, normalizedValue)
                return
            end

            obj.excludedTrials_ = normalizedValue;
            obj.refresh();
        end

        function n = get.ParameterName(obj)
            % n = obj.ParameterName
            % Return a display name for the tracked parameter.
            % Parameters:
            %   obj - psychophysics.Psych subclass instance.
            % Returns:
            %   n - Parameter name for labels and plot titles.
            if isempty(obj.Parameter)
                n = "";
                return
            end

            if ischar(obj.Parameter) || (isstring(obj.Parameter) && isscalar(obj.Parameter))
                n = string(obj.Parameter);
                return
            end

            if isprop(obj.Parameter, 'Name')
                n = string(obj.Parameter.Name);
            else
                n = string(class(obj.Parameter));
            end
        end
    end

    methods (Access = protected)
        function configureSource_(obj, source)
            % Configure DATA vs RUNTIME storage from the constructor source input.
            if isstruct(source)
                obj.RUNTIME = [];
                obj.DATA = source;
                return
            end

            obj.RUNTIME = source;
            if isempty(obj.RUNTIME)
                obj.DATA = [];
            end
        end

        function Parameter = normalizeParameter_(obj, Parameter)
            % Validate the Parameter input against online/offline mode requirements.
            if isempty(obj.RUNTIME) && (ischar(Parameter) || (isstring(Parameter) && isscalar(Parameter)))
                Parameter = string(Parameter);
                return
            end

            if ~isempty(obj.RUNTIME) && (ischar(Parameter) || (isstring(Parameter) && isscalar(Parameter)))
                ME = MException(obj.classIdentifier_('InvalidParameter'), ...
                    'In online mode, Parameter must be a parameter object rather than a DATA field name.');
                throwAsCaller(ME);
            end
        end

        function notifyDataUpdate_(obj, trialsStruct)
            % Broadcast NewData through obj.Helper when runtime trial state is available.
            if nargin < 2 || isempty(trialsStruct)
                if isempty(obj.RUNTIME) || ~isprop(obj.RUNTIME, 'TRIALS') || isempty(obj.RUNTIME.TRIALS)
                    return
                end
                trialsStruct = obj.RUNTIME.TRIALS;
            end

            evtdata = epsych.TrialsData(trialsStruct);
            obj.Helper.notify('NewData', evtdata);
        end

        function afterRefresh_(~)
            % Hook for subclasses that need post-refresh side effects.
        end

        function tt = trialTypeValues_(obj)
            % Return per-trial TrialType values when present in DATA.
            if isempty(obj.DATA) || ~isfield(obj.DATA, 'TrialType')
                tt = [];
                return
            end

            tt = double(obj.dataFieldValues_('TrialType'));
        end

        function mask = trialTypeMask_(obj, trialTypeBit)
            % Resolve a logical mask for the requested trial type.
            tt = obj.trialTypeValues_();
            if ~isempty(tt)
                mask = tt == obj.bitMaskToTrialTypeValue_(trialTypeBit);
            else
                rc = obj.responseCodes;
                if isempty(rc)
                    mask = false(1, obj.trialCount);
                else
                    decodedResponses = epsych.BitMask.decode(rc);
                    mask = decodedResponses.(char(trialTypeBit));
                end
            end

            mask = reshape(logical(mask), 1, []);
            if numel(mask) < obj.trialCount
                mask(end+1:obj.trialCount) = false;
            elseif numel(mask) > obj.trialCount
                mask = mask(1:obj.trialCount);
            end

            mask(obj.excludedTrialMask_()) = false;
        end

        function ttValue = bitMaskToTrialTypeValue_(~, trialTypeBit)
            % Convert TrialType_* bit selections to the saved numeric TrialType value.
            ttValue = double(uint32(trialTypeBit) - uint32(epsych.BitMask.TrialType_0));
        end

        function fieldName = parameterFieldName_(obj)
            % Resolve the tracked DATA field name from Parameter.
            if ischar(obj.Parameter) || (isstring(obj.Parameter) && isscalar(obj.Parameter))
                fieldName = char(string(obj.Parameter));
                return
            end

            fieldName = obj.Parameter.validName;
        end

        function values = dataFieldValues_(obj, fieldName)
            % Return unwrapped DATA field values as a row vector when available.
            if isempty(obj.DATA) || ~isfield(obj.DATA, fieldName)
                values = [];
                return
            end

            rawValues = [obj.DATA.(fieldName)];
            values = obj.unwrapValueContainer_(rawValues);
            if isempty(values)
                return
            end

            values = reshape(values, 1, []);
        end

        function fieldName = resolveDataFieldName_(obj, candidateNames)
            % Resolve the first DATA field present from the provided candidates.
            fieldName = "";
            if isempty(obj.DATA)
                return
            end

            for idx = 1:numel(candidateNames)
                candidate = char(candidateNames(idx));
                if isfield(obj.DATA, candidate)
                    fieldName = string(candidate);
                    return
                end
            end
        end

        function value = normalizeExcludedTrialsValue_(obj, value)
            % Validate and normalize ExcludedTrials property values.
            if isempty(value)
                value = zeros(1, 0);
                return
            end

            if islogical(value)
                value = reshape(value, 1, []);
                return
            end

            if isnumeric(value)
                if ~isreal(value) || any(~isfinite(value(:))) || any(value(:) < 1) || any(fix(value(:)) ~= value(:))
                    ME = MException(obj.classIdentifier_('InvalidExcludedTrials'), ...
                        'ExcludedTrials must be empty, a logical mask, or a vector of finite positive integer trial indices.');
                    throwAsCaller(ME);
                end

                value = unique(reshape(double(value), 1, []), 'stable');
                return
            end

            ME = MException(obj.classIdentifier_('InvalidExcludedTrials'), ...
                'ExcludedTrials must be empty, a logical mask, or a vector of finite positive integer trial indices.');
            throwAsCaller(ME);
        end

        function mask = excludedTrialMask_(obj)
            % Resolve configured trial exclusions to a logical mask.
            mask = false(1, obj.trialCount);
            if obj.trialCount == 0 || isempty(obj.excludedTrials_)
                return
            end

            if islogical(obj.excludedTrials_)
                count = min(obj.trialCount, numel(obj.excludedTrials_));
                mask(1:count) = obj.excludedTrials_(1:count);
                return
            end

            idx = obj.excludedTrials_;
            idx = idx(idx >= 1 & idx <= obj.trialCount);
            mask(idx) = true;
        end

        function identifier = classIdentifier_(obj, mnemonic)
            % Return a class-scoped MException identifier suffix.
            identifier = sprintf('%s:%s', strrep(class(obj), '.', ':'), mnemonic);
        end
    end

    methods (Static, Access = private)
        function values = unwrapValueContainer_(rawValues)
            % Unwrap Value containers used by saved trial data into plain arrays.
            if isempty(rawValues)
                values = [];
                return
            end

            sample = rawValues(1);
            if (isstruct(sample) && isfield(sample, 'Value')) || (isobject(sample) && isprop(sample, 'Value'))
                values = [rawValues.Value];
            else
                values = rawValues;
            end
        end
    end

    methods (Abstract, Access = protected)
        recomputeResults_(obj)
    end
end