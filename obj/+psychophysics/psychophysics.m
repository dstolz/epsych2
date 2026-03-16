classdef psychophysics < handle
    % obj = psychophysics.psychophysics(Runtime, BoxID)
    % Abstract base class for computing psychophysics metrics from trial data.
    %
    % Subclasses define ResponseBits and Type, and this class derives common
    % dependent quantities (counts, rates, d-prime) from the Runtime trial data.
    %
    % Properties (selected):
    %   Runtime, BoxID - Runtime handle and box identifier.
    %   Count, Rate    - Derived counts/rates per trial type.
    %
    % Methods:
    %   dprime         - Compute d' for each active trial type.
    
    properties (Abstract,Constant)
        ResponseBits
        Type
    end


    properties (Constant)
        TrialTypeBits = epsych.BitMask(12:15);
    end

    properties (SetAccess = immutable)
        Runtime
        BoxID
        
    end

    properties (Dependent)
        ResponseCodes
        Ind
        Count
        Rate
        TrialType
        NumTrialTypes
        Data
    end

    methods

        function obj = psychophysics(Runtime,BoxID)
            obj.BoxID   = BoxID;
            obj.Runtime = Runtime;
        end


        function s = get.Ind(obj)
            for i = 1:obj.NumTrialTypes
                f = char(obj.TrialTypeBits(i));
                s.(f).Trials = logical(bitget(obj.ResponseCodes,obj.TrialTypeBits(i)));
                for j = 1:length(obj.ResponseBits)
                    s.(f).(char(obj.ResponseBits(j))) = s.(f).Trials & bitget(obj.ResponseCodes,obj.ResponseBits(j));
                end
            end
        end
        
        function n = get.NumTrialTypes(obj)
            n = length(obj.TrialTypeBits);
        end
        

        function c = get.Count(obj)
            S = obj.Ind;
            for i = 1:obj.NumTrialTypes
                f = char(obj.TrialTypeBits(i));
                c.(f).Trials = sum(S.(f).Trials);
                for j = 1:length(obj.ResponseBits)
                    c.(f).(char(obj.ResponseBits(j))) = sum(S.(f).(char(obj.ResponseBits(j))));
                end
            end            
        end

        function r = get.Rate(obj)
            C = obj.Count;
            for i = 1:obj.NumTrialTypes
                f = char(obj.TrialTypeBits(i));
                for j = 1:length(obj.ResponseBits)
                    r.(f).(char(obj.ResponseBits(j))) = C.(f).(char(obj.ResponseBits(j))) ./ C.(f).Trials;
                end
            end
        end

        function c = get.ResponseCodes(obj)
             c = obj.Data.ResponseCodes;
        end

        function t = get.Data(obj)
            t = obj.Runtime.TRIALS(obj.BoxID).Data;
        end

        function dp = dprime(obj)
            R = obj.Rate;
            for i = 1:obj.NumTrialTypes
                f = char(obj.TrialTypeBits(i));
                switch obj.Type
                    case {'DETECT','YESNO'}
                        dp.(f) = obj.dprime_detect(R.(f).Hit,R.(f).FalseAlarm);
                        
                    case '2AFC'
                        dp.(f) = obj.dprime_2afc(R.(f).Hit,R.(f).Miss);
                end
            end
        end
        
        
        
        function plot(obj,ax)
            if nargin < 2 || isempty(ax), ax = gca; end
            
            
        end
    end

    methods (Static)
        function z = zscore(a)
            z = norminv(a,0,1);
        end

        function dp = dprime_detect(HR,FAR)
            HR  = max(min(HR,0.99),0.01);
            FAR = max(min(FAR,0.99),0.01);
            dp  = norminv(HR) - norminv(FAR);
        end

        function dp = dprime_2afc(HR,FAR)
            HR  = max(min(HR,0.99),0.01);
            FAR = max(min(FAR,0.99),0.01);
            dp  = norminv(HR) - norminv(FAR);
            dp  = dp ./ sqrt(2);
        end
    end
end