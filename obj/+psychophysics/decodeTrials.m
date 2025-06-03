classdef decodeTrials
    % decodeTrials decodes and summarizes trial results from a behavioral session.
    %
    % This class provides convenient access to trial-level behavioral data, parameter values,
    % and bitmask-decoded outcomes for use in psychophysics/behavioral analysis.

    properties
        TRIALS             % RUNTIME.TRIALS structure containing all trial data
        Parameter (1,1)    % hw.Parameter object specifying the experimental parameter
    end

    properties (Dependent)
        N (1,1) struct              % Total number of trials per decoded outcome
        M (1,1) struct              % Struct with fields for each bitmask, containing logical arrays for each trial
        responseCodes (1,:) uint32  % Vector of response codes for all trials
        DATA                        % Underlying DATA struct from TRIALS
        parameterName               % Name of the experimental parameter
        parameterData               % Values of the experimental parameter for each trial
        parameterIndex              % Index of the parameter in TRIALS.writeparams
        parameterFieldName          % Field name of the parameter in DATA
    end

    methods
        function obj = decodeTrials(TRIALS,Parameter)
            % Constructor: initializes with trial structure and parameter object.
            obj.TRIALS = TRIALS; 
            obj.Parameter = Parameter; 
        end

        function d = get.DATA(obj)
            % Returns DATA structure from TRIALS, or empty if not present.
            if isempty(obj.TRIALS)
                d = [];
            else
                d = obj.TRIALS.DATA;
            end
        end
        
        function m = get.M(obj)
            % Returns struct with logical arrays for each decoded bitmask outcome.
            if isempty(obj.responseCodes)
                m = [];
                return
            end
            bm = epsych.BitMask.getDefined;
            s = string(bm);
            for i = 1:length(bm)
                b = bitget(obj.responseCodes,bm(i));
                m.(s(i)) = logical(b);
            end
        end

        function n = get.N(obj)
            % Returns struct with count of each decoded outcome (sum over M).
            m = obj.M;
            n = struct(@sum,m);
        end

        function rc = get.responseCodes(obj)
            % Returns array of ResponseCode values for all trials.
            rc = uint32([obj.DATA.ResponseCode]);
        end

        function n = get.parameterName(obj)
            % Returns the name of the experimental parameter.
            n = obj.Parameter.Name;
        end

        function d = get.parameterData(obj)
            % Returns the data values for the experimental parameter across all trials.
            d = [obj.DATA.(obj.parameterFieldName)];
        end

        function i = get.parameterIndex(obj)
            % Returns index of the parameter in TRIALS.writeparams, or empty if not found.
            i = [];
            if isempty(obj.TRIALS), return; end
            if isempty(obj.parameterName), return; end
            i = find(ismember(obj.TRIALS.writeparams,obj.parameterName));
        end

        function n = get.parameterFieldName(obj)
            % Returns the field name for the experimental parameter in DATA, or empty if not found.
            n = [];
            if isempty(obj.TRIALS), return; end
            if isempty(obj.parameterName), return; end
            n = obj.TRIALS.writeparams{obj.parameterIndex};
        end
    end

end
