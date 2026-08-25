classdef Performance < handle
    % Performance displays and updates a table summarizing behavioral performance metrics.
    %
    % This class creates a GUI table to show performance statistics (such as d', hit rate,
    % and trial count) from a linked psychophysics object. Table updates automatically
    % when new data is available.

    properties
        psychObj                  % Reference to main psychophysics object providing data
        ParametersOfInterest (:,1) cell   % Fields to display as key independent variables
        SortDirection (1,1) string {mustBeMember(SortDirection,["descend","ascend"])} = "descend"

        % Trial type the table counts and scores. Every row is computed over
        % the trials carrying this bit, so a paradigm whose stimulus trials
        % are not TrialType_0 -- anything with more than one target
        % category, or a protocol that numbers them differently -- sets it
        % here rather than reading someone else's trials.
        TargetTrialType (1,1) epsych.BitMask = epsych.BitMask.TrialType_0
    end

    properties (SetAccess = private)
        TableH                           % Handle to uitable for displaying performance metrics
        ContainerH                       % Handle to the container figure or panel
        ColumnName                       % Column labels for the uitable
        Data                             % Latest table data
        Info                             % Metadata or auxiliary info for the table
        hl_NewData                       % Listener for data update events
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.components.Performance.getComponentSpec()
            % Superseded by gui.components.SessionPerformance, which owns the
            % 'Performance' palette type. Kept because screenshot tooling
            % still builds it, but not offered on the palette -- two specs
            % claiming one type would make the catalog lookup ambiguous.
            % See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type        = 'LegacyPerformance';
            s.label       = 'Performance (legacy)';
            s.category    = 'Displays';
            s.shape       = ["psych","parent"];
            s.requires    = "psych";
            s.placeable   = false;
        end
    end

    methods

        function obj = Performance(pObj,container)
            % Constructor: initializes the performance table and sets up listener for new data.
            if nargin < 2 || isempty(container), container = figure; end
            obj.ContainerH = container;
            obj.build;
            if nargin >= 1 && ~isempty(pObj)
                obj.psychObj = pObj;
                obj.hl_NewData = listener(pObj.Events,'NewData',@obj.update);
            end
        end

        function delete(obj)
            % Destructor: cleans up the listener.
            try
                delete(obj.hl_NewData);
            end
        end

        function build(obj)
            % Builds the table UI component within the container.
            obj.TableH = uitable(obj.ContainerH,'Unit','Normalized', ...
                'Position',[0 0 1 1],'RowStriping','on','FontSize',14);
        end

        function update(obj,src,event)
            vprintf(4,'Updating performance table')
            
            % Updates the table with the latest performance metrics from psychObj.
            if isempty(obj.psychObj.DATA), return; end
            
            if ~isvalid(obj.TableH), return; end % TO DO: Track down why this function is being called twice
            
            P = obj.psychObj;

            P.targetTrialType = obj.TargetTrialType;

            % Count field names are the decoded bitmask flag names, so the
            % column follows whatever trial type this table was pointed at.
            % string() on the enum yields the MEMBER NAME; char() would
            % convert the uint32 it derives from instead.
            countField = string(obj.TargetTrialType);

            D(:,1) = P.uniqueValues;
            D(:,2) = [P.Count.(countField)];
            D(:,3) = P.DPrime;
            D(:,4) = [P.Rate.Hit]*100;
            D(any(isnan(D),2),:) = [];

            D = sortrows(D,1,obj.SortDirection);
            
            % S = string(D);
            S(:,1) = compose("%.4g",D(:,1));
            S(:,2) = compose("%d",D(:,2));
            S(:,3) = compose("%.4g",D(:,3));
            S(:,4) = compose("%.1f",D(:,4));
            
            obj.TableH.Data = S;
            obj.TableH.ColumnName = [obj.ParametersOfInterest{:}, {'# Trials'}, {'d'''},{'Hit Rate'}];
        end

        function set.psychObj(obj,pobj)
            % Setter for psychObj property with validation and trigger for update.
            assert(epsych.EventHub.valid_psych_obj(pobj),'gui.components.Performance:set.psychObj', ...
                'psychObj must be from the toolbox "psychophysics"');
            obj.psychObj = pobj;
            obj.update;
        end

    end

    methods (Access = private)

    end
end
