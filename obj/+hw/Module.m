classdef Module < handle
        
    properties (SetAccess = immutable)
        Parent (1,1) 

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
        function obj = Module(Parent,Label,Name,Index)
            narginchk(4,4);

            obj.Parent = Parent;
            obj.Label = Label;
            obj.Name = Name;
            obj.Index = Index;
        end

        
    end

end