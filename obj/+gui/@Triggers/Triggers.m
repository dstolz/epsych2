classdef Triggers < gui.Helper & handle
    % gui.Triggers
    % obj = gui.Triggers(RUNTIME, TDTActiveX)
    % obj = gui.Triggers(RUNTIME, TDTActiveX, container, boxId)
    %
    % Simple GUI helper that displays available TDT trigger tags and allows
    % toggling them interactively via a table control.
    %
    % Properties
    % - BoxID: Trial/box index used to pick module trigger definitions
    %
    % Methods
    % - build: Populate the table based on current runtime trigger config

    properties
        BoxID   (1,1)   uint8 = 1;
    end

    properties (SetAccess = private)
        ContainerH
        TableH
    end

    methods
        % Constructor
        function obj = Triggers(RUNTIME,TDTActiveX,container,BoxID)
            narginchk(2,4);

            if nargin < 3 || isempty(container), container = figure; end
            if nargin < 4 || isempty(BoxID), BoxID = 1; end

            obj.BoxID = BoxID;
            obj.ContainerH = container;
            obj.TDTActiveX = TDTActiveX;

            obj.build(RUNTIME);
        end

        function build(obj,RUNTIME)
        
            % RUNTIME.TRIALS.MODULES names the modules for updates without OpenEx
            midx  = struct2array(RUNTIME.TRIALS(obj.BoxID).MODULES);
            fn    = fieldnames(RUNTIME.TRIALS(obj.BoxID).MODULES);

            state = [];
            T = {};
            tmIdx = [];
            for i = 1:length(RUNTIME.TDT.triggers)
                for j = 1:length(RUNTIME.TDT.triggers{i})
                    tmIdx(end+1) = RUNTIME.TDT.trigmods(i);

                    if RUNTIME.UseOpenEx
                        mname = fn{tmIdx(end) == midx};
                        T{end+1} = [mname '.' RUNTIME.TDT.triggers{i}{j}];
                        state(end+1) = obj.TDTActiveX.GetTargetVal(T{end});
                    else
                        T{end+1} = RUNTIME.TDT.triggers{i}{j};
                        state(end+1) = obj.TDTActiveX(tmIdx(end)).GetTagVal(T{end});
                    end
                end
            end

            if isempty(T)
                set(obj.TableH, ...
                    'Data',{'N/A'}, ...
                    'Enable','off', ...
                    'UserData',[]);
                return
            end

            T = [T(:) num2cell(logical(state(:)))];
            
            % uitable units is 'Pixels' only before 2021a
            ou = obj.ContainerH.Units;
            obj.ContainerH.Units = 'pixels';
            cpos = obj.ContainerH.Position;
            
            obj.TableH = uitable(obj.ContainerH, ...
                'ColumnFormat',{'char','logical'}, ...
                'ColumnEditable',[false,true], ...
                'ColumnName',{'Trigger','v'}, ...
                'RowName',[], ...
                'RowStriping','on', ...%'ColumnWidth',{cpos(3)-30,20}, ...
                'CellEditCallback',@obj.triggered, ...
                'UserData',tmIdx, ... 
                'Position',[0 0 cpos(3) cpos(4)-50], ...
                'Data',T, ...
                'Enable','on');
                
            obj.ContainerH.Units = ou;
            obj.update_highlight(obj.TableH,find(state),[1 0.6 0.6]);
        end
    end

    methods (Access = private)
            
        function triggered(obj,hObj,event)
            if isempty(event.Indices), return; end
                
            row = event.Indices(1);
            triggerName = hObj.Data{row,1};
            state = single(event.EditData);
            
            % update trigger tag states
            tmIdx = hObj.UserData;
            
            if isa(obj.TDTActiveX,'COM.RPco_x')
                obj.TDTActiveX(tmIdx(row)).SetTagVal(triggerName,state);
            else
                obj.TDTActiveX.SetTargetVal(triggerName,state);
            end
            hObj.Data{row,2} = logical(state);
            
            obj.update_highlight(hObj,find([hObj.Data{:,2}]),[1 0.6 0.6]);
        end

        
    end    
end