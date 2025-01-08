classdef Detection

% future Dan: update to make use of enumerated types ep.TrialType

    properties
        Go_TrialType    (1,1) double = 0;
        NoGo_TrialType  (1,1) double = 1;

        Parameter       (1,:) % hw.Parameter
        ParameterName   (1,:) char
        ParameterIDs    (1,:) uint8

        BoxID           (1,1) uint8 = 1;
        
        BitColors       (5,3) double {mustBeNonnegative,mustBeLessThanOrEqual(BitColors,1)} = [.8 1 .8; 1 .7 .7; .7 .9 1; 1 .7 1; 1 1 .4];

        BitsInUse epsych.BitMask = [3 4 6 7 5] % [Hit Miss CR FA Abort]

    end

    properties (Dependent)
        NumTrials       (1,1) uint16
        
        Go_Ind          (1,:) logical
        NoGo_Ind        (1,:) logical
        Go_Count        (1,1) uint16
        NoGo_Count      (1,1) uint16

        Hit_Ind     (1,:) logical
        Miss_Ind    (1,:) logical
        FA_Ind      (1,:) logical
        CR_Ind      (1,:) logical

        Hit_Count   (1,:) double
        Miss_Count  (1,:) double
        FA_Count    (1,:) double
        CR_Count    (1,:) double
        
        Trial_Count (1,:) double

        Hit_Rate    (1,:) double
        Miss_Rate   (1,:) double
        FA_Rate     (1,:) double
        CR_Rate     (1,:) double

        DPrime      (1,:) double
        Bias        (1,:) double
        
        % HR_FA_Diff  (1,:) double
                
        Trial_Index (1,1) double


        ParameterValues     (1,:)
        ParameterCount      (1,1)
        ParameterIndex      (1,1)
        ParameterFieldName  (1,:)
        ParameterData       (1,:)
        
        TRIALS
        DATA
        SUBJECT
    end

    properties (SetAccess = immutable)
        RUNTIME
    end

    properties (SetAccess = private)

        ResponseCodes   (1,:) uint16
        ResponsesEnum   (1,:) epsych.BitMask
        ResponsesChar   (1,:) cell

        ValidParameters (1,:) cell
        
        
    end
    

    
    methods        
        function obj = Detection(RUNTIME,BoxID,parameterName)
            
            obj.RUNTIME = RUNTIME;
            

            if nargin < 2 || isempty(BoxID), BoxID = 1; end
            if nargin < 3 || isempty(parameterName)
                % choose most variable parameter
                p = obj.ValidParameters;
                T = obj.TRIALS;
                for i = 1:length(p)
                    ind = ismember(T.writeparams,p{i});
                    if ~any(ind), continue; end
                    a = T.trials(:,ind);
                    if isnumeric(a{1})
                        v(i) = length(unique([a{:}]));
                    elseif ischar(a{1})
                        v(i) = length(unique(a));
                    elseif isstruct(a{1})
                        v(i) = length(cellfun(@(x) x.file,a,'uni',0));
                    end
                end
                [~,m] = max(v);
                parameterName = p{m};
            end

            obj.BoxID = BoxID;
            obj.ParameterName = parameterName;
            
        end

        
        

        % Ind ------------------------------------------------------
        function r = get.Hit_Ind(obj)
            r = bitget(obj.ResponseCodes,epsych.BitMask.Hit);
            r = logical(r);
        end

        function r = get.Miss_Ind(obj)
            r = bitget(obj.ResponseCodes,epsych.BitMask.Miss);
            r = logical(r);
        end

        function r = get.FA_Ind(obj)
            r = bitget(obj.ResponseCodes,epsych.BitMask.FalseAlarm);
            r = logical(r);
        end

        function r = get.CR_Ind(obj)
            r = bitget(obj.ResponseCodes,epsych.BitMask.CorrectReject);
            r = logical(r);
        end

        function i = get.Go_Ind(obj)
            i = [obj.DATA.TrialType] == obj.Go_TrialType;
        end

        function i = get.NoGo_Ind(obj)
            i = [obj.DATA.TrialType] == obj.NoGo_TrialType;
        end

        % Count -----------------------------------------------------
        function n = get.Go_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            ind = obj.Go_Ind;
            for i =1:length(v)
                n(i) = sum(ind & d == v(i));
            end
        end

        function n = get.NoGo_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            ind = obj.NoGo_Ind;
            for i =1:length(v)
                n(i) = sum(ind & d == v(i));
            end
        end
        
        function n = get.Trial_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            for i =1:length(v)
                n(i) = sum(d == v(i));
            end
        end

        function n = get.Hit_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            for i = 1:length(v)
                n(i) = sum(obj.Hit_Ind & d == v(i));
            end
        end
        
        function n = get.Miss_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            for i = 1:length(v)
                n(i) = sum(obj.Miss_Ind & d == v(i));
            end
        end
        
        function n = get.FA_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            for i = 1:length(v)
                n(i) = sum(obj.FA_Ind & d == v(i));
            end
        end
        function n = get.CR_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            for i = 1:length(v)
                n(i) = sum(obj.CR_Ind & d == v(i));
            end
        end



        % Rate ----------------------------------------------------
        function r = get.Hit_Rate(obj)
            r = obj.Hit_Count ./ obj.Go_Count;
        end

        function r = get.Miss_Rate(obj)
            r = 1 - obj.Hit_Rate;
        end

        function r = get.CR_Rate(obj)
            r = obj.CR_Count ./ obj.NoGo_Count;
        end

        function r = get.FA_Rate(obj)
            r = 1 - obj.CR_Rate;
        end

        function dp = get.DPrime(obj)
            dp = obj.zscore(obj.Hit_Rate) - obj.zscore(obj.FA_Rate);
        end

        function c = get.Bias(obj)
            c = -(obj.zscore(obj.Hit_Rate) + obj.zscore(obj.FA_Rate))./2;
        end
        
        function r = get.ResponsesEnum(obj)
            RC = obj.ResponseCodes;
            r(length(RC),1) = epsych.BitMask(0);
            for i = obj.BitsInUse
                ind = logical(bitget(RC,i));
                if ~any(ind), continue; end
                r(ind) = i;
            end
        end
        
        function c = get.ResponsesChar(obj)
            c = cellfun(@char,num2cell(obj.ResponsesEnum),'uni',0);
        end
        
        function rc = get.ResponseCodes(obj)
            rc = [obj.DATA.ResponseCode];
        end

        function n = get.NumTrials(obj)
            n = length(obj.DATA);
        end


        % Parameter -------------------------------------------------

        function v = get.ParameterValues(obj)
            v = [];
            if isempty(obj.ParameterName), return; end
            a = obj.TRIALS.trials(:,obj.ParameterIndex);
            if isnumeric(a{1})
                v = unique([a{:}]);
            elseif ischar(a{1})
                v = unique(a);
            elseif isstruct(a{1})
                v = cellfun(@(x) x.file,a,'uni',0);
            end
        end

        function d = get.ParameterData(obj)
            d = [obj.DATA.(obj.ParameterFieldName)];
        end

        function n = get.ParameterCount(obj)
            n = [];
            if isempty(obj.ParameterName), return; end
            v = obj.ParameterValues;
            d = obj.ParameterData;
            for i = 1:length(v)
                n(i) = sum(obj.Hit_Ind & ismember(d,v{i}));
            end
        end

        function i = get.ParameterIndex(obj)
            i = [];
            if isempty(obj.ParameterName), return; end
            i = find(ismember(obj.TRIALS.writeparams,obj.ParameterName));
        end

        function n = get.ParameterFieldName(obj)
            n = [];
            if isempty(obj.ParameterName), return; end
            n = obj.TRIALS.writeparams{obj.ParameterIndex};
        end

        function p = get.ValidParameters(obj)
            p = fieldnames(obj.DATA);
            p(~ismember(p,obj.TRIALS.writeparams)) = [];
        end
        
        function t = get.TRIALS(obj)
            t = obj.RUNTIME.TRIALS(obj.BoxID);
        end
        
        function d = get.DATA(obj)
            d = obj.TRIALS.DATA;
        end
        
        function s = get.SUBJECT(obj)
            s = obj.TRIALS.Subject;
        end
        
        function i = get.Trial_Index(obj)
            i = obj.TRIALS.TrialIndex;
        end
        
    end

    methods (Static)
        function z = zscore(a)
            % bounds input to [0.01 0.99] to avoid inf values
            a  = max(min(a,0.99),0.01);
            z = sqrt(2)*erfinv(2*a-1);
        end
    end
end