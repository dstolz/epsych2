classdef History < handle
    % gui.History
    % Trial-by-trial history table for behavioral sessions.
    %
    % Creates a GUI table that summarizes trial data from a linked
    % psychophysics object. The table updates when new data are available,
    % can color rows by decoded response bit for rapid session review, and
    % supports optional per-parameter column format overrides.
    %
    % Display behavior:
    %   - The newest trial is shown at the top by default.
    %   - Column headers are user sortable (uifigure containers); the chosen
    %     sort is reapplied on every trial update rather than being reset.
    %   - Right-click the table to show/hide parameter columns or to reset
    %     sorting to the default (newest first).
    %   - Column selection and sort order persist across sessions via
    %     getpref/setpref, keyed to the hosting GUI figure.
    %
    % Properties:
    %   psychObj             - Linked psychophysics object
    %   ParametersOfInterest - Data fields shown after Time and Response
    %   ColumnFormats        - Optional sprintf formats for all displayed columns
    %   ParameterColumnFormats - Legacy sprintf formats for ParametersOfInterest columns
    %   BitColors            - Optional response color override
    %   SortByColumn         - Name of the column used to order rows (default "Time")
    %   SortDirection        - "ascend" or "descend" (default "descend")
    %
    % Methods:
    %   History      - Construct the history table UI and optional listener
    %   build        - Create the underlying uitable
    %   update       - Refresh table data and row colors
    %   delete       - Cleanup listener and context menu resources
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
        SortByColumn (1,1) string = "Time"    % Column name used to order rows
        SortDirection (1,1) string {mustBeMember(SortDirection,["ascend","descend"])} = "descend"
    end

    properties (SetAccess = private)
        TableH                       % Handle to uitable
        ContainerH                   % Handle to container figure or panel

        Data                         % Rearranged data for table display
        Info                         % Metadata for table display (e.g., trial IDs)

        hl_NewData                   % Listener for new data events
    end

    properties (Access = private)
        ContextMenuH                 % Right-click context menu on the table
        ColumnsMenuH                 % "Show Columns" submenu
        MenuParams_ = {}             % Parameter names currently in the context menu
        PendingPrefs_ = []           % Saved preferences awaiting first data update
        FormatMap_ = struct          % Parameter name -> sprintf format
        PreferenceTag_ char = ''     % Optional explicit preference key
    end

    properties (Constant, Access = private)
        REQUIRED_FIELDS = {'RespCode','TrialID','computerTimestamp'}
        NO_PARAMS_SENTINEL = '(none)' % ParametersOfInterest entry meaning "hide all parameters"
        PREF_GROUP = 'epsych2_gui_History'
    end

    methods

        function obj = History(pObj,container,options)
            % H = gui.History(pObj, container)
            % H = gui.History(pObj, container, BitColors=colors)
            % H = gui.History(pObj, container, ColumnFormats=formats)
            % H = gui.History(pObj, container, PreferenceTag=tag)
            % Initialize the history table and optional display overrides.
            %
            % Parameters:
            %   pObj - Psychophysics object providing DATA, responseCodes, and BitColors.
            %   container - Figure or panel host for the table. If empty, creates a figure.
            %   options.ColumnFormats - Optional sprintf formats for all displayed columns.
            %   options.BitColors - Optional hex color scheme override.
            %   options.PreferenceTag - Optional key for saved preferences; defaults
            %       to the hosting figure Tag (or Name) so each GUI keeps its own settings.
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
                options.PreferenceTag {mustBeTextScalar} = ''
            end

            if isempty(container), container = figure; end
            obj.ContainerH = container;
            obj.ColumnFormats = string(options.ColumnFormats(:));
            obj.BitColors = string(options.BitColors(:));
            obj.PreferenceTag_ = char(options.PreferenceTag);
            obj.build;
            obj.loadPreferences;
            if nargin >= 1 && ~isempty(pObj)
                obj.psychObj = pObj;
                obj.hl_NewData = listener(pObj.Helper,'NewData',@obj.update);
            end
        end

        function delete(obj)
            % delete(obj)
            % Release NewData listener and context menu resources.
            if ~isempty(obj.hl_NewData) && isvalid(obj.hl_NewData)
                delete(obj.hl_NewData);
                obj.hl_NewData = event.listener.empty;
            end
            if ~isempty(obj.ContextMenuH) && isvalid(obj.ContextMenuH)
                delete(obj.ContextMenuH);
            end
        end

        function build(obj)
            % build(obj)
            % Create the history uitable in the configured container.
            obj.TableH = uitable(obj.ContainerH,'Unit','Normalized', ...
                'Position',[0 0 1 1],'RowStriping','off');
            try
                obj.TableH.ColumnSortable = true;
                obj.TableH.DisplayDataChangedFcn = @obj.onDisplayDataChanged;
            catch ME
                % Header-click sorting requires a uifigure-based uitable.
                vprintf(3,'gui.History: column sorting unavailable: %s',ME.message)
            end
            obj.buildContextMenu;
        end

        function update(obj,~,~)
            % update(obj, ~, ~)
            % Refresh table data, row ordering, labels, formats, and row colors.
            vprintf(4,'Updating History table')
            if ~epsych.Helper.valid_psych_obj(obj.psychObj), return; end
            if isempty(obj.psychObj.DATA), return; end

            obj.applyPendingPreferences;

            [RD,FN] = obj.rearrange_data;
            if isempty(RD), return; end

            if ~isvalid(obj.TableH), return; end % TO DO: Track down why this function is being called twice
            columnNames = [{'Time'}; {'Response'}; FN];

            order = obj.resolveDisplayOrder(RD,columnNames);
            obj.Info.DisplayOrder = order;

            obj.TableH.Data = obj.formatTableData(RD(order,:),columnNames);
            obj.TableH.RowName = cellstr(string(obj.Info.TrialNumber(order)));
            obj.TableH.ColumnName = columnNames;
            obj.TableH.ColumnFormat = repmat({'char'},1,numel(columnNames));

            obj.update_row_colors;
            obj.refreshColumnsMenu;
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
            obj.syncFormatMap;
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

    methods (Static, Access = private)
        function tf = isScalarLike(value)
            % tf = gui.History.isScalarLike(value)
            % True when a DATA field renders as a single table cell.
            % A char row vector is one value, not numel(value) values, so
            % element counting alone would wrongly reject text fields.
            %
            % Parameters:
            %   value - Any DATA field value.
            %
            % Returns:
            %   tf - Logical scalar.
            tf = (ischar(value) && (isrow(value) || isempty(value))) ...
                || isStringScalar(value) ...
                || (iscellstr(value) && isscalar(value)) ...
                || numel(value) <= 1;
        end
    end

    methods (Access = private)
        function update_row_colors(obj)
            % update_row_colors(obj)
            % Update row background colors from decoded response bits.
            if ~epsych.Helper.valid_psych_obj(obj.psychObj), return; end

            if isempty(obj.Info) || ~isfield(obj.Info,'ResponseBit'), return; end

            responseBits = epsych.BitMask.getResponses;
            n = numel(obj.Info.ResponseBit);
            i = [];
            if isfield(obj.Info,'DisplayOrder'), i = obj.Info.DisplayOrder; end
            if isempty(i) || numel(i) ~= n
                i = (n:-1:1)'; % default display order: newest trial first
            end
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
            DataOut = {};
            FN = {};
            requiredParams = obj.REQUIRED_FIELDS;
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
            obj.Info.TrialNumber = (1:numel(DataIn))'; % chronological order of DATA entries
            td = [DataIn.computerTimestamp] - DataIn(1).computerTimestamp;
            td.Format = "mm:ss";
            obj.Info.RelativeTimestamp = string(td);

            rb = obj.psychObj.responseBits;
            obj.Info.ResponseBit = rb(:);
            Response = string(rb);

            ind = structfun(@(a) ~gui.History.isScalarLike(a),DataIn(1));
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

            % permute (not squeeze) keeps rows-by-fields orientation when a
            % single parameter field is displayed
            DataOut = permute(struct2cell(DataIn),[3 1 2]);
            DataOut = [cellstr(Response(:)) DataOut];
            DataOut = [cellstr(obj.Info.RelativeTimestamp(:)) DataOut];

            FN = fieldnames(DataIn);
        end

        function order = resolveDisplayOrder(obj,RD,columnNames)
            % order = resolveDisplayOrder(obj, RD, columnNames)
            % Compute display row order from the current sort selection.
            % Sorting uses raw (unformatted) values so numeric columns order
            % numerically rather than lexicographically.
            n = size(RD,1);
            if obj.SortDirection == "ascend"
                order = (1:n)';
            else
                order = (n:-1:1)';
            end

            name = char(obj.SortByColumn);
            if isempty(name) || strcmp(name,'Time')
                return % chronological DATA order is the Time order
            end

            c = find(strcmp(columnNames,name),1);
            if isempty(c)
                order = (n:-1:1)'; % sorted column not currently displayed
                return
            end

            try
                key = obj.columnSortKey(RD(:,c));
                [~,order] = sort(key,char(obj.SortDirection));
                order = order(:);
            catch ME
                vprintf(2,'gui.History: unable to sort by "%s": %s',name,ME.message)
                order = (n:-1:1)';
            end
        end

        function key = columnSortKey(~,vals)
            % key = columnSortKey(vals)
            % Build a sortable key vector from raw column values.
            isNum = cellfun(@(v) (isnumeric(v) || islogical(v)) && isscalar(v), vals);
            if all(isNum)
                key = cellfun(@double,vals);
                return
            end
            key = strings(numel(vals),1);
            for k = 1:numel(vals)
                try
                    key(k) = strjoin(string(vals{k}),", ");
                catch
                    key(k) = "";
                end
            end
        end

        function onDisplayDataChanged(obj,~,event)
            % onDisplayDataChanged(obj, ~, event)
            % Record a header-click sort and reapply it with type-aware
            % ordering so the selection persists across trial updates.
            try
                col = event.InteractionColumn;
            catch
                return % programmatic data change or unsupported event
            end
            if isempty(col) || ~isvalid(obj.TableH), return; end
            col = col(1);

            cn = cellstr(string(obj.TableH.ColumnName));
            if col < 1 || col > numel(cn), return; end

            clicked = string(cn{col});
            if obj.SortByColumn == clicked
                if obj.SortDirection == "descend"
                    obj.SortDirection = "ascend";
                else
                    obj.SortDirection = "descend";
                end
            else
                obj.SortByColumn = clicked;
                obj.SortDirection = "ascend";
            end

            obj.savePreferences;
            obj.update;
        end

        function resetSort(obj)
            % resetSort(obj)
            % Restore the default sort: newest trial at the top.
            obj.SortByColumn = "Time";
            obj.SortDirection = "descend";
            obj.savePreferences;
            obj.update;
        end

        function toggleParameter(obj,paramName)
            % toggleParameter(obj, paramName)
            % Show or hide a parameter column from the context menu.
            avail = obj.availableParameters;
            shown = obj.displayedParameters(avail);
            if ismember(paramName,shown)
                shown = setdiff(shown,{paramName},'stable');
            else
                shown = [shown(:); {paramName}];
            end
            if isempty(shown)
                shown = {obj.NO_PARAMS_SENTINEL}; % an empty list would mean "show all fields"
            end
            obj.setParametersWithFormats(shown(:));
            obj.savePreferences;
            obj.update;
        end

        function params = availableParameters(obj)
            % params = availableParameters(obj)
            % Scalar-valued DATA fields eligible for display as columns.
            params = cell(0,1);
            if ~epsych.Helper.valid_psych_obj(obj.psychObj), return; end
            D = obj.psychObj.DATA;
            if isempty(D), return; end
            fn = setdiff(fieldnames(D),obj.REQUIRED_FIELDS(:),'stable');
            ind = cellfun(@(f) gui.History.isScalarLike(D(1).(f)), fn);
            params = sort(fn(ind));
        end

        function shown = displayedParameters(obj,avail)
            % shown = displayedParameters(obj, avail)
            % Parameter columns currently displayed; an empty
            % ParametersOfInterest means all available fields are shown.
            if isempty(obj.ParametersOfInterest)
                shown = avail(:);
            else
                shown = setdiff(obj.ParametersOfInterest,{obj.NO_PARAMS_SENTINEL},'stable');
                shown = shown(:);
            end
        end

        function setParametersWithFormats(obj,paramNames)
            % setParametersWithFormats(obj, paramNames)
            % Update ParametersOfInterest keeping per-parameter formats aligned.
            fmts = strings(numel(paramNames),1);
            for k = 1:numel(paramNames)
                key = matlab.lang.makeValidName(paramNames{k});
                if isfield(obj.FormatMap_,key)
                    fmts(k) = obj.FormatMap_.(key);
                else
                    fmts(k) = "auto";
                end
            end
            obj.ParameterColumnFormats = string.empty(0,1); % avoid transient count mismatch
            obj.ParametersOfInterest = paramNames;
            obj.ParameterColumnFormats = fmts;
        end

        function syncFormatMap(obj)
            % syncFormatMap(obj)
            % Remember which sprintf format belongs to which parameter so
            % formats survive column add/remove via the context menu.
            fmts = obj.ParameterColumnFormats;
            params = obj.ParametersOfInterest;
            if isempty(fmts) || isempty(params), return; end
            if isscalar(fmts), fmts = repmat(fmts,numel(params),1); end
            if numel(fmts) ~= numel(params), return; end
            for k = 1:numel(params)
                obj.FormatMap_.(matlab.lang.makeValidName(params{k})) = char(fmts(k));
            end
        end

        function buildContextMenu(obj)
            % buildContextMenu(obj)
            % Create the right-click menu for column selection and sorting.
            fig = ancestor(obj.ContainerH,'figure');
            if isempty(fig), return; end
            try
                obj.ContextMenuH = uicontextmenu(fig);
                obj.ColumnsMenuH = uimenu(obj.ContextMenuH,'Text','Show Columns');
                uimenu(obj.ContextMenuH,'Text','Reset Sort (Newest First)', ...
                    'Separator','on','MenuSelectedFcn',@(~,~) obj.resetSort);
                obj.TableH.ContextMenu = obj.ContextMenuH;
            catch ME
                vprintf(3,'gui.History: context menu unavailable: %s',ME.message)
            end
        end

        function refreshColumnsMenu(obj)
            % refreshColumnsMenu(obj)
            % Rebuild the column submenu when available fields change and
            % refresh the checked state of each entry.
            if isempty(obj.ColumnsMenuH) || ~isvalid(obj.ColumnsMenuH), return; end
            avail = obj.availableParameters;
            if ~isequal(obj.MenuParams_,avail)
                delete(obj.ColumnsMenuH.Children);
                for k = 1:numel(avail)
                    p = avail{k};
                    uimenu(obj.ColumnsMenuH,'Text',p, ...
                        'MenuSelectedFcn',@(~,~) obj.toggleParameter(p));
                end
                obj.MenuParams_ = avail;
            end
            shown = obj.displayedParameters(avail);
            ch = obj.ColumnsMenuH.Children;
            for k = 1:numel(ch)
                ch(k).Checked = ismember(ch(k).Text,shown);
            end
        end

        function loadPreferences(obj)
            % loadPreferences(obj)
            % Stage saved preferences; they are applied on the first data
            % update so they take precedence over programmatic defaults
            % assigned right after construction.
            try
                pname = obj.preferenceName;
                if ispref(obj.PREF_GROUP,pname)
                    obj.PendingPrefs_ = getpref(obj.PREF_GROUP,pname);
                    vprintf(3,'gui.History: loaded saved preferences "%s"',pname)
                end
            catch ME
                vprintf(2,'gui.History: failed to load preferences: %s',ME.message)
            end
        end

        function savePreferences(obj)
            % savePreferences(obj)
            % Persist column selection and sort order for this GUI.
            try
                s = struct;
                s.ParametersOfInterest = obj.ParametersOfInterest;
                s.ParameterColumnFormats = cellstr(obj.ParameterColumnFormats);
                s.SortByColumn = char(obj.SortByColumn);
                s.SortDirection = char(obj.SortDirection);
                setpref(obj.PREF_GROUP,obj.preferenceName,s);
            catch ME
                vprintf(2,'gui.History: failed to save preferences: %s',ME.message)
            end
        end

        function applyPendingPreferences(obj)
            % applyPendingPreferences(obj)
            % Apply staged preferences once, on the first update with data.
            if isempty(obj.PendingPrefs_), return; end
            s = obj.PendingPrefs_;
            obj.PendingPrefs_ = [];
            try
                if isfield(s,'ParametersOfInterest') && ~isempty(s.ParametersOfInterest)
                    obj.ParameterColumnFormats = string.empty(0,1); % clear before count changes
                    obj.ParametersOfInterest = s.ParametersOfInterest;
                    if isfield(s,'ParameterColumnFormats') && ~isempty(s.ParameterColumnFormats)
                        obj.ParameterColumnFormats = s.ParameterColumnFormats;
                    end
                end
                if isfield(s,'SortByColumn') && ~isempty(s.SortByColumn)
                    obj.SortByColumn = s.SortByColumn;
                end
                if isfield(s,'SortDirection') && ~isempty(s.SortDirection)
                    obj.SortDirection = s.SortDirection;
                end
                vprintf(3,'gui.History: applied saved preferences')
            catch ME
                vprintf(2,'gui.History: failed to apply saved preferences: %s',ME.message)
            end
        end

        function n = preferenceName(obj)
            % n = preferenceName(obj)
            % Preference key scoped to the hosting GUI: explicit tag, else
            % the ancestor figure Tag, else its Name, else 'default'.
            n = obj.PreferenceTag_;
            if isempty(n)
                try
                    f = ancestor(obj.ContainerH,'figure');
                    if ~isempty(f) && isvalid(f)
                        if ~isempty(f.Tag)
                            n = f.Tag;
                        elseif ~isempty(f.Name)
                            n = f.Name;
                        end
                    end
                catch
                end
            end
            if isempty(n), n = 'default'; end
            n = matlab.lang.makeValidName(n);
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
            % Resolve one sprintf format per displayed column. Columns
            % without a configured format use "auto" (natural string form).
            nCols = numel(columnNames);
            formats = repmat("auto",nCols,1);

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
            % Format one table value to a char row vector via sprintf. The
            % "auto" format displays values with their natural string form.
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

            if strcmp(char(fmt),'auto')
                if ischar(valueIn)
                    valueOut = valueIn;
                elseif isempty(valueIn)
                    valueOut = '';
                else
                    valueOut = char(strjoin(string(valueIn),", "));
                end
                return
            end

            try
                valueOut = sprintf(char(fmt),valueIn);
            catch
                % Keep table refresh robust if caller format and value type mismatch.
                valueOut = sprintf('%s',char(string(valueIn)));
            end
        end
    end
end
