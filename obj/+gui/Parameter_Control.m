classdef Parameter_Control < handle & matlab.mixin.SetGet

    properties (SetAccess = immutable)
        handle (1,1) % handle to graphics object
        parent (1,1) % handle to parent container
        Parameter (1,1) %hw.Parameter % handle to parameter

        type (1,:) char {mustBeMember(type,{'editfield','dropdown','checkbox'})} = 'editfield'

        autoCommit (1,1) logical = false
    end

    properties (SetObservable,AbortSet)
        Value (1,1) % current value
        Values (1,:)  % list of values
        Text (1,:) char = 'label' % label text
    end

    properties (SetObservable,AbortSet,SetAccess = protected)
        ValueUpdated (1,1) logical = false % flag indicating that the gui value has been updated
    end

    properties
        h_label % handle to uilabel
        h_value % handle to uieditfield or uidropdown
        container % handle to container built within parent

        colorNormal = '#f0f0f0';
        colorOnUpdate = '#00c700';
        colorOnUpdateAuto = '#7ad5ff';
        colorOnUpdateExternal = '#fad85c';
        colorOnError = '#e66367';
        
        Evaluator (1,1) % handle to custom function to handle evaluation of updated values
    end


    properties (Dependent)
        Name % Parameter.Name
    end



    methods
        % constructor
        function obj = Parameter_Control(parent,Parameter,options)
            arguments
                parent
                Parameter
                options.Type (1,:) char {mustBeMember(options.Type,{'editfield','dropdown','checkbox'})} = 'editfield'
                options.autoCommit (1,1) logical = false
            end
            obj.parent = parent;

            obj.Parameter = Parameter;
            obj.type = options.Type;

            obj.autoCommit = options.autoCommit;

            obj.create;

            if ~isa(Parameter.Parent,'hw.Software')
                addlistener(Parameter.Parent,'mode','PostSet',@obj.mode_change);
            end
            addlistener(Parameter,'Value','PostSet',@obj.value_change_external);
            % addlistener(Parameter,'Value','PostSet',@obj.commit_update);
        end


        

        function v = get.Value(obj)
            v = obj.h_value.Value;
        end

        function set.Value(obj,value)
            e.Value = value;
            obj.value_changed([],e);
        end


        function v = get.Values(obj)
            v = obj.h_value.ItemsData;
        end

        function set.Values(obj,values)
            if ~isequal(obj.type,'dropdown'), return; end
            obj.h_value.ItemsData = values;
            if isnumeric(values)
                obj.h_value.Items = string(values);
            else
                obj.h_value.Items = values;
            end
            i = ismember(values,obj.Value);
            if any(i)
                obj.h_value.Value = obj.Value;
            end
        end


        function n = get.Name(obj)
            n = obj.Parameter.Name;
        end


        function t = get.Text(obj)
            t = obj.h_label.Text;
        end

        function set.Text(obj,t)
            obj.Text = t;
            obj.h_label.Text = t;
        end



        function value_changed(obj,~,event)
            warning('off','MATLAB:structOnObject')
            event = struct(event);
            warning('on','MATLAB:structOnObject')
            if ~isfield(event,'PreviousValue')
                event.PreviousValue = []; 
            end

            % run Evaluator function, if specified. It will then be sure to
            % pass when called by hw.Parameter
            success = true;
            if isa(obj.Evaluator,'function_handle')
                [value,success] = obj.Evaluator(obj,event);
                if ~success
                    gui.Helper.timed_color_change(obj.h_label,obj.colorOnError);
                end
                event.Value = value;

            elseif isnumeric(event.Value) && (event.Value < obj.Parameter.Min || event.Value > obj.Parameter.Max)
                vprintf(0,1,'New parameter value for "%s" outside bounds [%g %g]', ...
                    obj.Name,obj.Parameter.Min,obj.Parameter.Max)
            end
           
            value = event.Value;


            obj.h_value.Value = value;
            obj.Value = value;

            obj.ValueUpdated = ~isequal(value,obj.Parameter.Value);

            if obj.autoCommit
                obj.Parameter.Value = value;
                gui.Helper.timed_color_change(obj.h_label,obj.colorOnUpdateAuto,postColor=obj.colorNormal);

            elseif ~obj.ValueUpdated && success
                obj.reset_label;

            elseif obj.ValueUpdated
                obj.h_label.BackgroundColor = obj.colorOnUpdate;
            end
        end

        function reset_label(obj)
            obj.h_label.BackgroundColor = obj.colorNormal;
            obj.ValueUpdated = false;
        end
    end


    methods (Access = protected)
        function create(obj)
            
            hl = uigridlayout(obj.parent,[1 2]);
            hl.RowHeight = {'1x'};
            hl.ColumnWidth = {'1x',100};
            hl.Padding = [0 0 0 0];
            obj.container = hl;

            obj.colorNormal = obj.container.BackgroundColor;

            P = obj.Parameter;

            h = uilabel(hl);
            h.Text = P.Name;
            h.Tooltip = P.Description;
            h.HorizontalAlignment = 'right';
            obj.h_label = h;

            switch obj.type
                case 'editfield'
                    h = uieditfield(hl,"numeric");
                    h.Value = P.Value;
                    h.ValueDisplayFormat = [P.Format P.Unit];
                    h.Limits = [P.Min P.Max];
                    if isequal(P.Type,'Integer')
                        h.RoundFractionalValues = 'on';
                    end

                case 'dropdown'
                    h = uidropdown(hl);

                case 'checkbox'
                    h = uicheckbox(hl);
            end

            if obj.autoCommit
                h.Tag = sprintf('ACPC_%s',P.Name);
            else
                h.Tag = sprintf('PC_%s',P.Name);
            end

            h.UserData = obj;
            h.ValueChangedFcn = @obj.value_changed;


            obj.h_value = h;

        end


        function mode_change(obj,src,event)
            try
                s = 'off';
                if event.AffectedObject.mode > 1
                    s = 'on';
                end

                obj.h_value.Enable = s;
                obj.h_label.Enable = s;
            end
        end

        function value_change_external(obj,~,event)
            v = event.AffectedObject.Value;
            if isempty(v), return; end % ?????
            if isequal(obj.type,'dropdown')
                % need to add to Items
                if ~ismember(v,obj.h_value.ItemsData)
                    obj.h_value.ItemsData = sort([obj.h_value.ItemsData, v]);
                    obj.h_value.Items = string(obj.h_value.Items.Data);
                end
            end
            obj.Value = v;
            obj.h_value.Value = v;
            gui.Helper.timed_color_change(obj.h_label, ...
                obj.colorOnUpdateExternal,postColor=obj.colorNormal);
        end
    end
end