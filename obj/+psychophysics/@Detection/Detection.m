classdef Detection < handle

% future Dan: update to make use of enumerated types ep.TrialType

    properties
        Stim_TrialType   (1,1) double = 0;
        Catch_TrialType  (1,1) double = 1;

        Parameter       (1,:) % hw.Parameter
        ParameterIDs    (1,:) uint8

        BoxID           (1,1) uint8 = 1;
        
        BitColors       (5,3) double {mustBeNonnegative,mustBeLessThanOrEqual(BitColors,1)} = [.8 1 .8; 1 .7 .7; .7 .9 1; 1 .7 1; 1 1 .4];

        BitsInUse epsych.BitMask = [1 2 3 4 7] % [Hit Miss CR FA Abort]

        Helper = epsych.Helper

    end

    properties (Dependent)
        NumTrials   (1,1) uint16
        
        Stim_Ind    (1,:) logical
        Catch_Ind   (1,:) logical
        Stim_Count  (1,1) uint16
        Catch_Count (1,1) uint16

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
        ParameterName   (1,:) char

        DATA
        SUBJECT
    end

    properties (SetAccess = private)

        ResponseCodes   (1,:) uint8
        ResponsesEnum   (1,:) epsych.BitMask
        ResponsesChar   (1,:) cell

        ValidParameters (1,:) cell
        
        
        TRIALS

        hl_NewData
    end
    

    
    methods        
        function obj = Detection(Parameter,BoxID)
            global RUNTIME

            if nargin < 2 || isempty(BoxID), BoxID = 1; end
            obj.BoxID = BoxID;

            obj.Parameter = Parameter;
           
            
            obj.hl_NewData = listener(RUNTIME.HELPER,'NewData',@obj.update_data);

        end

        function delete(obj)
            try
                delete(obj.hl_NewData);
            end
        end

        function update_data(obj,src,event)
            obj.TRIALS = event.Data;
            evtdata = epsych.TrialsData(obj.TRIALS);
            obj.Helper.notify('NewData',evtdata);
        end

       

        % Ind ------------------------------------------------------
        function r = get.Hit_Ind(obj)
            if isempty(obj.ResponseCodes)
                r = [];
                return
            end
            r = bitget(obj.ResponseCodes,epsych.BitMask.Hit);
            r = logical(r);
        end

        function r = get.Miss_Ind(obj)
            if isempty(obj.ResponseCodes)
                r = [];
                return
            end
            r = bitget(obj.ResponseCodes,epsych.BitMask.Miss);
            r = logical(r);
        end

        function r = get.FA_Ind(obj)
            if isempty(obj.ResponseCodes)
                r = [];
                return
            end
            r = bitget(obj.ResponseCodes,epsych.BitMask.FalseAlarm);
            r = logical(r);
        end

        function r = get.CR_Ind(obj)
            if isempty(obj.ResponseCodes)
                r = [];
                return
            end
            r = bitget(obj.ResponseCodes,epsych.BitMask.CorrectReject);
            r = logical(r);
        end

        function i = get.Stim_Ind(obj)
            i = [obj.DATA.TrialType] == obj.Stim_TrialType;
        end

        function i = get.Catch_Ind(obj)
            i = [obj.DATA.TrialType] == obj.Catch_TrialType;
        end

        % Count -----------------------------------------------------
        function n = get.Stim_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            ind = obj.Stim_Ind;
            for i =1:length(v)
                n(i) = sum(ind & isapprox(d,v(i),'loose'));
            end
        end

        function n = get.Catch_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            ind = obj.Catch_Ind;
            for i =1:length(v)
                n(i) = sum(ind & isapprox(d,v(i),'loose'));
            end
            
        end
        
        function n = get.Trial_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            for i =1:length(v)
                n(i) = sum(isapprox(d,v(i),'loose'));
            end
        end

        function n = get.Hit_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            hi = obj.Hit_Ind;
            for i = 1:length(v)
                n(i) = sum(hi & isapprox(d,v(i),'loose'));
            end
        end
        
        function n = get.Miss_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            for i = 1:length(v)
                n(i) = sum(obj.Miss_Ind & isapprox(d,v(i),'loose'));
            end
        end
        
        function n = get.FA_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            for i = 1:length(v)
                n(i) = sum(obj.FA_Ind & isapprox(d,v(i),'loose'));
            end
        end
        function n = get.CR_Count(obj)
            v = obj.ParameterValues;
            d = obj.ParameterData;
            hi = obj.CR_Ind;
            for i = 1:length(v)
                n(i) = sum(hi & isapprox(d,v(i),'loose'));
            end
        end



        % Rate ----------------------------------------------------
        function r = get.Hit_Rate(obj)
            r = obj.Hit_Count ./ obj.Stim_Count;
        end

        function r = get.Miss_Rate(obj)
            r = 1 - obj.Hit_Rate;
        end

        function r = get.CR_Rate(obj)
            r = obj.CR_Count ./ obj.Catch_Count;
        end

        function r = get.FA_Rate(obj)
            r = 1 - obj.CR_Rate;
        end

        function dp = get.DPrime(obj)
            far = obj.FA_Rate;
            far = far(~isnan(far));
            hr = obj.Hit_Rate;
            ind = isnan(hr);
            dp = obj.zscore(hr) - obj.zscore(far);
            dp(ind) = nan; 
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
            rc = uint8([obj.DATA.ResponseCode]);
        end

        function n = get.NumTrials(obj)
            n = length(obj.DATA);
        end


        % Parameter -------------------------------------------------
        function n = get.ParameterName(obj)
            n = obj.Parameter.Name;
        end

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
            if isempty(obj.TRIALS), return; end
            if isempty(obj.ParameterName), return; end
            i = find(ismember(obj.TRIALS.writeparams,obj.ParameterName));
        end

        function n = get.ParameterFieldName(obj)
            n = [];
            if isempty(obj.TRIALS), return; end
            if isempty(obj.ParameterName), return; end
            n = obj.TRIALS.writeparams{obj.ParameterIndex};
        end

        function p = get.ValidParameters(obj)
            if isempty(obj.TRIALS)
                p = [];
            else
                p = fieldnames(obj.DATA);
                p(~ismember(p,obj.TRIALS.writeparams)) = [];
            end
        end
        
        function d = get.DATA(obj)
            if isempty(obj.TRIALS)
                d = [];
            else
                d = obj.TRIALS.DATA;
            end
        end
        
        function s = get.SUBJECT(obj)
            if isempty(obj.TRIALS)
                s = [];
            else
                s = obj.TRIALS.Subject;
            end
        end
        
        function i = get.Trial_Index(obj)
            if isempty(obj.TRIALS)
                i = 1;
            else
                i = obj.TRIALS.TrialIndex;
            end
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