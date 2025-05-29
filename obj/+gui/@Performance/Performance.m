classdef Performance < handle


    properties
        PsychophysicsObj

        ParametersOfInterest (:,1) cell
    end

    properties (SetAccess = private)
        TableH
        ContainerH

        ColumnName
        Data
        Info

        hl_NewData
    end


    methods

        function obj = Performance(pObj,container)
            if nargin < 2 || isempty(container), container = figure; end
            
            obj.ContainerH = container;

            obj.build;
            
            if nargin >= 1 && ~isempty(pObj)
                obj.PsychophysicsObj = pObj;
            end

            obj.hl_NewData = listener(pObj.Helper,'NewData',@obj.update);
        end


        function delete(obj)
            try
                delete(obj.hl_NewData);
            end
        end
        
        function build(obj)
            obj.TableH = uitable(obj.ContainerH,'Unit','Normalized', ...
                'Position',[0 0 1 1],'RowStriping','on');
        end
        
        function update(obj,src,event)
            if isempty(obj.PsychophysicsObj.DATA), return; end

            P = obj.PsychophysicsObj;
            
            D(:,1) = P.ParameterValues;
            D(:,2) = P.Trial_Count;
            D(:,3) = P.DPrime;
            D(:,4) = P.Hit_Rate;

            D(any(isnan(D),2),:) = [];

            obj.TableH.Data = D;

            % % Call a function to rearrange DATA to make it easier to use (see below).
            % obj.rearrange_data;
            % 
            % % Flip the DATA matrix so that the most recent trials are displayed at the
            % % top of the table.
            % obj.TableH.Data = flipud(obj.Data);
            % 
            % % set the row names as the trial ids
            % obj.TableH.RowName = flipud(obj.Info.TrialID);
            % 
            % set the column names
            obj.TableH.ColumnName = [obj.ParametersOfInterest{:}, {'# Trials'}, {'d'''},{'Hit Rate'}];
            % 
            % obj.update_row_colors;
        end
        
        function set.PsychophysicsObj(obj,pobj)
            assert(epsych.Helper.valid_psych_obj(pobj),'gui.Performance:set.PsychophysicsObj', ...
                'PsychophysicsObj must be from the toolbox "psychophysics"');
            obj.PsychophysicsObj = pobj;
            obj.update;
        end
        
    end


    methods (Access = private)

    end
end