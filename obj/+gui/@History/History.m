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
        BitColors string = string.empty(0,1)  % Optional hex color override; defaults to psychObj.BitColors
    end

    properties (SetAccess = private)
        TableH                       % Handle to uitable
        ContainerH                   % Handle to container figure or panel

        Data                         % Rearranged data for table display
        Info                         % Metadata for table display (e.g., trial IDs)

        hl_NewData                   % Listener for new data events
    end

    methods

        function obj = History(pObj,container,options)
            % H = gui.History(pObj, container)
            % H = gui.History(pObj, container, BitColors=colors)
            % Initialize the history table and optionally override response-row colors.
            %
            % Parameters:
            %   pObj - Psychophysics object providing DATA, responseCodes, and BitColors
            %   container - Figure or panel that will host the table
            %   BitColors - Optional hex color scheme, one color per response
            arguments
                pObj = []
                container = []
                options.BitColors = string.empty(0,1)
            end

            if isempty(container), container = figure; end
            obj.ContainerH = container;
            obj.BitColors = string(options.BitColors(:));
            obj.build;
            if nargin >= 1 && ~isempty(pObj)
                obj.psychObj = pObj;
                obj.hl_NewData = listener(pObj.Helper,'NewData',@obj.update);
            end
        end

        function delete(obj)
            % Destructor: cleans up the listener.
            if isempty(obj.hl_NewData), return; end
            if isvalid(obj.hl_NewData)
                delete(obj.hl_NewData);
                obj.hl_NewData = event.listener.empty;
            end
        end

        function build(obj)
            % Builds the table UI component within the container.
            obj.TableH = uitable(obj.ContainerH,'Unit','Normalized', ...
                'Position',[0 0 1 1],'RowStriping','off');
        end

        function update(obj,~,~)
            % Updates the table with the latest data from the psychObj.
            vprintf(4,'Updating History table')
            if isempty(obj.psychObj.DATA), return; end
            RD = obj.rearrange_data;
            if isempty(RD), return; end


            [~,i] = sort(obj.Info.TrialID,'descend');

            if ~isvalid(obj.TableH), return; end % TO DO: Track down why this function is being called twice
            obj.TableH.Data = RD(i,:);
            obj.TableH.RowName = size(RD,1):-1:1;
            obj.TableH.ColumnName = [{'Time'}; {'Response'}; obj.ParametersOfInterest];
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

            if isempty(obj.Info) || ~isfield(obj.Info,'ResponseBit'), return; end

            responseBits = epsych.BitMask.getResponses;
            [~,i] = sort(obj.Info.TrialID,'descend');
            R = obj.Info.ResponseBit(i);
            C = repmat(epsych.BitMask.getDefaultColors(epsych.BitMask.Undefined),numel(R),1);
            bitColors = obj.getBitColors(responseBits);
            for idx = 1:numel(responseBits)
                b = responseBits(idx);
                ind = R == b;
                if ~any(ind), continue; end
                C(ind) = repmat(bitColors(idx),sum(ind),1);
            end
            obj.TableH.BackgroundColor = hex2rgb(C);
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

            RC = obj.psychObj.responseCodes;
            RCD = epsych.BitMask.decode(RC);
            r = repmat(epsych.BitMask(0),size(RC)); % preallocate
            for bm = epsych.BitMask.getResponses
                ind = RCD.(char(bm));
                if ~any(ind), continue; end
                r(ind) = bm;
            end
            obj.Info.ResponseBit = r(:);
            Response = string(r);

            ind = structfun(@(a) numel(a)>1,DataIn(1));
            fn = fieldnames(DataIn);
            fn = fn(ind);
            fn = fn(:)';
            DataIn = rmfield(DataIn,[requiredParams,fn]);

            DataOut = squeeze(struct2cell(DataIn))';
            DataOut = [cellstr(Response(:)) DataOut];
            DataOut = [cellstr(obj.Info.RelativeTimestamp(:)) DataOut];
        end

        function colors = getBitColors(obj,bits)
            % Resolve response colors from the hex override or the linked psychophysics object.
            bitIdx = double(bits(:));
            if ~isempty(obj.BitColors)
                colorSource = obj.BitColors;
                if numel(colorSource) == numel(bits)
                    colors = colorSource;
                elseif numel(colorSource) >= max(bitIdx)
                    colors = colorSource(bitIdx);
                else
                    error("BitColors must provide one hex color per response or per BitMask value.");
                end
                return
            end

            colorSource = obj.psychObj.BitColors;
            if isnumeric(colorSource)
                if size(colorSource,2) ~= 3
                    error("psychObj.BitColors must be an Nx3 RGB array or hex color strings.");
                end
                if size(colorSource,1) == numel(bits)
                    colors = rgb2hex(colorSource);
                elseif size(colorSource,1) >= max(bitIdx)
                    colors = rgb2hex(colorSource(bitIdx,:));
                else
                    error("psychObj.BitColors must provide one color per response or per BitMask value.");
                end
                return
            end

            colorSource = string(colorSource(:));
            if numel(colorSource) == numel(bits)
                colors = colorSource;
            elseif numel(colorSource) >= max(bitIdx)
                colors = colorSource(bitIdx);
            else
                error("psychObj.BitColors must provide one color per response or per BitMask value.");
            end
        end
    end
end
