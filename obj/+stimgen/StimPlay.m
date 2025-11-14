classdef (Hidden) StimPlay < handle & matlab.mixin.SetGet
    
    
    properties (AbortSet,SetObservable)
        StimObj % stimgen objects
        ListIdx (1,1) double {mustBeInteger} = 0;
        Reps    (1,1) double {mustBeInteger} = 20;
        ISI     (1,2) double {mustBePositive,mustBeFinite} = 1;
        
        Name    (1,1) string
        DisplayName (1,1) string
        
        RepsPresented (1,1) double {mustBeInteger,mustBeFinite} = 0;
    end
    
    properties (Dependent)
        Type
        Signal
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
            obj.RepsPresented = obj.RepsPresented + 1;
        end
        
        function y = get.Signal(obj)
            y = obj.StimObj.Signal;
        end
               
        
        function i = get_isi(obj)
            d = diff(obj.ISI);
            if d > 0
                i = rand(1)*d+obj.ISI(1);
            else
                i = obj.ISI(1);
            end
        end
        
        
    end
end