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
    end

    properties (SetAccess = private)
        TableH                           % Handle to uitable for displaying performance metrics
        ContainerH                       % Handle to the container figure or panel
        ColumnName                       % Column labels for the uitable
        Data                             % Latest table data
        Info                             % Metadata or auxiliary info for the table
        hl_NewData                       % Listener for data update events
    end

    methods

        function obj = Performance(pObj,container)
            % Constructor: initializes the performance table and sets up listener for new data.
            if nargin < 2 || isempty(container), container = figure; end
            obj.ContainerH = container;
            obj.build;
            if nargin >= 1 && ~isempty(pObj)
                obj.psychObj = pObj;
            end
            obj.hl_NewData = listener(pObj.Helper,'NewData',@obj.update);
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

            P.targetTrialType = epsych.BitMask.TrialType_0; % THIS SHOULD BE SETTABLE BY CALLER


            D(:,1) = P.uniqueValues;
            D(:,2) = [P.Count.TrialType_0];
            D(:,3) = P.DPrime;
            D(:,4) = [P.Rate.Hit]*100;
            D(any(isnan(D),2),:) = [];

            D = sortrows(D,1,obj.SortDirection);
            
            % S = string(D);
            S(:,1) = compose("%.2f",D(:,1));
            S(:,2) = compose("%d",D(:,2));
            S(:,3) = compose("%.4f",D(:,3));
            S(:,4) = compose("%.1f",D(:,4));
            
            obj.TableH.Data = S;
            obj.TableH.ColumnName = [obj.ParametersOfInterest{:}, {'# Trials'}, {'d'''},{'Hit Rate'}];
        end

        function set.psychObj(obj,pobj)
            % Setter for psychObj property with validation and trigger for update.
            assert(epsych.Helper.valid_psych_obj(pobj),'gui.Performance:set.psychObj', ...
                'psychObj must be from the toolbox "psychophysics"');
            obj.psychObj = pobj;
            obj.update;
        end

    end

    methods (Access = private)

    end
end
