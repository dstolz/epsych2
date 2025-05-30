classdef decodeTrials

    properties
        TRIALS % RUNTIME.TRIALS structure
        Parameter (1,1) % hw.Parameter
    end

    properties (Dependent)
        N (1,1) struct % Total number of trials
        M (1,1) struct % Structure with fields derived from obj.Bits


        responseCodes   (1,:) uint32

        DATA

        parameterName
        parameterData
        parameterIndex
        parameterFieldName
    end
    


    methods
        function obj = decodeTrials(TRIALS,Parameter)
            obj.TRIALS = TRIALS; 
            obj.Parameter = Parameter; 
        end


        % TRIALS
        function d = get.DATA(obj)
            if isempty(obj.TRIALS)
                d = [];
            else
                d = obj.TRIALS.DATA;
            end
        end
        

        function m = get.M(obj)
            if isempty(obj.responseCodes)
                m = [];
                return
            end

            bm = epsych.BitMask.getAll;
            s = string(bm);
            for i = 1:length(bm)
                b = bitget(obj.responseCodes,uint32(bm(i)));
                m.(s(i)) = logical(b);
            end
        end


        function n = get.N(obj)
            m = obj.M;
            n = struct(@sum,m);
        end






        % ResponseCode
        function rc = get.responseCodes(obj)
            rc = uint32([obj.DATA.ResponseCode]);
        end







        % Parameter
        function n = get.parameterName(obj)
            n = obj.Parameter.Name;
        end

        function d = get.parameterData(obj)
            d = [obj.DATA.(obj.parameterFieldName)];
        end


        function i = get.parameterIndex(obj)
            i = [];
            if isempty(obj.TRIALS), return; end
            if isempty(obj.parameterName), return; end
            i = find(ismember(obj.TRIALS.writeparams,obj.parameterName));
        end

        function n = get.parameterFieldName(obj)
            n = [];
            if isempty(obj.TRIALS), return; end
            if isempty(obj.parameterName), return; end
            n = obj.TRIALS.writeparams{obj.parameterIndex};
        end








    end

end