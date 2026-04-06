classdef History < handle
    % gui.History
    % Trial-by-trial history table for behavioral sessions.
    %
    % Creates a GUI table that summarizes trial data from a linked
    % psychophysics object. The table updates when new data are available,
    % can color rows by decoded response bit for rapid session review, and
    % supports optional per-parameter column format overrides.
    %
    % Properties:
    %   psychObj             - Linked psychophysics object
    %   ParametersOfInterest - Data fields shown after Time and Response
    %   ColumnFormats        - Optional sprintf formats for all displayed columns
    %   ParameterColumnFormats - Legacy sprintf formats for ParametersOfInterest columns
    %   BitColors            - Optional response color override
    %
    % Methods:
    %   History      - Construct the history table UI and optional listener
    %   build        - Create the underlying uitable
    %   update       - Refresh table data and row colors
    %   delete       - Cleanup listener resources
    %
    % Example:
    %   H = gui.History(pObj, uifigure);
    %
    % See also: documentation/gui/gui_History.md, epsych.BitMask

    properties
        psychObj                     % Reference to the main psychophysics object
        ParametersOfInterest (:,1) cell   % List of fields to display from the data structure
        ColumnFormats (:,1) string = string.empty(0,1) % Optional sprintf format strings for all displayed columns
        ParameterColumnFormats (:,1) string = string.empty(0,1) % Legacy sprintf format strings for parameter-only columns
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
            % H = gui.History(pObj, container, ColumnFormats=formats)
            % Initialize the history table and optional display overrides.
            %
            % Parameters:
            %   pObj - Psychophysics object providing DATA, responseCodes, and BitColors.
            %   container - Figure or panel host for the table. If empty, creates a figure.
            %   options.ColumnFormats - Optional sprintf formats for all displayed columns.
            %   options.BitColors - Optional hex color scheme override.
            %
            % Returns:
            %   obj - gui.History object.
            %
            % See also: documentation/gui/gui_History.md
            arguments
                pObj = []
                container = []
                options.ColumnFormats = string.empty(0,1)
                options.BitColors = string.empty(0,1)
            end

            if isempty(container), container = figure; end
            obj.ContainerH = container;
            obj.ColumnFormats = string(options.ColumnFormats(:));
            obj.BitColors = string(options.BitColors(:));
            obj.build;
            if nargin >= 1 && ~isempty(pObj)
                obj.psychObj = pObj;
                obj.hl_NewData = listener(pObj.Helper,'NewData',@obj.update);
            end
        end

        function delete(obj)
            % delete(obj)
            % Release NewData listener resources.
            if isempty(obj.hl_NewData), return; end
            if isvalid(obj.hl_NewData)
                delete(obj.hl_NewData);
                obj.hl_NewData = event.listener.empty;
            end
        end

        function build(obj)
            % build(obj)
            % Create the history uitable in the configured container.
            obj.TableH = uitable(obj.ContainerH,'Unit','Normalized', ...
                'Position',[0 0 1 1],'RowStriping','off');
        end

        function update(obj,~,~)
            % update(obj, ~, ~)
            % Refresh table data, row ordering, labels, formats, and row colors.
            vprintf(4,'Updating History table')
            if isempty(obj.psychObj.DATA), return; end
            [RD,FN] = obj.rearrange_data;
            if isempty(RD), return; end


            [~,i] = sort(obj.Info.TrialID,'descend');

            if ~isvalid(obj.TableH), return; end % TO DO: Track down why this function is being called twice
            columnNames = [{'Time'}; {'Response'}; FN];
            obj.TableH.Data = obj.formatTableData(RD(i,:),columnNames);
            obj.TableH.RowName = size(RD,1):-1:1;
            obj.TableH.ColumnName = columnNames;
            obj.TableH.ColumnFormat = repmat({'char'},1,numel(columnNames));

            obj.update_row_colors;
        end

        function set.ParametersOfInterest(obj,paramNames)
            % set.ParametersOfInterest(obj, paramNames)
            % Normalize parameters and validate format correspondence.
            if isempty(paramNames)
                obj.ParametersOfInterest = cell.empty(0,1);
            else
                obj.ParametersOfInterest = cellstr(string(paramNames(:)));
            end
            obj.validateParameterFormatCorrespondence;
        end

        function set.ParameterColumnFormats(obj,formats)
            % set.ParameterColumnFormats(obj, formats)
            % Normalize per-parameter formats and validate correspondence.
            obj.ParameterColumnFormats = string(formats(:));
            obj.validateParameterFormatCorrespondence;
        end

        function set.psychObj(obj,pobj)
            % set.psychObj(obj, pobj)
            % Validate and assign psychObj, then refresh table display.
            assert(epsych.Helper.valid_psych_obj(pobj),'gui.History:set.psychObj', ...
                'psychObj must be from the toolbox "psychophysics"');
            obj.psychObj = pobj;
            obj.update;
        end
    end

    methods (Access = private)
        function update_row_colors(obj)
            % update_row_colors(obj)
            % Update row background colors from decoded response bits.
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

        function [DataOut,FN] = rearrange_data(obj)
            % [DataOut, FN] = rearrange_data(obj)
            % Rearrange DATA into table rows with relative time and response text.
            requiredParams = {'RespCode','TrialID','computerTimestamp'};
            DataIn = obj.psychObj.DATA;

            if ~isempty(obj.ParametersOfInterest)
                ftr = setdiff(fieldnames(DataIn), [obj.ParametersOfInterest; requiredParams'], 'stable');
                DataIn = rmfield(DataIn,ftr);
            end

            if isempty(DataIn(1).TrialID)
                obj.Data = [];
                return
            end

            obj.Info.TrialID = [DataIn.TrialID]';
            td = [DataIn.computerTimestamp] - DataIn(1).computerTimestamp;
            td.Format = "mm:ss";
            obj.Info.RelativeTimestamp = string(td);

            rb = obj.psychObj.responseBits;
            obj.Info.ResponseBit = rb(:);
            Response = string(rb);

            ind = structfun(@(a) numel(a)>1,DataIn(1));
            fn = fieldnames(DataIn);
            fn = fn(ind);
            removeFields = [requiredParams(:); fn(:)];
            DataIn = rmfield(DataIn,removeFields);

            if ~isempty(obj.ParametersOfInterest)
                availableOrder = obj.ParametersOfInterest(ismember(obj.ParametersOfInterest,fieldnames(DataIn)));
                if ~isempty(availableOrder)
                    DataIn = orderfields(DataIn,availableOrder);
                end
            end

            DataOut = squeeze(struct2cell(DataIn))';
            DataOut = [cellstr(Response(:)) DataOut];
            DataOut = [cellstr(obj.Info.RelativeTimestamp(:)) DataOut];

            FN = fieldnames(DataIn);
        end

        function colors = getBitColors(obj,bits)
            % colors = getBitColors(obj, bits)
            % Resolve response colors from override settings or psychObj defaults.
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

        function dataOut = formatTableData(obj,dataIn,columnNames)
            % dataOut = formatTableData(obj, dataIn, columnNames)
            % Convert all table values to char using resolved sprintf formats.
            formats = obj.resolveColumnFormats(columnNames);
            nRows = size(dataIn,1);
            nCols = size(dataIn,2);
            dataOut = cell(nRows,nCols);
            for colIdx = 1:nCols
                fmt = formats(colIdx);
                for rowIdx = 1:nRows
                    dataOut{rowIdx,colIdx} = obj.formatCellValue(dataIn{rowIdx,colIdx},fmt);
                end
            end
        end

        function formats = resolveColumnFormats(obj,columnNames)
            % formats = resolveColumnFormats(obj, columnNames)
            % Resolve one sprintf format per displayed column.
            nCols = numel(columnNames);
            formats = repmat("%s",nCols,1);

            allFormats = string(obj.ColumnFormats(:));
            if ~isempty(allFormats)
                if isscalar(allFormats)
                    formats = repmat(allFormats,nCols,1);
                elseif numel(allFormats) == nCols
                    formats = allFormats;
                else
                    error("ColumnFormats must provide one format or one format per displayed column.");
                end
                return
            end

            parameterFormats = string(obj.ParameterColumnFormats(:));
            if isempty(parameterFormats)
                return
            end

            nParameterCols = max(nCols-2,0);
            if nParameterCols == 0
                return
            end

            if isscalar(parameterFormats)
                formats(3:end) = repmat(parameterFormats,nParameterCols,1);
            elseif ~isempty(obj.ParametersOfInterest) && numel(parameterFormats) == numel(obj.ParametersOfInterest)
                parameterNames = string(columnNames(3:end));
                [isMatched,formatIdx] = ismember(parameterNames,string(obj.ParametersOfInterest));
                if ~all(isMatched)
                    error("ParameterColumnFormats must correspond to ParametersOfInterest names.");
                end
                formats(3:end) = parameterFormats(formatIdx);
            elseif numel(parameterFormats) == nParameterCols
                formats(3:end) = parameterFormats;
            else
                error("ParameterColumnFormats must provide one format or one format per parameter column.");
            end
        end

        function validateParameterFormatCorrespondence(obj)
            % validateParameterFormatCorrespondence(obj)
            % Ensure per-parameter formats correspond to configured parameters.
            if isempty(obj.ParameterColumnFormats) || isempty(obj.ParametersOfInterest)
                return
            end

            nFormats = numel(obj.ParameterColumnFormats);
            nParams = numel(obj.ParametersOfInterest);
            if ~(isscalar(obj.ParameterColumnFormats) || nFormats == nParams)
                error("ParameterColumnFormats must provide one format or exactly one format per ParametersOfInterest entry (%d).",nParams);
            end
        end

        function valueOut = formatCellValue(~,valueIn,fmt)
            % valueOut = formatCellValue(valueIn, fmt)
            % Format one table value to a char row vector via sprintf.
            if isstring(valueIn)
                if isscalar(valueIn)
                    valueIn = char(valueIn);
                else
                    valueIn = char(strjoin(valueIn,", "));
                end
            end

            if isdatetime(valueIn) || isduration(valueIn)
                valueIn = char(string(valueIn));
            end

            if iscell(valueIn)
                valueIn = char(string(valueIn));
            end

            if ~ischar(valueIn) && ~(isnumeric(valueIn) || islogical(valueIn))
                valueIn = char(string(valueIn));
            end

            try
                valueOut = sprintf(char(fmt),valueIn);
            catch
                % Keep table refresh robust if caller format and value type mismatch.
                valueOut = sprintf("%s",char(string(valueIn)));
            end
        end
    end
end

