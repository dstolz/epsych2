classdef Module < handle
        
    properties (SetAccess = immutable)
        HW (1,1)  % parent hardware interface (inherits hw.Interface)

        Label   (1,:) char
        Name    (1,:) char
        Index   (1,1) uint8
        
    end
    


    properties
        Fs (1,1) double {mustBePositive,mustBeFinite,mustBeNonNan} = 1
        
        Parameters (1,:) hw.Parameter

        Info (1,1) struct % fields defined by parent
    end

    methods
        function obj = Module(HW,Label,Name,Index)
            narginchk(4,4);

            obj.HW = HW;
            obj.Label = Label;
            obj.Name = Name;
            obj.Index = Index;
        end

        
    end

end