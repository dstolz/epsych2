classdef decodeTrials
    % decodeTrials decodes and summarizes trial results from a behavioral session.
    %
    % This class provides convenient access to trial-level behavioral data, 
    % and bitmask-decoded outcomes for use in psychophysics/behavioral analysis.

    properties
        responseCodes             % Response Codes form RUNTIME.TRIALS.DATA
    end

    properties (Dependent)
        N (1,1) struct              % Total number of trials per decoded outcome
        M (1,1) struct              % Struct with fields for each bitmask, containing logical arrays for each trial
    end

    methods
        function obj = decodeTrials(responseCodes)
            % Constructor: initializes with trial structure.
            obj.responseCodes = responseCodes; 
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

    end

end