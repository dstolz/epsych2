classdef Parameter_Control < handle & matlab.mixin.SetGet
    %PARAMETER_CONTROL Bind a hw.Parameter to a small UI control.
    %   gui.Parameter_Control creates a labeled UI component that displays
    %   and edits a parameter object. The control keeps the UI state in sync
    %   with the underlying parameter and can optionally commit edits
    %   immediately.
    %
    %   OBJ = gui.Parameter_Control(PARENT, PARAMETER) creates a numeric edit
    %   field for PARAMETER inside PARENT.
    %
    %   OBJ = gui.Parameter_Control(PARENT, PARAMETER, Type=TYPE,
    %   BoundProperty=PROP, autoCommit=TF) selects the UI style, the
    %   hw.Parameter field to bind, and whether user edits are written to
    %   the parameter immediately.
    %
    %   Supported TYPE values are:
    %       'editfield'  - numeric edit field with label
    %       'dropdown'   - dropdown with label
    %       'checkbox'   - checkbox
    %       'toggle'     - state button
    %       'readonly'   - label showing Parameter.ValueStr
    %       'momentary'  - push button
    %
    %   Custom validation can be attached through EvaluatorFcn. The callback
    %   is invoked as:
    %       [VALUE,SUCCESS] = EvaluatorFcn(OBJ, EVENT, PARAMETER, EXTRAARGS...)
    %   where EXTRAARGS are supplied through the EvaluatorArgs cell array.
    %   VALUE is written back to the UI, and SUCCESS controls error coloring.
    %
    % Documentation: documentation/gui/Parameter_Control.md
    % See also gui.Parameter_Monitor, gui.Parameter_Update

    properties (SetAccess = immutable)
        handle (1,1) % handle to graphics object
        parent (1,1) % handle to parent container
        Parameter (1,1) %hw.Parameter % handle to parameter

        type (1,:) char {mustBeMember(type,{'editfield','dropdown','checkbox','toggle','readonly','momentary'})} = 'editfield'

        BoundProperty (1,:) char = 'Value' % hw.Parameter property to bind

        autoCommit (1,1) logical = false
    end

    properties (SetObservable,AbortSet)
        Value (1,1) % current value
        Values (1,:)  % list of values
        Text (1,:) char = 'label' % label text


        colorNormal           = "#ffffff";
        colorOnUpdate         = "#00c700";
        colorOnUpdateAuto     = "#7ad5ff";
        colorOnUpdateExternal = "#fad85c";
        colorOnError          = "#e66367";
        end

    properties (SetObservable,AbortSet,SetAccess = protected)
        ValueUpdated (1,1) logical = false % flag indicating that the gui value has been updated
    end

    properties
        h_label % handle to uilabel
        h_uiobj % handle to uieditfield or uidropdown
        container % handle to container built within parent

        PreUpdateFcn = [] % handle to function to call before value update
        PreUpdateFcnArgs (1,:) cell = {} % optional extra arguments passed to PreUpdate
        
        EvaluatorFcn = [] % handle to custom function to handle evaluation of updated values
        EvaluatorArgs (1,:) cell = {} % optional extra arguments passed to EvaluatorFcn

        PostUpdateFcn = [] % handle to function to call after value update
        PostUpdateFcnArgs (1,:) cell = {} % optional extra arguments passed to PostUpdate
    end


    properties (Dependent)
        Name % Parameter.Name
    end


    properties (Access=private)
        hl_mode
        hl_uiobj
        hl_color
    end


    methods
        % constructor
        function obj = Parameter_Control(parent,Parameter,options)
            arguments
                parent
                Parameter
                options.Type (1,:) char {mustBeMember(options.Type,{'editfield','dropdown','checkbox','toggle','readonly','momentary','stimtype'})} = 'editfield'
                options.BoundProperty (1,:) char = 'Value'
                options.autoCommit (1,1) logical = false
            end
            obj.parent = parent;

            obj.Parameter = Parameter;
            obj.type = options.Type;
            obj.BoundProperty = options.BoundProperty;

            pNames = properties(Parameter);
            if ~ismember(obj.BoundProperty,pNames)
                error('gui:Parameter_Control:InvalidBoundProperty', ...
                    'Invalid bound property "%s" for hw.Parameter.', obj.BoundProperty);
            end

            obj.autoCommit = options.autoCommit;

            obj.create;


            % if ~isa(Parameter.Parent,'hw.Software')
                obj.hl_mode = listener(Parameter.Parent,'mode','PostSet',@obj.mode_change);
            % end
            try
                obj.hl_uiobj = listener(Parameter,obj.BoundProperty,'PostSet',@obj.value_change_external);
            catch ME
                error('gui:Parameter_Control:UnobservableBoundProperty', ...
                    'Parameter property "%s" is not observable and cannot be bound.', obj.BoundProperty);
            end
            p = properties(obj);
            p = p(startsWith(p,'color'));
            obj.hl_color = listener(obj,p,'PostSet',@obj.update_color);
        end

        function delete(obj)
            delete(obj.hl_mode)
            delete(obj.hl_uiobj)
            delete(obj.hl_color)
        end
        

        function v = get.Value(obj)
            v = obj.h_uiobj.Value;
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
            v = obj.h_uiobj.ItemsData;
        end

        function set.Values(obj,values)
            switch obj.type
                case 'dropdown'
                    obj.h_uiobj.ItemsData = values;
                    if isnumeric(values)
                        obj.h_uiobj.Items = string(values);
                    else
                        obj.h_uiobj.Items = values;
                    end
                    i = ismember(values,obj.Value);
                    if any(i)
                        obj.h_uiobj.Value = obj.Value;
                    end
            end
        end


        function n = get.Name(obj)
            n = obj.Parameter.Name;
        end

        function value = getBoundValue(obj)
            value = obj.Parameter.(obj.BoundProperty);
        end

        function setBoundValue(obj,value)
            obj.Parameter.(obj.BoundProperty) = value;
        end

        function s = boundValueText(obj)
            if isequal(obj.BoundProperty,'Value')
                s = obj.Parameter.ValueStr;
                return
            end

            v = obj.getBoundValue();
            if isempty(v)
                s = "";
                return
            end

            if isscalar(v)
                s = string(v);
            elseif isnumeric(v) || islogical(v)
                s = string(mat2str(v));
            else
                s = string(v);
            end

            s = char(s);
        end

        function t = get.Text(obj)
            if ishandle(obj.h_label)
                t = obj.h_label.Text;
            else
                t = obj.h_uiobj.Text;
            end
        end

        function set.Text(obj,t)
            obj.Text = t;

            if ishandle(obj.h_label)
                obj.h_label.Text = t;
            else
                obj.h_uiobj.Text = t;
            end
        end



        function value_changed(obj,src,event)
            warning('off','MATLAB:structOnObject')
            event = struct(event);
            warning('on','MATLAB:structOnObject')
            if ~isfield(event,'PreviousValue')
                event.PreviousValue = []; 
            end

            % run pre-update function, if specified. This allows for any necessary setup before the value is changed, such as temporarily disabling randomization or other PostUpdate behavior when repeating a trial after an Abort.
            if isa(obj.PreUpdateFcn,'function_handle')
                obj.PreUpdateFcn(obj,event,obj.Parameter,obj.PreUpdateFcnArgs{:});
            end

            % run EvaluatorFcn function, if specified. It will then be sure to
            % pass when called by hw.Parameter
            success = true;
            if isa(obj.EvaluatorFcn,'function_handle')
                [value,success] = obj.EvaluatorFcn(obj,event,obj.Parameter,obj.EvaluatorArgs{:});
                if ~success
                    gui.Helper.timed_color_change(obj.h_uiobj,obj.colorOnError);
                end
                event.Value = value;

            elseif isfield(event,'EventName') && isequal(event.EventName,'ButtonPushed')
                obj.Parameter.Trigger;
                return
                
            elseif isnumeric(event.Value) && (event.Value < obj.Parameter.Min || event.Value > obj.Parameter.Max)
                vprintf(0,1,'New parameter value for "%s" outside bounds [%g %g]', ...
                    obj.Name,obj.Parameter.Min,obj.Parameter.Max)
            end
           
            value = event.Value;

            obj.h_uiobj.Value = value;
            % obj.Value = value;

            obj.ValueUpdated = ~isequal(value,obj.getBoundValue());

            % run post-update function, if specified. This allows for any necessary updates after the value is changed, such as re-enabling randomization when repeating a trial after an Abort, or updating other controls based on the new value.
            if isa(obj.PostUpdateFcn,'function_handle')
                obj.PostUpdateFcn(obj,event,obj.Parameter,obj.PostUpdateFcnArgs{:});
            end

            if obj.autoCommit
                if isempty(src), return; end
                obj.setBoundValue(value);
                % gui.Helper.timed_color_change(obj.h_uiobj,obj.colorOnUpdateAuto,postColor=obj.colorNormal);
                % obj.indicate_change;

            elseif ~obj.ValueUpdated && success
                obj.reset_label;

            elseif obj.ValueUpdated
                obj.h_uiobj.BackgroundColor = obj.colorOnUpdate;
            end
        end

        function reset_label(obj)
            obj.h_uiobj.BackgroundColor = obj.colorNormal;
            obj.ValueUpdated = false;
        end




        function update_color(obj,src,event)
            % s = src.Name;
            obj.h_uiobj.BackgroundColor = obj.colorNormal;
        end
    end


    methods (Access = protected)
        function create(obj)
            
            hl = uigridlayout(obj.parent,[1 2]);
            hl.RowHeight = {'1x'};
            hl.Padding = [0 0 0 0];
            obj.container = hl;


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
                    h.Value = obj.getBoundValue();
                    %h.ValueDisplayFormat = [P.Format ' ' P.Unit];
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

                case 'momentary'
                    hl.ColumnWidth = {'1x'};
                    h = uibutton(hl,'push');
                    h.Layout.Column = [1 2];
                    h.Text = P.Name;

                case 'stimtype'
                    hl.ColumnWidth = {'1x'};
                    h = uibutton(hl,'push');
                    h.Layout.Column = [1 2];
                    v = P.Value;
                    if isempty(v)
                        h.Text = sprintf('%s: [none]', P.Name);
                    else
                        h.Text = sprintf('%s: %s', P.Name, P.ValueStr);
                    end

                case 'readonly'
                    hl.ColumnWidth = {'1x'};
                    h = uilabel(hl);
                    h.Layout.Column = [1 2];
                    h.Text = obj.boundValueText();
                    h.HorizontalAlignment = 'center';
            end

            if isfield(h,'BackgroundColor')
                obj.colorNormal = h.BackgroundColor;
            end

            if isprop(h,'Value') && ~isequal(obj.type,'dropdown')
                h.Value = obj.getBoundValue();
            end

            if obj.autoCommit
                h.Tag = sprintf('ACPC_%s',P.Name);
            else
                h.Tag = sprintf('PC_%s',P.Name);
            end

            h.UserData = obj;

            switch obj.type
                case 'readonly'
                    % do nothing
                case 'momentary'
                    h.ButtonPushedFcn = @obj.value_changed;
                case 'stimtype'
                    h.ButtonPushedFcn = @obj.open_stimtype_gui;
                otherwise
                    h.ValueChangedFcn = @obj.value_changed;
            end


            obj.h_uiobj = h;

        end


        function mode_change(obj,src,event)
            try
                s = 'off';
                if event.AffectedObject.mode > 1
                    s = 'on';
                end

                obj.h_uiobj.Enable = s;
                if ishandle(obj.h_label)
                    obj.h_label.Enable = s;
                end
            end
        end

        function value_change_external(obj,~,event)
            v = event.AffectedObject.(obj.BoundProperty);
            if isempty(v), return; end % ?????

            % obj.Value = v;
            if isprop(obj.h_uiobj,'Value')
                obj.h_uiobj.Value = v;
            end

            obj.indicate_change;
        end


        function indicate_change(obj)
            v = obj.getBoundValue();

            switch obj.type
                case 'dropdown'
                    % need to add to Items
                    if ~ismember(v,obj.h_uiobj.ItemsData)
                        obj.h_uiobj.ItemsData = sort([obj.h_uiobj.ItemsData, v]);
                        obj.h_uiobj.Items = string(obj.h_uiobj.Items.Data);
                    end
                    gui.Helper.timed_color_change(obj.h_uiobj, ...
                        obj.colorOnUpdateExternal,postColor=obj.colorNormal);

                case 'readonly'
                    obj.h_uiobj.Text = obj.boundValueText();
                    gui.Helper.timed_color_change(obj.h_uiobj, ...
                        obj.colorOnUpdateExternal,postColor=obj.colorNormal);
                    

                case 'checkbox'
                    gui.Helper.timed_color_change(obj.h_uiobj, ...
                        obj.colorOnUpdateExternal,postColor=obj.colorNormal);
                    

                case {'toggle','momentary'}
                    if v
                        obj.h_uiobj.BackgroundColor = obj.colorOnUpdate;
                    else
                        obj.h_uiobj.BackgroundColor = obj.colorNormal;
                    end

                case 'stimtype'
                    P = obj.Parameter;
                    if isempty(P.Value)
                        obj.h_uiobj.Text = sprintf('%s: [none]', P.Name);
                    else
                        obj.h_uiobj.Text = sprintf('%s: %s', P.Name, P.ValueStr);
                    end
                    gui.Helper.timed_color_change(obj.h_uiobj, ...
                        obj.colorOnUpdateExternal,postColor=obj.colorNormal);

            end

        end

        function open_stimtype_gui(obj, ~, ~)
            % open_stimtype_gui - Open a non-modal figure to configure or pick a StimType.
            % If Parameter.Value is empty, shows a dropdown of available StimType
            % subclasses so the user can create one. If Value is already set,
            % opens the StimType property editor via create_gui().
            P = obj.Parameter;
            fig = uifigure('Name', sprintf('StimType — %s', P.Name), ...
                'WindowStyle', 'normal', ...
                'AutoResizeChildren', 'off');

            if isempty(P.Value)
                classList = stimgen.StimType.list();
                g = uigridlayout(fig, [2 2]);
                g.ColumnWidth = {'1x', '1x'};
                g.RowHeight   = {30, 30};
                uilabel(g, 'Text', 'Stimulus type:', 'HorizontalAlignment', 'right');
                dd = uidropdown(g, 'Items', classList, 'Value', classList{1});
                uilabel(g, 'Text', '');
                uibutton(g, 'push', 'Text', 'Create', ...
                    'ButtonPushedFcn', @(~,~) obj.create_stimtype_from_dropdown(dd, fig));
            else
                P.Value.create_gui(fig);
            end
        end

        function create_stimtype_from_dropdown(obj, dd, fig)
            % create_stimtype_from_dropdown - Construct selected StimType and assign to Parameter.
            className = sprintf('stimgen.%s', dd.Value);
            stim = feval(className);
            obj.Parameter.Value = stim;
            close(fig);
            obj.open_stimtype_gui([], []);
        end
    end
end
