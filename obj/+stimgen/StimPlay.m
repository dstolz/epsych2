classdef (Hidden) StimPlay < handle & matlab.mixin.SetGet
    
    
    properties (AbortSet,SetObservable)
        StimObj (1,:) %stimgen objects


        Fs      (1,1) double {mustBePositive,mustBeFinite} = 1;


        Reps    (1,1) double {mustBeInteger} = 20;
        ISI     (1,2) double {mustBePositive,mustBeFinite} = 1;
        
        Name    (1,1) string
        DisplayName (1,1) string
        
        RepsPresented (1,:) double {mustBeInteger,mustBeFinite} = 0;

        StimIdx (1,1) double {mustBeInteger} = 1;

        SelectionType {mustBeMember(SelectionType,["Shuffle","Serial"])} = "Shuffle";

        Complete (1,1) logical = false;
    end

    properties (SetAccess = private)
        StimOrder (1,:)
    end
    
    properties (Dependent)
        Type
        Signal
        CurrentStimObj
        NStimObj
    end
    
    methods
        function obj = StimPlay(StimObj)
            if nargin == 1 && ~isempty(StimObj)
                obj.StimObj = StimObj;
            end
        end
        
        function t = get.Type(obj)
            t = class(obj.StimObj);
            t(1:find(t=='.')) = [];
        end
        
        function n = get.DisplayName(obj)
            if isempty(obj.DisplayName) || obj.DisplayName == ""
                isi = obj.ISI;
                if all(isi==isi(1))
                    isi(2) = [];
                end
                isistr = mat2str(isi);
                n = string(sprintf('%s (%s) x%d, isi = %s sec', ...
                    obj.Name,obj.Type,obj.Reps,isistr));
            else
                n = obj.DisplayName;
            end
        end
        
        function increment(obj)

            if sum(obj.RepsPresented) == obj.Reps * obj.NStimObj
                obj.Complete = true;
                return
            end

            switch obj.SelectionType
                case "Shuffle"
                    idx = obj.select_Shuffle();

                case "Serial"
                    idx = obj.select_Serial();
            end

            obj.StimIdx = idx;

            obj.RepsPresented(idx) = obj.RepsPresented(idx) + 1;
            obj.StimOrder(sum(obj.RepsPresented)) = idx;            
        end
        
        
        function i = get_isi(obj)
            d = diff(obj.ISI);
            if d > 0
                i = rand(1)*d+obj.ISI(1);
            else
                i = obj.ISI(1);
            end
        end
        
        function reset(obj)
            obj.StimIdx = 0;
            obj.RepsPresented = zeros(size(obj.StimObj));
            obj.StimOrder = nan(1,obj.Reps*obj.NStimObj);
        end


        function set.Fs(obj,fs)
            for i = 1:obj.NStimObj
                if obj.StimObj.IsMultiObj
                    obj.StimObj(i).Fs = fs;
                else
                    obj.StimObj.MultiObjects(i).Fs = fs;
                end
            end
        end

        function update_signal(obj)
            if obj.StimObj.IsMultiObj
                arrayfun(@update_signal,obj.StimObj.MultiObjects);
            else
                arrayfun(@update_signal,obj.StimObj);
            end
        end


        function y = get.Signal(obj)
            y = obj.CurrentStimObj.Signal;
        end

        function so = get.CurrentStimObj(obj)
            if obj.StimObj.IsMultiObj
                so = obj.StimObj.MultiObjects(obj.StimIdx);
            else
                so = obj.StimObj(obj.StimIdx);
            end
        end
               
        function n = get.NStimObj(obj)
            if obj.StimObj.IsMultiObj
                n = numel(obj.StimObj.MultiObjects);
            else
                n = numel(obj.StimObj);
            end
        end
    end

    methods (Access = private)
        function idx = select_Shuffle(obj)
            r = obj.RepsPresented;

            m = min(r);

            idx = find(r == m);

            i = randi(numel(idx));

            idx = idx(i);
        end

        function idx = select_Serial(obj)
            r = obj.RepsPresented;

            m = min(r);

            idx = find(r == m,1);

        end
    end
end