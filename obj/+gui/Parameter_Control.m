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

        type (1,:) char {mustBeMember(type,{'editfield','dropdown','checkbox','toggle','readonly','momentary','stimtype'})} = 'editfield'

        BoundProperty (1,:) char {mustBeMember(BoundProperty,{'Value','Values','Min','Max','isRandom','Expression','Description','Unit','Format'})} = 'Value' % hw.Parameter property to bind

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

        % epsych.Runtime (optional). When set, an autoCommit Value edit is
        % also pushed into RUNTIME.TRIALS.trials. Without this, the edit
        % lives only on the hw.Parameter: the dispatcher re-applies the
        % stale trial-table value at the next trial boundary and a phase
        % save records the table value, silently reverting the edit both
        % ways. Leave empty for session-control toggles (Reminder, Deliver
        % Trials, ...) -- those rely on the table re-assert to self-clear.
        Runtime = []

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
        hl_bounds
        hl_color
        committing_ (1,1) logical = false % true while an autoCommit write-back is in flight; suppresses the re-entrant PostUpdateFcn from value_change_external
    end


    methods
        % constructor
        function obj = Parameter_Control(parent,Parameter,options)
            arguments
                parent
                Parameter
                options.Type (1,:) char {mustBeMember(options.Type,{'auto','editfield','dropdown','checkbox','toggle','readonly','momentary','stimtype'})} = 'auto'
                options.BoundProperty (1,:) char {mustBeMember(options.BoundProperty,{'Value','Values','Min','Max','isRandom','Expression','Description','Unit','Format'})} = 'Value'
                options.autoCommit (1,1) logical = false
                options.Text (1,:) char = Parameter.Name
                options.Runtime = [] % epsych.Runtime; see the Runtime property
            end
            obj.parent = parent;
            obj.Runtime = options.Runtime;

            obj.Parameter = Parameter;
            controlType = options.Type;
            if isequal(controlType, 'auto')
                controlType = obj.defaultTypeFromParameter(Parameter);
            end
            obj.type = controlType;
            obj.BoundProperty = options.BoundProperty;
            obj.Text = options.Text;

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
            % Bounds can change at runtime (Min/Max sibling controls, phase
            % loads); an edit field frozen at its creation-time Limits then
            % silently rejects values the parameter now allows.
            if isequal(obj.type,'editfield')
                obj.hl_bounds = listener(Parameter,{'Min','Max'},'PostSet',@obj.bounds_changed);
            end
            p = properties(obj);
            p = p(startsWith(p,'color'));
            obj.hl_color = listener(obj,p,'PostSet',@obj.update_color);
        end

        function delete(obj)
            delete(obj.hl_mode)
            delete(obj.hl_uiobj)
            delete(obj.hl_bounds)
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
            v = obj.Parameter.Values;
        end

        %{
         Note: for dropdown controls, the Values property is determined by the bound Parameter.Values, so setting it directly on the control will update the Parameter.Values. For other control types, Values is not used and setting it will have no effect.
         This is a bit of an odd design but allows for convenient management of dropdown options through the underlying Parameter.
         If we wanted to allow setting Values directly on the control for non-dropdown types, we would need to implement additional logic to handle that, and it could potentially lead to confusion about where the source of truth is for the list of values. For now, we'll keep it simple and only allow Values to be set through the Parameter for dropdown controls.
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
        %}

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


        function set.Text(obj,t)
            obj.Text = t;

            if ishandle(obj.h_label)
                obj.h_label.Text = t;
            elseif ishandle(obj.h_uiobj)
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

            elseif isequal(obj.BoundProperty,'Value') && isnumeric(event.Value) ...
                    && (event.Value < obj.Parameter.Min || event.Value > obj.Parameter.Max)
                % Only a Value edit is subject to the parameter's bounds. A control
                % bound to Min/Max IS the bound: widening it (raising Max, lowering
                % Min) is legitimate and must not be reported as out of bounds.
                vprintf(0,1,'New parameter value for "%s" outside bounds [%g %g]', ...
                    obj.Name,obj.Parameter.Min,obj.Parameter.Max)
            end

            value = event.Value;

            obj.h_uiobj.Value = value;
            % obj.Value = value;

            obj.ValueUpdated = ~isequal(value,obj.getBoundValue());

            % run post-update function, if specified. This allows for any necessary updates after the value is changed, such as re-enabling randomization when repeating a trial after an Abort, or updating other controls based on the new value.
            obj.runPostUpdateFcn(event);

            if obj.autoCommit
                if isempty(src), return; end
                % Committing the value re-triggers the bound property's PostSet
                % listener (value_change_external). Guard the write-back so that path
                % does not run PostUpdateFcn a second time -- it already ran just above.
                obj.committing_ = true;
                try
                    obj.setBoundValue(value);
                catch ME
                    obj.committing_ = false;
                    rethrow(ME)
                end
                obj.committing_ = false;

                obj.syncRuntimeTrials_();

            elseif ~obj.ValueUpdated && success
                obj.reset_label;

            elseif obj.ValueUpdated
                obj.set_color_(obj.colorOnUpdate);
            end
        end

        function reset_label(obj)
            obj.set_color_(obj.colorNormal);
            obj.ValueUpdated = false;
        end

        function reset_value(obj)
            % reset_value(obj)
            % Discard an uncommitted edit by restoring the control to the
            % value currently held by the bound parameter property. No-op
            % when there is nothing pending.
            if ~obj.ValueUpdated, return; end

            v = obj.getBoundValue();
            if isprop(obj.h_uiobj,'Value') && ~isempty(v)
                obj.ensureDropdownItem_(obj.h_uiobj,v);
                obj.h_uiobj.Value = v;
            end

            obj.reset_label;

            % Dependent controls were resynced against the discarded edit when
            % the user made it, so run the hook again against the restored
            % value -- otherwise e.g. min/max fields stay enabled after
            % reverting the isRandom checkbox that enabled them.
            e = struct('PreviousValue', [], 'EventName', 'Reset');
            e.Value = v;
            obj.runPostUpdateFcn(e);
        end




        function update_color(obj,src,event)
            % s = src.Name;
            obj.set_color_(obj.colorNormal);
        end


        function runPostUpdateFcn(obj, event)
            % runPostUpdateFcn(obj, event)
            % Invoke the optional PostUpdateFcn with the standard argument list
            % (control, event, bound Parameter, extra args). Shared by the
            % user-driven path (value_changed) and the external-change path
            % (value_change_external) so dependent controls stay in sync no
            % matter what triggered the value change.
            if isa(obj.PostUpdateFcn,'function_handle')
                obj.PostUpdateFcn(obj,event,obj.Parameter,obj.PostUpdateFcnArgs{:});
            end
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
                    h.Text = obj.Text;
                    h.Tooltip = P.Description;
                    h.HorizontalAlignment = 'right';
                    obj.h_label = h;

                    h = uieditfield(hl,"numeric");
                    h.Value = obj.getBoundValue();
                    %h.ValueDisplayFormat = [P.Format ' ' P.Unit];
                    h.Limits = obj.widgetLimits_();
                    if isequal(P.Type,'Integer')
                        h.RoundFractionalValues = 'on';
                    end

                case 'dropdown'
                    hl.ColumnWidth = {'1x',100};

                    h = uilabel(hl);
                    h.Text = obj.Text;
                    h.Tooltip = P.Description;
                    h.HorizontalAlignment = 'right';
                    obj.h_label = h;

                    h = uidropdown(hl);
                    vals = P.Values; % 1xN cell, one trial level per element
                    h.ItemsData = vals;
                    % Items must be char/string labels; ItemsData keeps raw values
                    if iscell(vals)
                        h.Items = cellfun(@(x) char(string(x)), vals, UniformOutput=false);
                    elseif isnumeric(vals) || islogical(vals)
                        h.Items = string(vals);
                    else
                        h.Items = vals;
                    end
                    v = obj.getBoundValue();
                    if ~isempty(v)
                        % Show the current value even if it isn't among the
                        % design-time Values; ensureDropdownItem_ adds it.
                        obj.ensureDropdownItem_(h, v);
                        h.Value = v;
                    end

                case 'checkbox'
                    hl.ColumnWidth = {'1x'};
                    h = uicheckbox(hl);
                    h.Text = obj.Text;
                    obj.colorNormal = '#000';

                case 'toggle'
                    hl.ColumnWidth = {'1x'};
                    h = uibutton(hl,'state');
                    h.Layout.Column = [1 2];
                    h.Text = obj.Text;

                case 'momentary'
                    hl.ColumnWidth = {'1x'};
                    h = uibutton(hl,'push');
                    h.Layout.Column = [1 2];
                    h.Text = obj.Text;

                case 'stimtype'
                    hl.ColumnWidth = {'1x'};
                    h = uibutton(hl,'push');
                    h.Layout.Column = [1 2];
                    h.Text = obj.stimtypeText_();

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

            % PostSet fires on every write, not only on writes that change the
            % value -- a parameter re-applied at the start of each trial would
            % otherwise flash a control that never moved, making the indication
            % meaningless. Compare against what is on screen before overwriting
            % it. An autoCommit write-back always indicates, since there the
            % flash confirms this control's own commit reached the parameter.
            changed = obj.displayDiffers_(v);

            % obj.Value = v;
            if isprop(obj.h_uiobj,'Value')
                % For dropdowns, the value may not be among the design-time
                % Values (e.g. when loading a saved phase). Add it before
                % assigning, otherwise the dropdown rejects the value.
                obj.ensureDropdownItem_(obj.h_uiobj, v);
                obj.h_uiobj.Value = v;
            end

            if changed || obj.committing_
                obj.indicate_change;
            elseif obj.ValueUpdated
                % The parameter arrived at the value this control was already
                % showing, so the pending edit is satisfied -- drop the
                % uncommitted-edit highlight instead of leaving it stuck on.
                obj.reset_label;
            end

            % Mirror the user-driven path: a parameter changed from outside this
            % control (loading a phase, a linked-parameter update, etc.) should still
            % run the PostUpdateFcn so dependent UI stays in sync -- e.g. toggling a
            % checkbox-bound isRandom must enable/disable the related min/max fields.
            % Skip while an autoCommit write-back is in flight, since value_changed
            % already ran PostUpdateFcn for that same change.
            if ~obj.committing_
                % Assign Value after construction so a cell-valued v is not expanded
                % into a struct array by struct().
                e = struct('PreviousValue', [], 'EventName', 'PostSet');
                e.Value = v;
                obj.runPostUpdateFcn(e);
            end
        end


        function indicate_change(obj)
            v = obj.getBoundValue();

            switch obj.type
                case 'editfield'
                    % Blue confirms this control's own autoCommit write-back;
                    % yellow flags a change from outside (phase load, linked
                    % parameter). Without this, edit fields gave no feedback at
                    % all and a committed change was indistinguishable from a
                    % rejected one.
                    if obj.committing_
                        c = obj.colorOnUpdateAuto;
                    else
                        c = obj.colorOnUpdateExternal;
                    end
                    gui.Helper.timed_color_change(obj.h_uiobj, c, postColor=obj.colorNormal);

                case 'dropdown'
                    obj.ensureDropdownItem_(obj.h_uiobj, v);
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
                    obj.h_uiobj.Text = obj.stimtypeText_();
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
                classList = obj.concreteStimTypes_();
                if isempty(classList)
                    uilabel(uigridlayout(fig, [1 1]), ...
                        'Text', 'No concrete stimgen.StimType subclasses were found.', ...
                        'HorizontalAlignment', 'center');
                    return
                end
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
            try
                stim = feval(className);
            catch ME
                vprintf(0, 1, ME);
                uialert(fig, sprintf(['Could not create "%s".\n\n%s\n\nIf this persists, ' ...
                    'the stimgen submodule may be out of step with EPsych; see ' ...
                    'documentation/stimgen.md.'], className, ME.message), ...
                    'Stimulus Creation Failed');
                return
            end
            obj.Parameter.Value = stim;
            close(fig);
            obj.open_stimtype_gui([], []);
        end
    end

    methods (Access = private)
        function syncRuntimeTrials_(obj)
            % syncRuntimeTrials_(obj)
            % Push a just-committed Value into the runtime trial table.
            % Only a Value edit has a trials-table column; a bound-property
            % edit (Min, Max, isRandom, ...) is host-side parameter state
            % with nothing to sync. updateTrialsFromParameters is a no-op
            % before the session compiles TRIALS.
            if isempty(obj.Runtime) || ~isequal(obj.BoundProperty,'Value')
                return
            end
            obj.Runtime.updateTrialsFromParameters(obj.Parameter);
        end

        function lims = widgetLimits_(obj)
            % lims = widgetLimits_(obj)
            % Edit-field Limits for the bound property. A Value control is
            % constrained to the parameter's bounds. A control bound to Min or
            % Max must not be constrained by the very bound it edits, or that
            % bound could never be widened from the GUI (e.g. raising Max above
            % its current value); it is only constrained by the opposite bound.
            P = obj.Parameter;
            switch obj.BoundProperty
                case 'Value'
                    lims = [P.Min P.Max];
                case 'Min'
                    lims = [-Inf P.Max];
                case 'Max'
                    lims = [P.Min Inf];
                otherwise
                    lims = [-Inf Inf];
            end
        end

        function bounds_changed(obj,~,~)
            % bounds_changed(obj,~,~)
            % Refresh the edit field's Limits after the parameter's Min/Max
            % change. The displayed value is clamped first because assigning
            % Limits that exclude the current widget value errors.
            if ~isprop(obj.h_uiobj,'Limits'), return; end
            lims = obj.widgetLimits_();
            v = obj.h_uiobj.Value;
            if v < lims(1) || v > lims(2)
                obj.h_uiobj.Value = min(max(v,lims(1)),lims(2));
            end
            obj.h_uiobj.Limits = lims;
        end

        function tf = displayDiffers_(obj, v)
            % tf = displayDiffers_(obj, v)
            % True when v is not what the control is currently showing. The
            % comparison is per control type because the "displayed value"
            % lives in a different property for each: Value for the entry
            % widgets, Text for the label-like ones. A control with neither
            % (a momentary push button) has nothing to compare, so it always
            % counts as changed.
            switch obj.type
                case 'readonly'
                    tf = ~isequal(obj.h_uiobj.Text, obj.boundValueText());

                case 'stimtype'
                    tf = ~isequal(obj.h_uiobj.Text, obj.stimtypeText_());

                otherwise
                    tf = ~isprop(obj.h_uiobj,'Value') || ~isequal(obj.h_uiobj.Value, v);
            end
        end

        function s = stimtypeText_(obj)
            % s = stimtypeText_(obj)
            % Button caption for a 'stimtype' control: the parameter name and
            % the stimulus it currently holds.
            P = obj.Parameter;
            if isempty(P.Value)
                s = sprintf('%s: [none]', P.Name);
            else
                s = sprintf('%s: %s', P.Name, P.ValueStr);
            end
        end

        function set_color_(obj, color)
            % set_color_(obj, color)
            % Paint the state indication onto whichever color property the
            % widget exposes. uicheckbox has no BackgroundColor -- FontColor
            % is its only color affordance -- so follow the same
            % BackgroundColor/Color/FontColor precedence that
            % gui.Helper.timed_color_change uses, keeping the two paths
            % consistent for a given control type.
            if isprop(obj.h_uiobj,'BackgroundColor')
                obj.h_uiobj.BackgroundColor = color;
            elseif isprop(obj.h_uiobj,'Color')
                obj.h_uiobj.Color = color;
            elseif isprop(obj.h_uiobj,'FontColor')
                obj.h_uiobj.FontColor = color;
            end
        end

        function ensureDropdownItem_(obj, h, v)
            % ensureDropdownItem_(obj, h, v)
            % Guarantee v is present in dropdown handle h's ItemsData so that
            % assigning h.Value = v passes MATLAB's validation. Values loaded
            % from saved phases (or a Parameter's current Value) may not be
            % among the design-time Parameter.Values used to build the
            % dropdown. No-op for non-dropdown controls.
            if ~isequal(obj.type,'dropdown'), return; end
            itemsData = h.ItemsData;
            if ~iscell(itemsData)
                itemsData = num2cell(itemsData);
            end
            if any(cellfun(@(x) isequal(x,v), itemsData)), return; end
            newData = [itemsData, {v}];
            h.ItemsData = newData;
            h.Items = cellfun(@(x) char(string(x)), newData, UniformOutput=false);
        end
    end

    methods (Access = private, Static)
        function names = concreteStimTypes_()
            % names = concreteStimTypes_()
            % Instantiable stimgen.StimType subclass names for the picker.
            %
            % stimgen.StimType.list globs +stimgen/*.m against a hardcoded
            % blocklist, so any non-instantiable file added to that package
            % reaches feval as if it were a stimulus. stimgen is a submodule
            % that versions on its own cadence, so filter on class metadata
            % rather than trusting what list returns.
            names = stimgen.StimType.list();
            keep  = cellfun(@(n) isConcreteStimType("stimgen." + n), names);
            names = names(keep);
        end

        function controlType = defaultTypeFromParameter(Parameter)
            candidates = {'readonly','momentary','stimtype','checkbox','dropdown','editfield'};
            scores = zeros(1, numel(candidates));

            % Access rules
            if isequal(Parameter.Access, 'Read')
                scores(strcmp(candidates,'readonly')) = scores(strcmp(candidates,'readonly')) + 100;
                scores(strcmp(candidates,'editfield')) = scores(strcmp(candidates,'editfield')) - 50;
                scores(strcmp(candidates,'checkbox')) = scores(strcmp(candidates,'checkbox')) - 50;
                scores(strcmp(candidates,'dropdown')) = scores(strcmp(candidates,'dropdown')) - 50;
                scores(strcmp(candidates,'momentary')) = scores(strcmp(candidates,'momentary')) - 50;
            end

            % Trigger behavior should dominate primitive type.
            if Parameter.isTrigger
                scores(strcmp(candidates,'momentary')) = scores(strcmp(candidates,'momentary')) + 120;
                scores(strcmp(candidates,'checkbox')) = scores(strcmp(candidates,'checkbox')) - 40;
                scores(strcmp(candidates,'dropdown')) = scores(strcmp(candidates,'dropdown')) - 40;
                scores(strcmp(candidates,'editfield')) = scores(strcmp(candidates,'editfield')) - 40;
            end

            % Semantic type preferences
            switch Parameter.Type
                case 'StimType'
                    scores(strcmp(candidates,'stimtype')) = scores(strcmp(candidates,'stimtype')) + 110;
                    scores(strcmp(candidates,'editfield')) = scores(strcmp(candidates,'editfield')) - 40;
                case 'Boolean'
                    scores(strcmp(candidates,'checkbox')) = scores(strcmp(candidates,'checkbox')) + 80;
                    scores(strcmp(candidates,'editfield')) = scores(strcmp(candidates,'editfield')) - 20;
                case {'Buffer','Coefficient Buffer'}
                    scores(strcmp(candidates,'readonly')) = scores(strcmp(candidates,'readonly')) + 60;
                    scores(strcmp(candidates,'editfield')) = scores(strcmp(candidates,'editfield')) - 30;
                case {'Float','Integer','String','File','Undefined'}
                    scores(strcmp(candidates,'editfield')) = scores(strcmp(candidates,'editfield')) + 25;
            end

            % Discrete values are often best represented as dropdown.
            if numel(Parameter.Values) > 1
                nVals = numel(Parameter.Values);
                if nVals <= 40
                    scores(strcmp(candidates,'dropdown')) = scores(strcmp(candidates,'dropdown')) + 70;
                else
                    scores(strcmp(candidates,'dropdown')) = scores(strcmp(candidates,'dropdown')) + 15;
                end
                scores(strcmp(candidates,'editfield')) = scores(strcmp(candidates,'editfield')) - 10;
            end

            % Small finite integer ranges can work well as dropdown choices.
            if isequal(Parameter.Type,'Integer') && isfinite(Parameter.Min) && isfinite(Parameter.Max)
                rangeSpan = Parameter.Max - Parameter.Min;
                if rangeSpan >= 0 && rangeSpan <= 20 && floor(rangeSpan) == rangeSpan
                    scores(strcmp(candidates,'dropdown')) = scores(strcmp(candidates,'dropdown')) + 35;
                end
            end

            % Array-like values are poor fits for scalar entry controls.
            if Parameter.isArray
                scores(strcmp(candidates,'readonly')) = scores(strcmp(candidates,'readonly')) + 40;
                scores(strcmp(candidates,'editfield')) = scores(strcmp(candidates,'editfield')) - 20;
                scores(strcmp(candidates,'checkbox')) = scores(strcmp(candidates,'checkbox')) - 20;
            end

            [~, bestIdx] = max(scores);
            controlType = candidates{bestIdx};
        end
    end
end
