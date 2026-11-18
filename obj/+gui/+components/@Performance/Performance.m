classdef Performance < handle
    % Performance displays and updates a table summarizing behavioral performance metrics.
    %
    % This class creates a GUI table to show performance statistics (such as d', hit rate,
    % and trial count) from a linked psychophysics object. Table updates automatically
    % when new data is available.

    properties
        psychObj                  % psychophysics.Detection providing the rows
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
            s.psychTypes  = "psychophysics.Detection";
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
            catch
            end
        end

        function build(obj)
            % Builds the table UI component within the container.
            obj.TableH = uitable(obj.ContainerH,'Unit','Normalized', ...
                'Position',[0 0 1 1],'RowStriping','on','FontSize',14);
        end

        function update(obj,~,~)
            % One row per stimulus value of the analysis's Results. Which
            % trials are stimulus trials is the analysis's setting
            % (StimulusTrialType); the table reads, it never sets.
            vprintf(4,'Updating performance table')
            if isempty(obj.psychObj) || ~isvalid(obj.TableH), return; end

            R = obj.psychObj.Results;
            if isempty(R.Values)
                obj.TableH.Data = cell(0,4);
                return
            end

            D = [R.Values(:), R.N.Trials(:), R.DPrime(:), 100*R.Rate.Hit(:)];
            D = sortrows(D,1,obj.SortDirection);

            % Every value keeps its row: an undefined d' (no catch trials
            % yet) or hit rate (every trial aborted) reads "--". Dropping
            % such rows hid levels that had real trials behind them.
            S = [compose("%.4g",D(:,1)), compose("%d",D(:,2)), ...
                 compose("%.4g",D(:,3)), compose("%.1f",D(:,4))];
            S(isnan(D)) = "--";

            % A cellstr, not a string array: the default container is a
            % classic figure, whose uitable refuses strings.
            obj.TableH.Data = cellstr(S);
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
