classdef History < gui.PopOut
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
    %   - The chronological trial number is the leading "Trial" column. It is
    %     not a uitable RowName: every changed table property costs a view
    %     round-trip of tens of milliseconds regardless of how many rows are
    %     shown, so rewriting the row headers once per trial was pure cost.
    %   - Rows are rendered in blocks of RowBlockSize, padded with blank white
    %     rows. A uitable whose row COUNT changes makes the view rebuild its
    %     row model, which measures several times more than replacing the cell
    %     contents at a fixed count; padding pays that once per block instead
    %     of once per trial. Set RowBlockSize to 1 to render an exact count.
    %   - Column headers are user sortable (uifigure containers); the chosen
    %     sort is reapplied on every trial update rather than being reset.
    %   - Columns are user rearrangeable by dragging a header (uifigure
    %     containers); the chosen order is reapplied on every trial update.
    %   - Right-click the table to show/hide parameter columns or to reset
    %     sorting or column order to their defaults.
    %   - Column selection, order, and sort order persist across sessions
    %     via getpref/setpref, keyed to the hosting GUI figure.
    %   - Right-click > Open in Separate Window (or the popOut method) opens
    %     a second, independent table over the same trials in a window of
    %     its own; see gui.PopOut.
    %
    % Properties:
    %   psychObj             - Linked psychophysics object
    %   ParametersOfInterest - Data fields shown after Trial, Time and Response
    %   ColumnFormats        - Optional sprintf formats for all displayed columns
    %   ParameterColumnFormats - Legacy sprintf formats for ParametersOfInterest columns
    %   BitColors            - Optional response color override
    %   SortByColumn         - Name of the column used to order rows (default "Time")
    %   SortDirection        - "ascend" or "descend" (default "descend")
    %   RowBlockSize         - Rendered rows are padded to a multiple of this
    %                          (default 50); 1 renders an exact row count
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
        RowBlockSize (1,1) double {mustBeInteger,mustBePositive} = 50 % Render rows in blocks of this size; 1 disables padding
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
        ColumnOrder_ (:,1) cell = {} % User-arranged column display order (persisted)
        Updating_ = false            % Reentrancy guard for update
        MenuFields_ = {}             % DATA field names the columns menu was last built from
        MenuShown_ = {}              % ParametersOfInterest the menu check state was last built from
    end

    properties (Constant, Access = private)
        REQUIRED_FIELDS = {'RespCode','TrialID','computerTimestamp'}
        NO_PARAMS_SENTINEL = '(none)' % ParametersOfInterest entry meaning "hide all parameters"
        PREF_GROUP = 'epsych2_gui_History'
        TRIAL_COLUMN = 'Trial'        % Leading column holding the chronological trial number
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
                % Listener first, then psychObj: set.psychObj validates and
                % renders, so assigning it last makes that the single initial
                % render rather than one before the listener exists.
                obj.hl_NewData = listener(pObj.Helper,'NewData',@obj.update);
                obj.psychObj = pObj;
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
            % RowName is emptied once and never written again: the trial
            % number is a Data column instead. Every changed uitable property
            % costs a view round-trip of tens of ms regardless of row count,
            % so a per-trial RowName rewrite is pure overhead.
            obj.TableH = uitable(obj.ContainerH,'Unit','Normalized', ...
                'Position',[0 0 1 1],'RowStriping','on','RowName',{});
            try
                obj.TableH.ColumnSortable = true;
                obj.TableH.ColumnRearrangeable = true;
                obj.TableH.DisplayDataChangedFcn = @obj.onDisplayDataChanged;
            catch ME
                % Header-click sorting and drag-to-rearrange require a uifigure-based uitable.
                vprintf(3,'gui.History: column sorting/rearranging unavailable: %s',ME.message)
            end
            obj.buildContextMenu;
        end

        function update(obj,~,~)
            % update(obj, ~, ~)
            % Refresh table data, row ordering, labels, formats, and row colors.
            %
            % No per-update vprintf: with the default GLogVerbosity of Inf a
            % level-4 record is never suppressed, so it would cost a
            % dbstack('-completenames') and a log write on every trial.
            if isempty(obj.TableH) || ~isvalid(obj.TableH), return; end
            if obj.Updating_, return; end
            if ~epsych.Helper.valid_psych_obj(obj.psychObj), return; end
            if isempty(obj.psychObj.DATA), return; end

            obj.Updating_ = true;
            guard = onCleanup(@() obj.endUpdate_);

            obj.applyPendingPreferences;

            [RD,FN] = obj.rearrange_data;
            if isempty(RD), return; end

            columnNames = [{obj.TRIAL_COLUMN}; {'Time'}; {'Response'}; FN];

            order = obj.resolveDisplayOrder(RD,columnNames);
            obj.Info.DisplayOrder = order;

            tableData = obj.formatTableData(RD(order,:),columnNames);

            colOrder = obj.resolveColumnOrder(columnNames);
            columnNames = columnNames(colOrder);
            tableData = tableData(:,colOrder);

            rowColors = obj.resolveRowColors(order);
            [tableData,rowColors] = obj.padToBlock(tableData,rowColors);

            obj.writeTable(tableData,columnNames,rowColors);
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

    methods (Access = protected)
        function c = popOutHostContainer_(obj)
            % Container this table was built into (gui.PopOut).
            c = obj.ContainerH;
        end

        function h = createPopOut_(obj,container)
            % A second history table over the same psychophysics object, in
            % its own window. On first open it mirrors the host's columns
            % and sort; from then on it saves and restores its own layout
            % under its own tag, so hiding a column there leaves the
            % embedded table alone.
            tag = obj.popOutPreferenceTag_();
            hasSaved = ispref(obj.PREF_GROUP,tag);

            h = gui.History(obj.psychObj,container, ...
                ColumnFormats=obj.ColumnFormats, ...
                BitColors=obj.BitColors, ...
                PreferenceTag=tag);
            h.RowBlockSize = obj.RowBlockSize;

            if hasSaved, return; end % the constructor already staged its own layout

            % Formats are cleared first so the parameter count can change
            % without tripping the correspondence check.
            h.ParameterColumnFormats = string.empty(0,1);
            h.ParametersOfInterest   = obj.ParametersOfInterest;
            h.ParameterColumnFormats = obj.ParameterColumnFormats;
            h.SortByColumn  = obj.SortByColumn;
            h.SortDirection = obj.SortDirection;
            h.ColumnOrder_  = obj.ColumnOrder_;
            h.savePreferences;
            h.update;
        end
    end

    methods (Access = private)
        function endUpdate_(obj)
            % endUpdate_(obj)
            % Release the reentrancy guard; called from update's onCleanup so
            % an early return or an error cannot leave update wedged shut.
            obj.Updating_ = false;
        end

        function C = resolveRowColors(obj,order)
            % C = resolveRowColors(obj, order)
            % RGB row colors for the given display order, from decoded
            % response bits.
            %
            % Parameters:
            %   order - Display row order into the chronological trial list.
            %
            % Returns:
            %   C - numel(order)x3 RGB array.
            C = zeros(0,3);
            if ~epsych.Helper.valid_psych_obj(obj.psychObj), return; end
            if isempty(obj.Info) || ~isfield(obj.Info,'ResponseBit'), return; end

            responseBits = epsych.BitMask.getResponses;
            n = numel(obj.Info.ResponseBit);
            i = order(:);
            if isempty(i) || max(i) > n
                i = (n:-1:1)'; % default display order: newest trial first
            end
            R = obj.Info.ResponseBit(i);
            hexC = repmat(epsych.BitMask.getDefaultColors(epsych.BitMask.Undefined),numel(R),1);
            bitColors = obj.getBitColors(responseBits);
            for idx = 1:numel(responseBits)
                b = responseBits(idx);
                ind = R == b;
                if ~any(ind), continue; end
                hexC(ind) = repmat(bitColors(idx),sum(ind),1);
            end
            C = hex2rgb(hexC);
        end

        function [dataOut,colorsOut] = padToBlock(obj,dataIn,colorsIn)
            % [dataOut, colorsOut] = padToBlock(obj, dataIn, colorsIn)
            % Pad the rendered rows out to a multiple of RowBlockSize.
            %
            % A uitable whose row COUNT changes makes the view rebuild its row
            % model, which measures several times more than replacing the cell
            % contents at a fixed count. Holding the count constant between
            % block boundaries pays that cost once per block instead of once
            % per trial. Padding rows are blank and white, so they read as
            % empty space below the oldest trial.
            dataOut = dataIn;
            colorsOut = colorsIn;
            n = size(dataIn,1);
            blk = obj.RowBlockSize;
            if blk <= 1 || n == 0, return; end

            cap = max(blk,ceil(n/blk)*blk);
            if cap == n, return; end

            dataOut = repmat({''},cap,size(dataIn,2));
            dataOut(1:n,:) = dataIn;
            colorsOut = ones(cap,3);
            if ~isempty(colorsIn)
                colorsOut(1:size(colorsIn,1),:) = colorsIn;
            end
        end

        function writeTable(obj,tableData,columnNames,rowColors)
            % writeTable(obj, tableData, columnNames, rowColors)
            % Push the rendered table to the uitable, skipping the column
            % properties when they are unchanged: a changed column name or
            % format makes the view rebuild its column model.
            obj.TableH.Data = tableData;
            if ~isempty(rowColors)
                obj.TableH.BackgroundColor = rowColors;
            end
            if ~isequal(cellstr(string(obj.TableH.ColumnName(:))),columnNames(:))
                obj.TableH.ColumnName = columnNames;
                obj.TableH.ColumnFormat = repmat({'char'},1,numel(columnNames));
            end
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
            % Trial number leads as a normal column rather than a RowName, so
            % the row headers never have to be rewritten. Kept numeric here so
            % sorting on it orders numerically.
            DataOut = [num2cell(obj.Info.TrialNumber(:)) DataOut];

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

        function order = resolveColumnOrder(obj,columnNames)
            % order = resolveColumnOrder(obj, columnNames)
            % Apply the user's saved drag-to-rearrange column order.
            % Columns not present in the saved order (new parameters, or
            % a saved order from a prior parameter set) keep their
            % original relative position, appended after known columns.
            n = numel(columnNames);
            order = (1:n)';
            stored = obj.ColumnOrder_;
            if isempty(stored), return; end

            [tf,idx] = ismember(stored,columnNames);
            known = idx(tf);
            remaining = setdiff((1:n)',known,'stable');
            order = [known(:); remaining(:)];
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
            % ordering so the selection persists across trial updates, or
            % record a drag-to-rearrange column order.
            try
                if string(event.Interaction) == "rearrange"
                    obj.onColumnsRearranged(event);
                    return
                end
            catch
                % Interaction unavailable; fall through to legacy sort handling.
            end

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

        function onColumnsRearranged(obj,event)
            % onColumnsRearranged(obj, event)
            % Persist a user drag-to-rearrange column order.
            try
                newOrder = cellstr(string(event.DisplayColumnName));
            catch ME
                vprintf(2,'gui.History: unable to read rearranged column order: %s',ME.message)
                return
            end
            if isempty(newOrder), return; end
            obj.ColumnOrder_ = newOrder(:);
            obj.savePreferences;
        end

        function resetSort(obj)
            % resetSort(obj)
            % Restore the default sort: newest trial at the top.
            obj.SortByColumn = "Time";
            obj.SortDirection = "descend";
            obj.savePreferences;
            obj.update;
        end

        function resetColumnOrder(obj)
            % resetColumnOrder(obj)
            % Restore the default column order (Time, Response, then
            % parameters in their natural order).
            obj.ColumnOrder_ = {};
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
                uimenu(obj.ContextMenuH,'Text','Reset Column Order', ...
                    'MenuSelectedFcn',@(~,~) obj.resetColumnOrder);
                obj.addPopOutMenu_(obj.ContextMenuH);
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

            % The menu depends only on the DATA field set and the shown
            % parameters, neither of which normally changes between trials.
            % Every Checked write is a view round-trip, so skip the whole
            % method when nothing it renders has moved.
            fields = fieldnames(obj.psychObj.DATA);
            if isequal(fields,obj.MenuFields_) && isequal(obj.ParametersOfInterest,obj.MenuShown_)
                return
            end
            obj.MenuFields_ = fields;
            obj.MenuShown_ = obj.ParametersOfInterest;

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
                s.ColumnOrder = obj.ColumnOrder_;
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
                if isfield(s,'ColumnOrder') && ~isempty(s.ColumnOrder)
                    stored = cellstr(s.ColumnOrder);
                    % Orders saved before the Trial column existed would push
                    % it to the far right, since resolveColumnOrder appends
                    % unknown columns. Lead with it instead.
                    if ~ismember(obj.TRIAL_COLUMN,stored)
                        stored = [{obj.TRIAL_COLUMN}; stored(:)];
                    end
                    obj.ColumnOrder_ = stored;
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

            % Columns 1-3 are Trial, Time and Response; parameters follow.
            nParameterCols = max(nCols-3,0);
            if nParameterCols == 0
                return
            end

            if isscalar(parameterFormats)
                formats(4:end) = repmat(parameterFormats,nParameterCols,1);
            elseif ~isempty(obj.ParametersOfInterest) && numel(parameterFormats) == numel(obj.ParametersOfInterest)
                parameterNames = string(columnNames(4:end));
                [isMatched,formatIdx] = ismember(parameterNames,string(obj.ParametersOfInterest));
                if ~all(isMatched)
                    error("ParameterColumnFormats must correspond to ParametersOfInterest names.");
                end
                formats(4:end) = parameterFormats(formatIdx);
            elseif numel(parameterFormats) == nParameterCols
                formats(4:end) = parameterFormats;
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
