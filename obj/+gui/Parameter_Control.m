classdef Parameter_Control < handle & matlab.mixin.SetGet

        properties (SetAccess = immutable)
            handle (1,1) % handle to graphics object
            parent (1,1) % handle to parent container
            Parameter (1,1) hw.Parameter % handle to parameter

            type (1,:) char {mustBeMember(type,{'editfield','dropdown'})} = 'editfield'           

            autoCommit (1,1) logical = false
        end

        properties (SetObservable = true)
            ValueUpdated (1,1) logical = false % 
        end

        properties
            h_label % handle to uilabel
            h_value % handle to uieditfield or uidropdown
            container % handle to container built within parent

            color_updated (1,:) double = [0 .8 0]
        end



        methods
            % constructor
            function obj = Parameter_Control(parent,Parameter,options)
                arguments
                    parent
                    Parameter
                    options.Type (1,:) char {mustBeMember(options.Type,{'editfield','dropdown'})} = 'editfield'
                    options.autoCommit (1,1) logical = false
                end
                obj.parent = parent;
                
                obj.Parameter = Parameter;
                obj.type = options.Type;
                
                obj.autoCommit = options.autoCommit;

                obj.create;
            end


            function value_changed(obj,src,event)
                if isequal(event.Value,obj.Parameter.Value)
                    obj.reset_label;
                    return
                end
                
                obj.h_label.BackgroundColor = obj.color_updated;
                if obj.autoCommit
                    obj.Parameter.Value = event.Value;
                    drawnow limitrate
                    obj.reset_label;
                else
                    obj.ValueUpdated = true;
                end
            end

            function reset_label(obj)
                obj.h_label.BackgroundColor = 'none';
            end
        end


        methods (Access = protected)
            function create(obj)
                hl = uigridlayout(obj.parent,[1 2]);
                hl.RowHeight = {'1x'};
                hl.ColumnWidth = {'1x',100};
                hl.Padding = [0 0 0 0];
                obj.container = hl;


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
        end
end