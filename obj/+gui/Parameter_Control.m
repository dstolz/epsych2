classdef Parameter_Control < handle & matlab.mixin.SetGet

    properties (SetAccess = immutable)
        handle (1,1) % handle to graphics object
        parent (1,1) % handle to parent container
        Parameter (1,1) %hw.Parameter % handle to parameter

        type (1,:) char {mustBeMember(type,{'editfield','dropdown','checkbox','toggle','readonly'})} = 'editfield'

        autoCommit (1,1) logical = false
    end

    properties (SetObservable,AbortSet)
        Value (1,1) % current value
        Values (1,:)  % list of values
        Text (1,:) char = 'label' % label text


        colorNormal = '#f0f0f0';
        colorOnUpdate = '#00c700';
        colorOnUpdateAuto = '#7ad5ff';
        colorOnUpdateExternal = '#fad85c';
        colorOnError = '#e66367';
    end

    properties (SetObservable,AbortSet,SetAccess = protected)
        ValueUpdated (1,1) logical = false % flag indicating that the gui value has been updated
    end

    properties
        h_label % handle to uilabel
        h_value % handle to uieditfield or uidropdown
        container % handle to container built within parent

        
        Evaluator (1,1) % handle to custom function to handle evaluation of updated values
    end


    properties (Dependent)
        Name % Parameter.Name
    end


    properties (Access=private)
        hl_mode
        hl_Value
        hl_color
    end


    methods
        % constructor
        function obj = Parameter_Control(parent,Parameter,options)
            arguments
                parent
                Parameter
                options.Type (1,:) char {mustBeMember(options.Type,{'editfield','dropdown','checkbox','toggle','readonly'})} = 'editfield'
                options.autoCommit (1,1) logical = false
            end
            obj.parent = parent;

            obj.Parameter = Parameter;
            obj.type = options.Type;

            obj.autoCommit = options.autoCommit;

            obj.create;


            if ~isa(Parameter.Parent,'hw.Software')
                obj.hl_mode = listener(Parameter.Parent,'mode','PostSet',@obj.mode_change);
            end
            obj.hl_Value = listener(Parameter,'Value','PostSet',@obj.value_change_external);
            p = properties(obj);
            p = p(startsWith(p,'color'));
            obj.hl_color = listener(obj,p,'PostSet',@obj.update_color);
        end

        function delete(obj)
            delete(obj.hl_mode)
            delete(obj.hl_Value)
            delete(obj.hl_color)
        end
        

        function v = get.Value(obj)
            v = obj.h_value.Value;
        end

        function set.Value(obj,value)
            if isequal(obj.type,'dropdown') && isnumeric(obj.Value)
                % necessary due to possible comparison with single or other
                % types
                i = isapprox(obj.Values,value,'loose');
                if any(i)
                    value = obj.Values(i);
                else
                    vprintf(0,1,'Invalid value for "%s": %g',obj.Parameter.Name,value)
                end
            end

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
            if ishandle(obj.h_label)
                t = obj.h_label.Text;
            else
                t = obj.h_value.Text;
            end
        end

        function set.Text(obj,t)
            obj.Text = t;

            if ishandle(obj.h_label)
                obj.h_label.Text = t;
            else
                obj.h_value.Text = t;
            end
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
                    gui.Helper.timed_color_change(obj.h_value,obj.colorOnError);
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
                % gui.Helper.timed_color_change(obj.h_value,obj.colorOnUpdateAuto,postColor=obj.colorNormal);
                obj.indicate_change;

            elseif ~obj.ValueUpdated && success
                obj.reset_label;

            elseif obj.ValueUpdated
                obj.h_value.BackgroundColor = obj.colorOnUpdate;
            end
        end

        function reset_label(obj)
            obj.h_value.BackgroundColor = obj.colorNormal;
            obj.ValueUpdated = false;
        end




        function update_color(obj,src,event)
            % s = src.Name;
            obj.h_value.BackgroundColor = obj.colorNormal;
        end
    end


    methods (Access = protected)
        function create(obj)
            
            hl = uigridlayout(obj.parent,[1 2]);
            hl.RowHeight = {'1x'};
            hl.Padding = [0 0 0 0];
            obj.container = hl;

            obj.colorNormal = obj.container.BackgroundColor;

            P = obj.Parameter;


            switch obj.type
                case 'editfield'
                    hl.ColumnWidth = {'1x',100};

                    h = uilabel(hl);
                    h.Text = P.Name;
                    h.Tooltip = P.Description;
                    h.HorizontalAlignment = 'right';
                    obj.h_label = h;

                    h = uieditfield(hl,"numeric");
                    h.Value = P.Value;
                    h.ValueDisplayFormat = [P.Format P.Unit];
                    h.Limits = [P.Min P.Max];
                    if isequal(P.Type,'Integer')
                        h.RoundFractionalValues = 'on';
                    end

                case 'dropdown'
                    hl.ColumnWidth = {'1x',100};

                    h = uilabel(hl);
                    h.Text = P.Name;
                    h.Tooltip = P.Description;
                    h.HorizontalAlignment = 'right';
                    obj.h_label = h;

                    h = uidropdown(hl);

                case 'checkbox'
                    hl.ColumnWidth = {'1x'};
                    h = uicheckbox(hl);
                    h.Text = P.Name;
                    obj.colorNormal = '#000';

                case 'toggle'
                    hl.ColumnWidth = {'1x'};
                    h = uibutton(hl,'state');
                    h.Layout.Column = [1 2];
                    h.Text = P.Name;

                case 'readonly'
                    hl.ColumnWidth = {'1x'};
                    h = uilabel(hl);
                    h.Layout.Column = [1 2];
                    h.Text = P.ValueStr;
                    h.HorizontalAlignment = 'center';
            end

            if obj.autoCommit
                h.Tag = sprintf('ACPC_%s',P.Name);
            else
                h.Tag = sprintf('PC_%s',P.Name);
            end

            h.UserData = obj;

            if ~isequal(obj.type,'readonly')
                h.ValueChangedFcn = @obj.value_changed;
            end


            obj.h_value = h;

        end


        function mode_change(obj,src,event)
            try
                s = 'off';
                if event.AffectedObject.mode > 1
                    s = 'on';
                end

                obj.h_value.Enable = s;
                if ishandle(obj.h_label)
                    obj.h_label.Enable = s;
                end
            end
        end

        function value_change_external(obj,~,event)
            v = event.AffectedObject.Value;
            if isempty(v), return; end % ?????


            obj.Value = v;
            obj.h_value.Value = v;

            obj.indicate_change;
        end


        function indicate_change(obj)
            v = obj.Value;

            switch obj.type
                case 'dropdown'
                    % need to add to Items
                    if ~ismember(v,obj.h_value.ItemsData)
                        obj.h_value.ItemsData = sort([obj.h_value.ItemsData, v]);
                        obj.h_value.Items = string(obj.h_value.Items.Data);
                    end
                    gui.Helper.timed_color_change(obj.h_value, ...
                        obj.colorOnUpdateExternal,postColor=obj.colorNormal);

                case 'readonly'
                    obj.h_value.Text = obj.Parameter.ValueStr;
                    gui.Helper.timed_color_change(obj.h_value, ...
                        obj.colorOnUpdateExternal,postColor=obj.colorNormal);
                    

                case 'checkbox'
                    gui.Helper.timed_color_change(obj.h_value, ...
                        obj.colorOnUpdateExternal,postColor=obj.colorNormal);
                    

                case 'toggle'
                    if v
                        obj.h_value.BackgroundColor = obj.colorOnUpdate;
                    else
                        obj.h_value.BackgroundColor = obj.colorNormal;
                    end
                    
            end

        end
    end
end