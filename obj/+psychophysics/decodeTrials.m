classdef decodeTrials
    % decodeTrials decodes and summarizes trial results from a behavioral session.
    %
    % This class provides convenient access to trial-level behavioral data, 
    % and bitmask-decoded outcomes for use in psychophysics/behavioral analysis.

    properties
        TRIALS             % RUNTIME.TRIALS structure containing all trial data
    end

    properties (Dependent)
        N (1,1) struct              % Total number of trials per decoded outcome
        M (1,1) struct              % Struct with fields for each bitmask, containing logical arrays for each trial
        responseCodes (1,:) uint32  % Vector of response codes for all trials
        DATA                        % Underlying DATA struct from TRIALS
    end

    methods
        function obj = decodeTrials(TRIALS)
            % Constructor: initializes with trial structure.
            obj.TRIALS = TRIALS; 
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

    end

end
