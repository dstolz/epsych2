classdef Parameter_Table < handle

    properties
        handle (1,1) % handle to graphics object
        parent (1,1) % handle to parent container
        Parameter (1,1) hw.Parameter % handle to parameter

        type (1,:) char {mustBeMember(type,{'editfield','dropdown'})} = 'editfield'
    end

    properties (SetObservable = true)
        ValueUpdated (1,1) logical = false %
    end

    properties
        styleOnUpdate = uistyle('BackgroundColor',[0 0.6 0])
        styleNormal = uistyle('BackgroundColor',[])
    end



    methods
        % constructor
        function obj = Parameter_Table(parent,Parameters,options)
                arguments
                    parent
                    Parameters
                    options.Type (1,:) char {mustBeMember(options.Type,{'editfield','dropdown'})} = 'editfield'
                end
                obj.parent = parent;
                
                obj.Parameter = Parameters;
                obj.type = options.Type;
                
                obj.create;
        end


        function value_changed(obj,src,event)
            % TO DO: CHECK RANGE OF INPUT
            if isequal(event.Value,obj.Parameter.Value)
                % addStyle(obj.handle,obj.styleNormal,'row',event.);
                return
            end
            obj.ValueUpdated = true;
            addStyle(obj.handle,obj.styleOnUpdate);
        end


        function create(obj)
            h = uitable(obj.parent);
            h.ColumnEditable = [false true];
            h.CellEditCallback = @obj.value_changed;

            d(:,1) = {P.Name};
            d(:,2) = {P.Value};

            obj.handle = h;

        end

    end
end