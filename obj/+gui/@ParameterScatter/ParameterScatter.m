classdef ParameterScatter < gui.PopOut
    % obj = gui.ParameterScatter(source, container)
    % Generic trial-parameter scatter plot for custom behavior GUIs.
    %
    % Compares any two per-trial parameters recorded in the current
    % experiment. X, Y, and an optional color-by parameter are chosen from
    % dropdowns at any time and the plot updates immediately; a NewData
    % listener refreshes the plot after every completed trial. "Trial
    % Number" (chronological DATA index) is always offered as a parameter.
    % When constructed from a runtime the lists are seeded from the
    % parameters it will record, so they are populated before the first
    % trial. Parameters flagged Visible=false on their hw.Parameter are
    % excluded from the selectable lists, as are array-valued and
    % write-only parameters.
    %
    % "Response" is offered whenever the experiment records a response code
    % (a RespCode/ResponseCode DATA field): a categorical parameter holding
    % the decoded outcome name (Hit, Miss, CorrectReject, FalseAlarm, Abort,
    % or Undefined) rather than the raw bitmask value.
    %
    % Categorical (text) parameters, e.g. a scalar char/string DATA field or
    % a runtime parameter with Type='String', are offered alongside numeric
    % ones. On a categorical axis, points are placed at integer positions
    % per distinct value seen so far and the axis ticks are labeled with
    % those values; log scale is skipped for that axis. As a color-by
    % parameter, a categorical is mapped to one discrete color per distinct
    % value with the colorbar ticks labeled instead of a continuous scale.
    % The set of known categories only grows, so a value's plotted position
    % or color stays fixed once assigned, even as new categories appear.
    %
    % Display behavior:
    %   - Right-click the axes for basic aesthetics: marker style, size,
    %     opacity, color, colormap (for color-by mode), log scales, grid.
    %   - Right-click > Open in Separate Window (or the popOut method) opens
    %     a second, independent scatter over the same data in a window of
    %     its own; see gui.PopOut.
    %   - Parameter selections and aesthetics persist across sessions via
    %     getpref/setpref, keyed to the hosting GUI figure (or an explicit
    %     PreferenceTag). Selections passed to the constructor are the
    %     first-session defaults only; saved ones take precedence.
    %   - The plot can be hosted in any graphics container (uifigure,
    %     legacy figure, panel, tab, or a uigridlayout cell) and adapts to
    %     resizing. uifigure-family containers get a uigridlayout/uidropdown
    %     control row; legacy figures get equivalent uicontrol popupmenus.
    %
    % Properties:
    %   XParameter, YParameter - Selected DATA field names (or 'Trial Number'
    %                            / 'Response')
    %   ColorParameter         - Third parameter for marker color, or '(none)'
    %   Marker, MarkerSize, MarkerColor, MarkerAlpha - Marker aesthetics
    %   ColormapName           - Colormap used when colorizing by a parameter
    %   LogX, LogY, ShowGrid   - Axes aesthetics
    %   BoxID                  - Restrict NewData updates to these boxes; empty accepts all
    %
    % Methods:
    %   ParameterScatter - Construct the plot UI and attach the NewData listener
    %   update           - Refresh parameter lists and redraw from current data
    %   delete           - Cleanup listener and context menu resources
    %
    % Examples:
    %   % In a custom behavior GUI (online; pObj is e.g. psychophysics.Detection):
    %   obj.hScatter = gui.ParameterScatter(pObj, parentPanel);
    %
    %   % Directly from the runtime:
    %   obj.hScatter = gui.ParameterScatter(RUNTIME, parentPanel);
    %
    %   % Offline, from saved trial data:
    %   S = gui.ParameterScatter(DATA, uifigure);
    %
    % See also: documentation/gui/gui_ParameterScatter.md, gui.History

    properties
        XParameter     (1,:) char = ''        % DATA field for the x axis; empty = auto
        YParameter     (1,:) char = ''        % DATA field for the y axis; empty = auto
        ColorParameter (1,:) char = '(none)'  % DATA field for marker color, or '(none)'

        Marker      (1,:) char {mustBeMember(Marker,{'o','s','d','^','v','p','h'})} = 'o'
        MarkerSize  (1,1) double {mustBePositive,mustBeFinite} = 48
        MarkerColor (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(MarkerColor,1)} = [0 .4 .8]
        MarkerAlpha (1,1) double {mustBeNonnegative,mustBeLessThanOrEqual(MarkerAlpha,1)} = 0.6
        ColormapName (1,:) char = 'parula'    % colormap used in color-by mode

        LogX     (1,1) logical = false
        LogY     (1,1) logical = false
        ShowGrid (1,1) logical = true

        BoxID (1,:) double = [] % restrict NewData updates to these boxes; empty accepts all
    end

    properties (SetAccess = private)
        AxesH                        % Axes hosting the scatter
        ScatterH = []                % Scatter graphics object
        ColorbarH = []               % Colorbar shown in color-by mode
        ContainerH                   % Hosting container supplied at construction
        DropdownX                    % X parameter selector
        DropdownY                    % Y parameter selector
        DropdownC                    % Color-by parameter selector

        hl_NewData = event.listener.empty % Listener for NewData events
    end

    properties (Access = private)
        DATA_ = []                   % Cached per-trial data struct array
        Source_ = []                 % Construction source, reused to build a pop-out
        Runtime_ = []                % epsych.Runtime used to resolve the parameter lists
        PanelH_ = []                 % Wrapper panel (legacy-figure hosting only)
        LabelX_ = []                 % X control label (legacy-figure hosting only)
        LabelY_ = []                 % Y control label (legacy-figure hosting only)
        LabelC_ = []                 % Color control label (legacy-figure hosting only)
        ContextMenuH_ = []           % Right-click aesthetics menu
        PendingSelections_ = []      % Requested selections awaiting their parameters
        PreferenceTag_ char = ''     % Optional explicit preference key
        isWeb_ (1,1) logical = true  % True when hosted in uifigure-family graphics
        suspend_ (1,1) logical = false % Guard against redraw recursion during batch updates
        runtimeResolved_ (1,1) logical = false
        InvisibleNames_ (1,:) cell = {} % validNames of invisible parameters
        DeclaredNames_ (1,:) cell = {}  % validNames the runtime will record once trials begin
        DeclaredCategoricalNames_ (1,:) cell = {} % validNames of runtime-declared text parameters
        CategoricalNames_ (1,:) cell = {} % validNames currently treated as text/categorical
        CategoryLevels_ = struct()  % validName -> cellstr of distinct values seen so far, in assigned order
        ResponseField_ (1,:) char = '' % DATA field holding response codes, backing the Response parameter

        % Per-trial value caches, one entry per parameter. A trial's value is
        % fixed once recorded and a category keeps the code it was first
        % assigned, so each redraw reads only the trials added since the last
        % one -- a redraw asks for the x, y and color parameters and used to
        % re-read the whole session for each.
        ValueCache_ = struct()      % validName -> 1xN numeric values
        CodeCache_ = struct()       % validName -> 1xN categorical codes
        CacheFingerprint_ = {}      % identifies the trials the caches were built from
    end

    properties (Constant, Access = private)
        TRIAL_NUMBER_LABEL = 'Trial Number' % synthetic parameter: chronological DATA index
        RESPONSE_LABEL = 'Response'         % synthetic parameter: response code decoded to its outcome name
        RESPONSE_CODE_FIELDS = {'RespCode','ResponseCode'} % DATA fields that may back the Response parameter
        NONE_LABEL = '(none)'               % ColorParameter entry meaning "flat marker color"
        PLOTTABLE_TYPES = {'Float','Integer','Boolean'} % hw.Parameter types that yield a plottable scalar
        CATEGORICAL_TYPES = {'String'}      % hw.Parameter types that yield a plottable text value
        SELECTION_FIELDS = {'XParameter','YParameter','ColorParameter'}
        PREF_GROUP = 'epsych2_gui_ParameterScatter'
        VALID_MARKERS = {'o','s','d','^','v','p','h'}
        VALID_COLORMAPS = {'parula','turbo','jet','hot','cool','copper','bone'}
        MARKER_SIZES = [12 24 36 48 72 96 144]
        MARKER_ALPHAS = [0.25 0.5 0.75 1]
    end

    methods
        function obj = ParameterScatter(source, container, options)
            % obj = gui.ParameterScatter(source, container)
            % obj = gui.ParameterScatter(source, container, PreferenceTag=tag)
            % Initialize the scatter plot UI and attach the data listener.
            %
            % Parameters:
            %   source - Data source: a psychophysics object (updates via its
            %       Helper NewData event), an epsych.Runtime (updates via
            %       RUNTIME.HELPER), or a DATA struct array for offline use.
            %   container - Figure, panel, tab, or layout host. If empty,
            %       creates a uifigure.
            %   options.PreferenceTag - Optional key for saved preferences;
            %       defaults to the hosting figure Tag (or Name) so each GUI
            %       keeps its own settings.
            %   options.BoxID - Restrict NewData updates to these boxes.
            %   options.XParameter, options.YParameter, options.ColorParameter -
            %       Initial selections used only when nothing was saved for
            %       this PreferenceTag; a selection restored from a previous
            %       session wins. Applied once the named parameters appear in
            %       the data, so they survive construction before the first
            %       trial.
            %
            % Returns:
            %   obj - gui.ParameterScatter object.
            arguments
                source = []
                container = []
                options.PreferenceTag {mustBeTextScalar} = ''
                options.BoxID (1,:) double = []
                options.XParameter {mustBeTextScalar} = ''
                options.YParameter {mustBeTextScalar} = ''
                options.ColorParameter {mustBeTextScalar} = ''
            end

            if isempty(container)
                container = uifigure('Name','Parameter Scatter');
            end
            obj.ContainerH = container;
            obj.PreferenceTag_ = char(options.PreferenceTag);
            obj.BoxID = options.BoxID;

            obj.build_(container);
            obj.loadPreferences_;

            % Constructor selections seed the first-ever view only; a saved
            % selection outranks them so the user's last choice sticks.
            obj.stageSelection_('XParameter',options.XParameter,true);
            obj.stageSelection_('YParameter',options.YParameter,true);
            obj.stageSelection_('ColorParameter',options.ColorParameter,true);

            obj.attachSource_(source);
            obj.update;
        end

        function delete(obj)
            % delete(obj)
            % Release the NewData listener and context menu resources.
            if ~isempty(obj.hl_NewData)
                listeners = obj.hl_NewData(isvalid(obj.hl_NewData));
                if ~isempty(listeners), delete(listeners); end
                obj.hl_NewData = event.listener.empty;
            end
            if ~isempty(obj.ContextMenuH_) && isvalid(obj.ContextMenuH_)
                delete(obj.ContextMenuH_);
            end
        end

        function update(obj,~,~)
            % update(obj, ~, ~)
            % Refresh the selectable parameter lists and redraw the scatter.
            if isempty(obj.AxesH) || ~isvalid(obj.AxesH), return; end
            vprintf(4,'Updating ParameterScatter')

            D = obj.currentData_;
            avail = obj.availableParameters_(D);
            obj.applyPendingSelections_(avail);

            obj.suspend_ = true;
            if ~ismember(obj.XParameter,avail)
                obj.XParameter = obj.TRIAL_NUMBER_LABEL;
            end
            if ~ismember(obj.YParameter,avail)
                others = setdiff(avail,{obj.TRIAL_NUMBER_LABEL},'stable');
                if isempty(others)
                    obj.YParameter = obj.TRIAL_NUMBER_LABEL;
                else
                    obj.YParameter = others{1};
                end
            end
            if ~ismember(obj.ColorParameter,[{obj.NONE_LABEL} avail])
                obj.ColorParameter = obj.NONE_LABEL;
            end
            obj.setDropdownItems_(obj.DropdownX,avail,obj.XParameter);
            obj.setDropdownItems_(obj.DropdownY,avail,obj.YParameter);
            obj.setDropdownItems_(obj.DropdownC,[{obj.NONE_LABEL} avail],obj.ColorParameter);
            obj.suspend_ = false;

            obj.redraw_(D);
        end

        function onNewData(obj,~,event)
            % onNewData(obj, ~, event)
            % NewData listener callback: cache the trial data and refresh.
            %
            % Parameters:
            %   event - Event payload with event.Data.DATA (epsych.TrialsData).
            try
                if ~isempty(obj.BoxID) && ~isempty(event.BoxID) ...
                        && ~ismember(event.BoxID,obj.BoxID)
                    return
                end
            catch
                % Event without box information; accept it.
            end
            obj.DATA_ = event.Data.DATA;
            obj.update;
        end

        function onSelectionChanged(obj,~,~)
            % onSelectionChanged(obj, ~, ~)
            % Dropdown callback: apply the selections, persist them, redraw.
            obj.suspend_ = true;
            obj.XParameter = obj.getDropdownValue_(obj.DropdownX);
            obj.YParameter = obj.getDropdownValue_(obj.DropdownY);
            obj.ColorParameter = obj.getDropdownValue_(obj.DropdownC);
            obj.PendingSelections_ = []; % an explicit choice outranks any staged one
            obj.suspend_ = false;
            obj.savePreferences_;
            obj.redraw_(obj.currentData_);
        end

        function set.XParameter(obj,v)
            obj.XParameter = char(string(v));
            obj.selectionChanged_;
        end

        function set.YParameter(obj,v)
            obj.YParameter = char(string(v));
            obj.selectionChanged_;
        end

        function set.ColorParameter(obj,v)
            v = char(string(v));
            if isempty(v), v = obj.NONE_LABEL; end
            obj.ColorParameter = v;
            obj.selectionChanged_;
        end
    end

    methods (Access = protected)
        function c = popOutHostContainer_(obj)
            % Container this scatter was built into (gui.PopOut).
            c = obj.ContainerH;
        end

        function h = createPopOut_(obj,container)
            % A second scatter over the same source, in its own window.
            % Current selections are passed as constructor defaults, so the
            % window opens on what the host is showing; from then on the
            % pop-out saves and restores its own choices under its own tag,
            % and nothing it does reaches the host.
            tag = obj.popOutPreferenceTag_();
            hasSaved = ispref(obj.PREF_GROUP,tag);

            h = gui.ParameterScatter(obj.Source_,container, ...
                PreferenceTag=tag, ...
                BoxID=obj.BoxID, ...
                XParameter=obj.XParameter, ...
                YParameter=obj.YParameter, ...
                ColorParameter=obj.ColorParameter);

            if hasSaved, return; end % it has aesthetics of its own already

            aes = {'Marker','MarkerSize','MarkerColor','MarkerAlpha', ...
                'ColormapName','LogX','LogY','ShowGrid'};
            for k = 1:numel(aes)
                h.(aes{k}) = obj.(aes{k});
            end
            h.savePreferences_;
            h.refreshMenuChecks_;
            h.update;
        end
    end

    methods (Access = private)
        function attachSource_(obj,source)
            % Resolve the data source and attach the NewData listener.
            obj.Source_ = source; % kept so a pop-out can attach to the same source
            if isstruct(source)
                obj.DATA_ = source; % offline data; no listener
            elseif isa(source,'epsych.Runtime') || (isobject(source) && isprop(source,'HELPER'))
                obj.Runtime_ = source;
                obj.hl_NewData = listener(source.HELPER,'NewData',@obj.onNewData);
                try
                    obj.DATA_ = source.TRIALS(1).DATA;
                catch
                    % No trial data yet; first NewData event populates it.
                end
            elseif epsych.Helper.valid_psych_obj(source)
                obj.Runtime_ = source.RUNTIME;
                obj.hl_NewData = listener(source.Helper,'NewData',@obj.onNewData);
                obj.DATA_ = source.DATA;
            else
                error('gui:ParameterScatter:InvalidSource', ...
                    'source must be a psychophysics object, an epsych.Runtime, or a DATA struct array');
            end
        end

        function build_(obj,container)
            % Create the control row and axes inside the container.
            try
                g = uigridlayout(container,[2 1]);
                g.RowHeight = {'fit','1x'};
                g.ColumnWidth = {'1x'};
                g.Padding = [2 2 2 2];
                g.RowSpacing = 2;

                ctrl = uigridlayout(g,[1 6]);
                ctrl.ColumnWidth = {'fit','1x','fit','1x','fit','1x'};
                ctrl.RowHeight = {'fit'};
                ctrl.Padding = [0 0 0 0];
                ctrl.ColumnSpacing = 4;

                uilabel(ctrl,'Text','X:');
                obj.DropdownX = uidropdown(ctrl,'Items',{obj.TRIAL_NUMBER_LABEL}, ...
                    'ValueChangedFcn',@obj.onSelectionChanged);
                uilabel(ctrl,'Text','Y:');
                obj.DropdownY = uidropdown(ctrl,'Items',{obj.TRIAL_NUMBER_LABEL}, ...
                    'ValueChangedFcn',@obj.onSelectionChanged);
                uilabel(ctrl,'Text','Color:');
                obj.DropdownC = uidropdown(ctrl,'Items',{obj.NONE_LABEL}, ...
                    'ValueChangedFcn',@obj.onSelectionChanged);

                obj.AxesH = uiaxes(g);
                obj.isWeb_ = true;
            catch
                % Legacy figure hosting: uigridlayout is unavailable, so lay
                % out uicontrols in a borderless wrapper panel we own.
                obj.isWeb_ = false;
                p = uipanel(container,'Units','normalized','Position',[0 0 1 1], ...
                    'BorderType','none');
                obj.PanelH_ = p;
                obj.LabelX_ = uicontrol(p,'Style','text','String','X:', ...
                    'Units','pixels','HorizontalAlignment','right');
                obj.DropdownX = uicontrol(p,'Style','popupmenu', ...
                    'String',{obj.TRIAL_NUMBER_LABEL},'Units','pixels', ...
                    'Callback',@obj.onSelectionChanged);
                obj.LabelY_ = uicontrol(p,'Style','text','String','Y:', ...
                    'Units','pixels','HorizontalAlignment','right');
                obj.DropdownY = uicontrol(p,'Style','popupmenu', ...
                    'String',{obj.TRIAL_NUMBER_LABEL},'Units','pixels', ...
                    'Callback',@obj.onSelectionChanged);
                obj.LabelC_ = uicontrol(p,'Style','text','String','Color:', ...
                    'Units','pixels','HorizontalAlignment','right');
                obj.DropdownC = uicontrol(p,'Style','popupmenu', ...
                    'String',{obj.NONE_LABEL},'Units','pixels', ...
                    'Callback',@obj.onSelectionChanged);
                obj.AxesH = axes('Parent',p,'Units','pixels');
                p.SizeChangedFcn = @(~,~) obj.classicResize_;
                obj.classicResize_;
            end
            box(obj.AxesH,'on');
            obj.buildContextMenu_;
        end

        function classicResize_(obj)
            % Keep a fixed-height control strip above the axes (legacy hosting).
            if isempty(obj.PanelH_) || ~isvalid(obj.PanelH_), return; end
            pos = getpixelposition(obj.PanelH_);
            w = max(pos(3),200);
            h = max(pos(4),120);
            pad = 4; ctrlH = 22;
            labW = [20 20 40];
            ddW = max(50,floor((w - sum(labW) - 7*pad)/3));
            y = h - ctrlH - pad;
            x = pad;
            obj.LabelX_.Position   = [x y-3 labW(1) ctrlH]; x = x + labW(1) + pad;
            obj.DropdownX.Position = [x y ddW ctrlH];       x = x + ddW + pad;
            obj.LabelY_.Position   = [x y-3 labW(2) ctrlH]; x = x + labW(2) + pad;
            obj.DropdownY.Position = [x y ddW ctrlH];       x = x + ddW + pad;
            obj.LabelC_.Position   = [x y-3 labW(3) ctrlH]; x = x + labW(3) + pad;
            obj.DropdownC.Position = [x y ddW ctrlH];
            obj.AxesH.OuterPosition = [pad pad w-2*pad max(20,y-2*pad)];
        end

        function selectionChanged_(obj)
            % Programmatic selection change: revalidate lists and redraw.
            if obj.suspend_ || isempty(obj.DropdownX), return; end
            obj.update;
        end

        function D = currentData_(obj)
            % Cached DATA with the preallocated-but-empty first trial guard.
            D = obj.DATA_;
            if ~isempty(D) && isfield(D,'TrialID') && isempty(D(1).TrialID)
                D = D([]);
            end
        end

        function avail = availableParameters_(obj,D)
            % Parameters offered in the selectors: scalar numeric or scalar
            % text DATA fields plus the parameters the runtime will record
            % once trials begin, less invisible ones, plus the synthetic
            % Trial Number and Response entries. The runtime-declared names
            % keep the selectors usable before the first trial, when DATA has
            % no fields to learn from.
            obj.resolveRuntimeNames_;
            numFn = {};
            catFn = {};
            if ~isempty(D)
                f = fieldnames(D);
                isNum = false(size(f));
                isCat = false(size(f));
                for k = 1:numel(f)
                    v = D(1).(f{k});
                    if isstruct(v) && isfield(v,'Value'), v = v.Value; end
                    isNum(k) = (isnumeric(v) || islogical(v)) && isscalar(v);
                    isCat(k) = ischar(v) || (isstring(v) && isscalar(v));
                end
                numFn = f(isNum);
                catFn = f(isCat);
            end
            numFn = union(numFn(:)',obj.DeclaredNames_);
            catFn = union(catFn(:)',obj.DeclaredCategoricalNames_);
            obj.CategoricalNames_ = setdiff(catFn,obj.InvisibleNames_);

            % A response code is far more useful decoded than as a bitmask
            % integer, so offer the decoded outcome name as its own
            % categorical parameter alongside the raw code.
            obj.ResponseField_ = obj.resolveResponseField_(D,numFn);
            if ~isempty(obj.ResponseField_) && ~ismember(obj.RESPONSE_LABEL,union(numFn,catFn))
                obj.CategoricalNames_ = [obj.CategoricalNames_ {obj.RESPONSE_LABEL}];
                obj.seedResponseLevels_;
            end

            fn = setdiff(union(numFn,obj.CategoricalNames_),obj.InvisibleNames_);
            avail = [{obj.TRIAL_NUMBER_LABEL} sort(fn(:))'];
        end

        function name = resolveResponseField_(obj,D,numFn)
            % DATA field backing the synthetic Response parameter, or ''.
            % Runtime-declared names are consulted too so Response is
            % selectable before the first trial has written any DATA fields.
            % Invisible names count: hiding the raw code is not a reason to
            % withhold the decoded outcome, and leaving them out would offer
            % Response only from the first trial on.
            name = '';
            candidates = union(numFn,obj.InvisibleNames_);
            if isstruct(D), candidates = union(candidates,fieldnames(D)'); end
            if isempty(candidates), return; end
            for k = 1:numel(obj.RESPONSE_CODE_FIELDS)
                idx = find(strcmpi(candidates,obj.RESPONSE_CODE_FIELDS{k}),1);
                if ~isempty(idx)
                    name = candidates{idx};
                    return
                end
            end
        end

        function seedResponseLevels_(obj)
            % Seed the Response categories with the full outcome set so a
            % given outcome keeps the same position and color from the first
            % trial on, and across sessions, regardless of what has occurred.
            if isfield(obj.CategoryLevels_,obj.RESPONSE_LABEL), return; end
            bm = [epsych.BitMask.getResponses epsych.BitMask.Undefined];
            obj.CategoryLevels_.(obj.RESPONSE_LABEL) = cellstr(string(bm(:)'));
        end

        function txt = responseText_(obj,D,first)
            % Decoded outcome name for trials first:end ('' where no code is
            % available). Mirrors psychophysics.Psych.responseBits: with more
            % than one response bit set, the last one in enum order wins.
            if nargin < 3, first = 1; end
            n = numel(D);
            txt = repmat({''},1,max(n-first+1,0));
            if isempty(obj.ResponseField_) || isempty(D) || ~isfield(D,obj.ResponseField_)
                return
            end
            rc = obj.parameterValues_(D,obj.ResponseField_);
            rc = rc(first:end);
            valid = isfinite(rc) & rc >= 0;
            if ~any(valid), return; end
            decoded = epsych.BitMask.decode(uint32(rc(valid)));
            names = repmat({char(epsych.BitMask.Undefined)},1,sum(valid));
            for bm = epsych.BitMask.getResponses
                ind = decoded.(char(bm));
                if ~any(ind), continue; end
                names(ind) = {char(bm)};
            end
            txt(valid) = names;
        end

        function resolveRuntimeNames_(obj)
            % Resolve, once, the runtime's invisible parameters and the
            % parameters it will record as DATA fields, split into numeric
            % (DeclaredNames_) and text (DeclaredCategoricalNames_). Recorded
            % fields come from the Access='Read' set (see
            % ep_TimerFcn_RunTime), so the declared lists mirror that filter
            % minus array-valued types and types that yield neither a
            % plottable scalar nor a plottable text value.
            if obj.runtimeResolved_, return; end
            R = obj.Runtime_;
            if isempty(R)
                obj.runtimeResolved_ = true;
                return
            end
            try
                P = R.all_parameters(includeInvisible=true,includeTriggers=true,Access='All');
                if ~isempty(P)
                    obj.InvisibleNames_ = {P(~[P.Visible]).validName};
                    plottable = [P.Visible] & ~[P.isArray] ...
                        & ismember({P.Type},obj.PLOTTABLE_TYPES) ...
                        & ~strcmp({P.Access},'Write');
                    obj.DeclaredNames_ = {P(plottable).validName};
                    categorical = [P.Visible] & ~[P.isArray] ...
                        & ismember({P.Type},obj.CATEGORICAL_TYPES) ...
                        & ~strcmp({P.Access},'Write');
                    obj.DeclaredCategoricalNames_ = {P(categorical).validName};
                end
                obj.runtimeResolved_ = true;
            catch ME
                vprintf(3,'gui.ParameterScatter: unable to resolve runtime parameters: %s',ME.message)
            end
        end

        function syncCaches_(obj,D)
            % Drop the per-trial caches when the trials were replaced rather
            % than extended. Within a session DATA only grows, so a value
            % already read for a trial stays valid.
            fp = {};
            if ~isempty(D)
                fp = {numel(fieldnames(D))};
                if isfield(D,'TrialID'), fp{end+1} = D(1).TrialID; end
                if isfield(D,'computerTimestamp'), fp{end+1} = D(1).computerTimestamp; end
            end
            if isequaln(fp,obj.CacheFingerprint_), return; end
            obj.ValueCache_ = struct();
            obj.CodeCache_ = struct();
            obj.CacheFingerprint_ = fp;
        end

        function v = parameterValues_(obj,D,name)
            % Per-trial numeric values for a parameter; NaN where unavailable.
            % Trials already read are reused; only the new ones are extracted.
            n = numel(D);
            if strcmp(name,obj.TRIAL_NUMBER_LABEL)
                v = 1:n;
                return
            end
            if isempty(D) || ~isfield(D,name)
                v = nan(1,n); % nothing to cache: the field is not recorded
                return
            end

            key = matlab.lang.makeValidName(name);
            v = zeros(1,0);
            if isfield(obj.ValueCache_,key)
                v = obj.ValueCache_.(key);
                if numel(v) > n, v = zeros(1,0); end
            end

            first = numel(v) + 1;
            if first <= n
                vNew = nan(1,n-first+1);
                for k = first:n
                    val = D(k).(name);
                    if isstruct(val) && isfield(val,'Value'), val = val.Value; end
                    if (isnumeric(val) || islogical(val)) && isscalar(val)
                        vNew(k-first+1) = double(val);
                    end
                end
                v = [v vNew];
                obj.ValueCache_.(key) = v;
            end
        end

        function [v,labels] = categoricalCodes_(obj,D,name)
            % Per-trial integer codes for a text parameter, plus the ordered
            % category labels those codes index into. Codes are assigned the
            % first time a value is seen and never reassigned, so a category
            % keeps its plotted position/color as later trials add new ones --
            % which also makes an assigned code final, so only the trials
            % added since the last redraw are coded.
            n = numel(D);
            key = matlab.lang.makeValidName(name);

            v = zeros(1,0);
            if isfield(obj.CodeCache_,key)
                v = obj.CodeCache_.(key);
                if numel(v) > n, v = zeros(1,0); end
            end

            if isfield(obj.CategoryLevels_,name)
                labels = obj.CategoryLevels_.(name);
            else
                labels = {};
            end

            first = numel(v) + 1;
            if first > n, return; end

            txt = obj.categoricalText_(D,name,first);

            seen = txt(~cellfun(@isempty,txt));
            newLevels = setdiff(unique(seen,'stable'),labels,'stable');
            if ~isempty(newLevels)
                labels = [labels sort(newLevels)];
                obj.CategoryLevels_.(name) = labels;
            end

            vNew = nan(1,numel(txt));
            filled = ~cellfun(@isempty,txt);
            if any(filled)
                [tf,idx] = ismember(txt(filled),labels);
                coded = nan(1,numel(idx));
                coded(tf) = idx(tf);
                vNew(filled) = coded;
            end

            v = [v vNew];
            obj.CodeCache_.(key) = v;
        end

        function txt = categoricalText_(obj,D,name,first)
            % Text value of a categorical parameter for trials first:end.
            n = numel(D);
            if strcmp(name,obj.RESPONSE_LABEL)
                txt = obj.responseText_(D,first);
                return
            end
            txt = cell(1,n-first+1);
            if isempty(D) || ~isfield(D,name), return; end
            for k = first:n
                val = D(k).(name);
                if isstruct(val) && isfield(val,'Value'), val = val.Value; end
                if ischar(val)
                    txt{k-first+1} = val;
                elseif isstring(val) && isscalar(val)
                    txt{k-first+1} = char(val);
                end
            end
        end

        function redraw_(obj,D)
            % Redraw the scatter from the current selections and aesthetics.
            ax = obj.AxesH;
            if isempty(ax) || ~isvalid(ax), return; end

            obj.syncCaches_(D);

            sh = obj.ScatterH;
            if isempty(sh) || ~isvalid(sh)
                sh = scatter(ax,nan,nan,obj.MarkerSize,'filled');
                obj.ScatterH = sh;
                box(ax,'on');
            end

            isCatX = ismember(obj.XParameter,obj.CategoricalNames_);
            isCatY = ismember(obj.YParameter,obj.CategoricalNames_);
            isCatC = ~strcmp(obj.ColorParameter,obj.NONE_LABEL) ...
                && ismember(obj.ColorParameter,obj.CategoricalNames_);

            if isCatX
                [x,xLabels] = obj.categoricalCodes_(D,obj.XParameter);
            else
                x = obj.parameterValues_(D,obj.XParameter);
                xLabels = {};
            end
            if isCatY
                [y,yLabels] = obj.categoricalCodes_(D,obj.YParameter);
            else
                y = obj.parameterValues_(D,obj.YParameter);
                yLabels = {};
            end

            if strcmp(obj.ColorParameter,obj.NONE_LABEL)
                set(sh,'XData',x,'YData',y,'CData',obj.MarkerColor);
                if ~isempty(obj.ColorbarH) && isvalid(obj.ColorbarH)
                    colorbar(ax,'off');
                    obj.ColorbarH = [];
                end
            elseif isCatC
                [c,cLabels] = obj.categoricalCodes_(D,obj.ColorParameter);
                x(isnan(c)) = nan; % colormapped markers need a color value
                set(sh,'XData',x,'YData',y,'CData',c(:));
                try
                    colormap(ax,feval(obj.ColormapName,max(numel(cLabels),1)));
                catch
                    vprintf(2,'gui.ParameterScatter: unknown colormap "%s"',obj.ColormapName)
                end
                ax.CLim = [0.5 max(numel(cLabels),1)+0.5];
                if isempty(obj.ColorbarH) || ~isvalid(obj.ColorbarH)
                    obj.ColorbarH = colorbar(ax);
                end
                obj.ColorbarH.Ticks = 1:numel(cLabels);
                obj.ColorbarH.TickLabels = cLabels;
                obj.ColorbarH.Label.String = obj.ColorParameter;
                obj.ColorbarH.Label.Interpreter = 'none';
            else
                c = obj.parameterValues_(D,obj.ColorParameter);
                x(isnan(c)) = nan; % colormapped markers need a color value
                set(sh,'XData',x,'YData',y,'CData',c(:));
                try
                    colormap(ax,obj.ColormapName);
                catch
                    vprintf(2,'gui.ParameterScatter: unknown colormap "%s"',obj.ColormapName)
                end
                cf = c(isfinite(c));
                if ~isempty(cf)
                    if min(cf) == max(cf)
                        ax.CLim = min(cf) + [-1 1];
                    else
                        ax.CLim = [min(cf) max(cf)];
                    end
                end
                if isempty(obj.ColorbarH) || ~isvalid(obj.ColorbarH)
                    obj.ColorbarH = colorbar(ax);
                end
                obj.ColorbarH.TicksMode = 'auto';
                obj.ColorbarH.TickLabelsMode = 'auto';
                obj.ColorbarH.Label.String = obj.ColorParameter;
                obj.ColorbarH.Label.Interpreter = 'none';
            end

            set(sh,'Marker',obj.Marker,'SizeData',obj.MarkerSize, ...
                'MarkerFaceAlpha',obj.MarkerAlpha,'MarkerEdgeAlpha',obj.MarkerAlpha);

            if obj.LogX && ~isCatX, ax.XScale = 'log'; else, ax.XScale = 'linear'; end
            if obj.LogY && ~isCatY, ax.YScale = 'log'; else, ax.YScale = 'linear'; end
            if obj.ShowGrid, grid(ax,'on'); else, grid(ax,'off'); end

            if isCatX
                ax.XTick = 1:numel(xLabels);
                ax.XTickLabel = xLabels;
                ax.XTickLabelRotation = 30;
                if ~isempty(xLabels), ax.XLim = [0.5 numel(xLabels)+0.5]; end
            else
                ax.XTickMode = 'auto';
                ax.XTickLabelMode = 'auto';
                ax.XTickLabelRotation = 0;
                ax.XLimMode = 'auto';
            end
            if isCatY
                ax.YTick = 1:numel(yLabels);
                ax.YTickLabel = yLabels;
                if ~isempty(yLabels), ax.YLim = [0.5 numel(yLabels)+0.5]; end
            else
                ax.YTickMode = 'auto';
                ax.YTickLabelMode = 'auto';
                ax.YLimMode = 'auto';
            end

            xlabel(ax,obj.XParameter,'Interpreter','none');
            ylabel(ax,obj.YParameter,'Interpreter','none');
        end

        % ------------------------------------------------------------------
        % Dropdown abstraction: uidropdown (web) vs uicontrol popupmenu (legacy)

        function setDropdownItems_(obj,h,items,value)
            % Replace a dropdown's item list, preserving the selection.
            %
            % The list is written only when it actually changes: the
            % parameters on offer are the same from one trial to the next, and
            % rewriting Items closes the list under a user who has it open
            % mid-selection.
            items = cellstr(items);
            items = items(:)';
            if isempty(items), items = {''}; end
            if obj.isWeb_
                if ~isequal(cellstr(h.Items(:))',items)
                    h.Items = items;
                end
                if ~ismember(value,items), value = items{1}; end
                if ~strcmp(char(h.Value),value)
                    h.Value = value;
                end
            else
                idx = find(strcmp(items,value),1);
                if isempty(idx), idx = 1; end
                if ~isequal(cellstr(h.String(:))',items)
                    h.Value = 1; % keep Value in range while the list changes
                    h.String = items;
                end
                if h.Value ~= idx
                    h.Value = idx;
                end
            end
        end

        function v = getDropdownValue_(obj,h)
            % Currently selected dropdown item as char.
            if obj.isWeb_
                v = char(h.Value);
            else
                s = cellstr(h.String);
                v = s{h.Value};
            end
        end

        % ------------------------------------------------------------------
        % Aesthetics context menu

        function buildContextMenu_(obj)
            % Create the right-click menu for basic plot aesthetics.
            fig = ancestor(obj.AxesH,'figure');
            if isempty(fig), return; end
            try
                cm = uicontextmenu(fig);
                obj.ContextMenuH_ = cm;

                m = uimenu(cm,'Text','Marker');
                for mk = obj.VALID_MARKERS
                    uimenu(m,'Text',mk{1},'Tag',['aes|Marker|' mk{1}], ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('Marker',mk{1}));
                end
                m = uimenu(cm,'Text','Marker Size');
                for sz = obj.MARKER_SIZES
                    uimenu(m,'Text',num2str(sz),'Tag',['aes|MarkerSize|' num2str(sz)], ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('MarkerSize',sz));
                end
                m = uimenu(cm,'Text','Opacity');
                for a = obj.MARKER_ALPHAS
                    uimenu(m,'Text',sprintf('%d%%',round(a*100)),'Tag',['aes|MarkerAlpha|' num2str(a)], ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('MarkerAlpha',a));
                end
                uimenu(cm,'Text','Marker Color ...','MenuSelectedFcn',@(~,~) obj.pickMarkerColor_);
                m = uimenu(cm,'Text','Colormap');
                for c = obj.VALID_COLORMAPS
                    uimenu(m,'Text',c{1},'Tag',['aes|ColormapName|' c{1}], ...
                        'MenuSelectedFcn',@(~,~) obj.setAesthetic_('ColormapName',c{1}));
                end
                uimenu(cm,'Text','Log X','Separator','on','Tag','tgl|LogX', ...
                    'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('LogX'));
                uimenu(cm,'Text','Log Y','Tag','tgl|LogY', ...
                    'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('LogY'));
                uimenu(cm,'Text','Grid','Tag','tgl|ShowGrid', ...
                    'MenuSelectedFcn',@(~,~) obj.toggleAesthetic_('ShowGrid'));

                obj.addPopOutMenu_(cm);

                obj.AxesH.ContextMenu = cm;
                obj.refreshMenuChecks_;
            catch ME
                vprintf(3,'gui.ParameterScatter: context menu unavailable: %s',ME.message)
            end
        end

        function setAesthetic_(obj,prop,val)
            % Apply an aesthetics menu choice, persist it, and redraw.
            obj.(prop) = val;
            obj.savePreferences_;
            obj.refreshMenuChecks_;
            obj.redraw_(obj.currentData_);
        end

        function toggleAesthetic_(obj,prop)
            obj.setAesthetic_(prop,~obj.(prop));
        end

        function pickMarkerColor_(obj)
            c = uisetcolor(obj.MarkerColor,'Marker Color');
            if isscalar(c), return; end % user cancelled
            obj.setAesthetic_('MarkerColor',c);
        end

        function refreshMenuChecks_(obj)
            % Sync menu item check marks with the current property values.
            cm = obj.ContextMenuH_;
            if isempty(cm) || ~isvalid(cm), return; end
            items = findall(cm,'Type','uimenu');
            for k = 1:numel(items)
                t = items(k).Tag;
                if startsWith(t,'aes|')
                    p = strsplit(t,'|');
                    cur = obj.(p{2});
                    if isnumeric(cur), cur = num2str(cur); end
                    items(k).Checked = strcmp(cur,p{3});
                elseif startsWith(t,'tgl|')
                    p = strsplit(t,'|');
                    items(k).Checked = logical(obj.(p{2}));
                end
            end
        end

        % ------------------------------------------------------------------
        % Preference persistence

        function loadPreferences_(obj)
            % Apply saved aesthetics immediately; stage parameter selections
            % so each is applied once its parameter is known, rather than
            % validated away against a list that is empty pre-session.
            try
                pname = obj.preferenceName_;
                if ~ispref(obj.PREF_GROUP,pname), return; end
                s = getpref(obj.PREF_GROUP,pname);
                aes = {'Marker','MarkerSize','MarkerColor','MarkerAlpha', ...
                    'ColormapName','LogX','LogY','ShowGrid'};
                for k = 1:numel(aes)
                    if isfield(s,aes{k})
                        obj.(aes{k}) = s.(aes{k});
                    end
                end
                for k = 1:numel(obj.SELECTION_FIELDS)
                    f = obj.SELECTION_FIELDS{k};
                    if isfield(s,f), obj.stageSelection_(f,s.(f)); end
                end
                obj.refreshMenuChecks_;
                vprintf(3,'gui.ParameterScatter: loaded saved preferences "%s"',pname)
            catch ME
                vprintf(2,'gui.ParameterScatter: failed to load preferences: %s',ME.message)
            end
        end

        function applyPendingSelections_(obj,avail)
            % Apply each staged selection as its parameter becomes available.
            % Unmatched ones stay staged: a selection naming a parameter that
            % only shows up once trials begin must not be dropped on the way.
            if isempty(obj.PendingSelections_) || numel(avail) < 2, return; end
            s = obj.PendingSelections_;
            obj.suspend_ = true;
            for k = 1:numel(obj.SELECTION_FIELDS)
                f = obj.SELECTION_FIELDS{k};
                if ~isfield(s,f), continue; end
                valid = avail;
                if strcmp(f,'ColorParameter'), valid = [{obj.NONE_LABEL} avail]; end
                if ismember(s.(f),valid)
                    obj.(f) = s.(f);
                    s = rmfield(s,f);
                end
            end
            obj.suspend_ = false;
            if isempty(fieldnames(s)), s = []; end
            obj.PendingSelections_ = s;
        end

        function stageSelection_(obj,fieldName,value,asDefault)
            % Stage a selection to be applied once its parameter is known.
            % Staged rather than applied directly because a GUI is typically
            % built before the first trial, when the parameter list is still
            % empty and any immediate assignment would be validated away.
            %
            % asDefault=true leaves an already-staged selection alone: a
            % host's constructor arguments are a starting layout, not an
            % override, so they must not clobber the preference restored
            % from the previous session.
            if nargin < 4, asDefault = false; end
            if isempty(value), return; end
            s = obj.PendingSelections_;
            if isempty(s), s = struct; end
            if asDefault && isfield(s,fieldName), return; end
            s.(fieldName) = char(value);
            obj.PendingSelections_ = s;
        end

        function savePreferences_(obj)
            % Persist selections and aesthetics for this GUI.
            try
                s = struct;
                s.XParameter = obj.XParameter;
                s.YParameter = obj.YParameter;
                s.ColorParameter = obj.ColorParameter;
                s.Marker = obj.Marker;
                s.MarkerSize = obj.MarkerSize;
                s.MarkerColor = obj.MarkerColor;
                s.MarkerAlpha = obj.MarkerAlpha;
                s.ColormapName = obj.ColormapName;
                s.LogX = obj.LogX;
                s.LogY = obj.LogY;
                s.ShowGrid = obj.ShowGrid;
                setpref(obj.PREF_GROUP,obj.preferenceName_,s);
            catch ME
                vprintf(2,'gui.ParameterScatter: failed to save preferences: %s',ME.message)
            end
        end

        function n = preferenceName_(obj)
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
    end
end
