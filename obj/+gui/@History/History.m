classdef History < handle
    % History displays and updates a trial-by-trial history table for behavioral sessions.
    %
    % This class generates a GUI table summarizing trial data from a linked psychophysics object.
    % The table is automatically updated as new trials are collected, showing details such as
    % timestamps, response codes, and selected parameters of interest. Row colors can be set based
    % on response codes for quick visual assessment.

    properties
        psychObj                     % Reference to the main psychophysics object
        ParametersOfInterest (:,1) cell   % List of fields to display from the data structure
    end

    properties (SetAccess = private)
        TableH                       % Handle to uitable
        ContainerH                   % Handle to container figure or panel

        Data                         % Rearranged data for table display
        Info                         % Metadata for table display (e.g., trial IDs)

        hl_NewData                   % Listener for new data events
    end

    methods

        function obj = History(pObj,container)
            % Constructor: initializes the history table and sets up listener for new data.
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
                'Position',[0 0 1 1],'RowStriping','off');
        end

        function update(obj,src,event)
            % Updates the table with the latest data from the psychObj.
            if isempty(obj.psychObj.DATA), return; end
            RD = obj.rearrange_data;
            if isempty(RD), return; end


            [tid,i] = sort(obj.Info.TrialID,'descend');

            obj.TableH.Data = RD(i,:);
            obj.TableH.RowName = tid;
            obj.TableH.ColumnName = [{'Time'}; {'Response'}; fieldnames(obj.psychObj.DATA)];
            obj.update_row_colors;
        end

        function set.psychObj(obj,pobj)
            % Setter for psychObj property with validation and trigger for update.
            assert(epsych.Helper.valid_psych_obj(pobj),'gui.History:set.psychObj', ...
                'psychObj must be from the toolbox "psychophysics"');
            obj.psychObj = pobj;
            obj.update;
        end
    end

    methods (Access = private)
        function update_row_colors(obj)
            % Updates row background colors based on response bitmask.
            if ~epsych.Helper.valid_psych_obj(obj.psychObj), return; end
            C = strings(size(obj.Data,1));
            R = cellfun(@epsych.BitMask,obj.Data(:,2),'uni',0);
            R = [R{:}];
            for i = 1:length(obj.psychObj.BitsInUse)
                ind = R == obj.psychObj.BitsInUse(i);
                if ~any(ind), continue; end
                C(ind) = repmat(obj.psychObj.BitColors(i),sum(ind),1);
            end
            obj.TableH.BackgroundColor = flipud(C);
            obj.TableH.RowStriping = 'on';
        end

        function DataOut = rearrange_data(obj)
            % Reorganizes raw DATA from psychObj into a table format suitable for display.
            % Handles filtering fields, timestamp formatting, and response decoding.
            requiredParams = {'ResponseCode','TrialID','inaccurateTimestamp'};
            DataIn = obj.psychObj.DATA;

            if ~isempty(obj.ParametersOfInterest)
                ftr = setdiff(fieldnames(DataIn),[obj.ParametersOfInterest;requiredParams']);
                DataIn = rmfield(DataIn,ftr);
            end

            if isempty(DataIn(1).TrialID)
                obj.Data = [];
                return
            end

            obj.Info.TrialID = [DataIn.TrialID]';
            td = [DataIn.inaccurateTimestamp] - DataIn(1).inaccurateTimestamp;
            td.Format = "mm:ss";
            obj.Info.RelativeTimestamp = string(td);

            RC = obj.psychObj.decodedTrials.responseCodes;
            r = cell(size(RC));
            for i = epsych.BitMask.getResponses
                ind = logical(bitget(RC,i));
                if ~any(ind), continue; end
                r{ind} = i;
            end
            Response = cellfun(@char,r,'uni',0);

            ind = structfun(@(a) numel(a)>1,DataIn(1));
            fn = fieldnames(DataIn);
            fn = fn(ind);
            fn = fn(:)';
            DataIn = rmfield(DataIn,[requiredParams,fn]);

            DataOut = squeeze(struct2cell(DataIn))';
            DataOut = [Response DataOut];
            DataOut = [cellstr(obj.Info.RelativeTimestamp(:)) DataOut];
        end
    end
end
