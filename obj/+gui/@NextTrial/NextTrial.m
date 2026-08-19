classdef NextTrial < gui.PopOut
    % obj = gui.NextTrial(source, container)
    % Generic "upcoming trial" display for custom behavior GUIs.
    %
    % Shows the parameters of the trial about to be presented, refreshed
    % from every NewTrial event. The right-click menu also offers Open in
    % Separate Window (see gui.PopOut), which repeats the display in a
    % window of its own -- useful for a large, across-the-room readout while
    % the embedded table keeps its compact field selection.
    %
    % Which fields are shown can be set
    % programmatically (constructor Fields=, or setFields) and/or by the
    % operator, via a right-click "Show Field" menu. The selection persists
    % across sessions with getpref/setpref, keyed to the hosting figure (or
    % an explicit PreferenceTag), the same pattern gui.ParameterScatter and
    % gui.Parameter_Monitor use.
    %
    % Fields are named by validName, matching
    % epsych.TrialsData.Data.writeParamIdx (the NewTrial event payload).
    % Trial 1 is dispatched before the behavior GUI is launched, so its
    % NewTrial event predates the listener; the constructor seeds the
    % display from RUNTIME.TRIALS rather than leaving the first trial of
    % the session unshown. With no runtime trials yet (a GUI built before
    % a run) only the constructor's Fields (or a saved selection) are
    % known and the table stays blank until the first event supplies the
    % compiled trial table and the field names it declares. When no
    % Fields are given and nothing was saved, every declared field is
    % shown once the first trial is compiled.
    %
    % Values render with str/num2str by default. A per-field Formatters
    % map (validName -> function_handle(rawValue) -> char/string) overrides
    % that, e.g. to decode a numeric trial-type code into a label.
    %
    % Font size is settable the same two ways -- obj.FontSize = 22, or the
    % right-click "Font Size" menu -- and is saved with the field selection,
    % so an operator who sized the table to be read from across the room
    % gets it back next session.
    %
    % Properties:
    %   SelectedFields  - validNames currently displayed (Dependent)
    %   AvailableFields - validNames declared by the most recent NewTrial (Dependent)
    %   FontSize        - Table font size in points (Dependent)
    %   ContextMenu     - the right-click menu; host GUIs may append items
    %
    % Methods:
    %   NextTrial   - Construct the display and attach the NewTrial listener
    %   setFields   - Programmatically choose which fields are displayed
    %   setFontSize - Programmatically set the table font size
    %   delete      - Release the listener and context menu
    %
    % Examples:
    %   % Minimal: show every declared field once trials are compiled
    %   obj.NextTrialPanel = gui.NextTrial(RUNTIME, panelNextTrial);
    %
    %   % Programmatic default + a custom label for TrialType
    %   fmt = containers.Map({'TrialType'}, {@(v) myTrialTypeLabel(v)});
    %   obj.NextTrialPanel = gui.NextTrial(RUNTIME, panelNextTrial, ...
    %       Fields=["Depth","TrialType"], Formatters=fmt, FontSize=20);
    %
    % See also: documentation/gui/gui_NextTrial.md, gui.BehaviorGUI.addNextTrial,
    % gui.Parameter_Monitor, gui.ParameterScatter, epsych.TrialsData

    properties (Dependent)
        SelectedFields  % validNames currently displayed, in declared order
        AvailableFields % validNames declared by the most recent NewTrial event
        FontSize        % Table font size in points
    end

    properties
        % FontPresets - Sizes offered as one-click entries on the Font Size menu
        FontPresets (1,:) double {mustBePositive} = [10 12 14 16 20 24 28 36]
    end

    properties (SetAccess = private)
        Parent                              % Hosting container supplied at construction
        TableH                              % uitable displaying the upcoming trial
        ContextMenu = []                    % Right-click "Show Field" menu
        hl_NewTrial = event.listener.empty  % Listener for NewTrial events
    end

    properties (Access = private)
        SelectedFields_ (1,:) string = string.empty(1,0)
        AvailableFields_ (1,:) string = string.empty(1,0)
        AvailableLabels_ (1,:) string = string.empty(1,0)
        AvailableUnits_ (1,:) string = string.empty(1,0)
        DefaultFields_ (1,:) string = string.empty(1,0)
        HasExplicitSelection_ (1,1) logical = false
        LastEventData_ = []
        Formatters_
        Source_ = []                    % Construction source, reused to build a pop-out
        FontSize_ (1,1) double = 16
        PreferenceTag_ (1,:) char = ''
        ShowMenuH_ = []
        FontMenuH_ = []
        selfDeleteListener_ = event.listener.empty
    end

    properties (Constant, Access = private)
        PREF_GROUP = 'epsych2_gui_NextTrial'
    end

    methods
        function obj = NextTrial(source, container, options)
            % obj = gui.NextTrial(source, container, ...)
            %  source    - epsych.Runtime (listens on RUNTIME.EVENTS) or an
            %              epsych.EventHub directly.
            %  container - Figure, panel, tab, or layout host for the table.
            %  Fields         - Programmatic default field names (validName);
            %                   used only when nothing was saved for this
            %                   PreferenceTag. A selection restored from a
            %                   previous session takes precedence.
            %  Formatters     - containers.Map, validName -> function_handle
            %                   (rawValue) -> char/string, for fields whose
            %                   raw trial-table value needs decoding.
            %  FontSize       - Table font size. Default 16. Like the field
            %                   selection, a size saved for this
            %                   PreferenceTag takes precedence.
            %  PreferenceTag  - Optional key for saved preferences (defaults
            %                   to the hosting figure Tag/Name).
            arguments
                source
                container (1,1)
                options.Fields (1,:) string = string.empty(1,0)
                options.Formatters = containers.Map('KeyType','char','ValueType','any')
                options.FontSize (1,1) double = 16
                options.PreferenceTag (1,:) char = ''
            end

            if ~isa(options.Formatters,'containers.Map')
                error('gui:NextTrial:InvalidFormatters', ...
                    'Formatters must be a containers.Map of validName -> function_handle.')
            end

            obj.Parent        = container;
            obj.Source_        = source; % kept so a pop-out can follow the same events
            obj.Formatters_    = options.Formatters;
            obj.FontSize_      = options.FontSize;
            obj.PreferenceTag_ = options.PreferenceTag;
            obj.DefaultFields_ = reshape(options.Fields,1,[]);

            if ~isempty(obj.DefaultFields_)
                obj.SelectedFields_      = obj.DefaultFields_;
                obj.HasExplicitSelection_ = true;
            end

            obj.buildUI_(container, options.FontSize);
            obj.loadPreferences_();
            obj.attachListener_(source);
            obj.seedFromRuntime_(source);
        end

        function delete(obj)
            % Release the NewTrial listener and context menu. The table
            % graphics are left for the hosting figure to tear down.
            try
                if ~isempty(obj.hl_NewTrial) && isvalid(obj.hl_NewTrial)
                    obj.hl_NewTrial.Enabled = false;
                    delete(obj.hl_NewTrial);
                end
            catch
            end
            try
                delete(obj.selfDeleteListener_);
            catch
            end
            try
                if ~isempty(obj.ContextMenu) && isvalid(obj.ContextMenu)
                    delete(obj.ContextMenu);
                end
            catch
            end
        end

        function fields = get.SelectedFields(obj)
            fields = obj.SelectedFields_;
        end

        function fields = get.AvailableFields(obj)
            fields = obj.AvailableFields_;
        end

        function sz = get.FontSize(obj)
            sz = obj.FontSize_;
        end

        function set.FontSize(obj, points)
            obj.setFontSize(points);
        end

        function setFontSize(obj, points)
            % setFontSize(obj, points)
            % Set the table font size, in points. Sizes outside 6-72 are
            % clamped rather than refused, so a scripted value cannot leave
            % the display unreadable. Persists like a menu selection.
            arguments
                obj
                points (1,1) double {mustBePositive, mustBeFinite}
            end
            points = min(max(round(points), 6), 72);
            obj.FontSize_ = points;
            obj.applyFontSize_();
            obj.savePreferences_();
        end

        function setFields(obj, fields)
            % setFields(obj, fields)
            % Programmatically choose which fields are displayed. Fields
            % not yet declared by a compiled trial table are kept and
            % simply render nothing until they appear. Persists like a
            % menu selection.
            arguments
                obj
                fields (1,:) string
            end
            obj.setSelection_(fields);
        end
    end

    methods (Access = protected)

        function c = popOutHostContainer_(obj)
            % Container this display was built into (gui.PopOut).
            c = obj.Parent;
        end

        function h = createPopOut_(obj, container)
            % A second upcoming-trial display on the same event source, in
            % its own window and with its own field selection.
            h = gui.NextTrial(obj.Source_, container, ...
                Fields        = obj.SelectedFields_, ...
                Formatters    = obj.Formatters_, ...
                FontSize      = obj.FontSize_, ...
                PreferenceTag = obj.popOutPreferenceTag_());

            % Replay the most recent trial so the window opens populated
            % instead of blank until the next NewTrial arrives.
            if ~isempty(obj.LastEventData_)
                h.onNewTrial_([], struct('Data', obj.LastEventData_));
            end
        end
    end

    methods (Access = private)

        function buildUI_(obj, parent, fontSize)
            t = uitable(parent, ...
                'ColumnName', {'Parameter','Value'}, ...
                'RowName', [], ...
                'ColumnEditable', [false false]);
            if ~isa(parent,'matlab.ui.container.GridLayout')
                % A uigridlayout cell manages its child's position; setting
                % Units/Position there is a no-op that also warns.
                t.Units = 'normalized';
                t.Position = [0 0 1 1];
            end
            try
                t.FontSize = fontSize;
            catch
            end
            t.Data = cell(0,2);
            obj.TableH = t;

            obj.selfDeleteListener_ = listener(t, 'ObjectBeingDestroyed', @(~,~) delete(obj));

            obj.createContextMenu_();
        end

        function attachListener_(obj, source)
            if isa(source,'epsych.EventHub')
                H = source;
            elseif isobject(source) && isprop(source,'EVENTS') && isa(source.EVENTS,'epsych.EventHub')
                H = source.EVENTS;
            else
                error('gui:NextTrial:InvalidSource', ...
                    'source must be an epsych.Runtime or an epsych.EventHub.')
            end
            obj.hl_NewTrial = listener(H, 'NewTrial', @(src,evt) obj.onNewTrial_(src,evt));
        end

        function seedFromRuntime_(obj, source)
            % Trial 1 is dispatched by ep_TimerFcn_Start, through
            % epsych.Runtime.set.TRIALS, BEFORE RunExpt fevals
            % FUNCS.BehaviorGUI -- so this listener is attached one trial
            % too late and the table would stay blank until trial 2.
            % Replay the pending trial out of the runtime state instead.
            % (gui.ParameterScatter backfills DATA the same way.)
            try
                T = source.TRIALS;
                if isempty(T), return; end
                obj.onNewTrial_([], struct('Data', T(1)));
            catch
                % Not a runtime, or no trials compiled yet; the first
                % NewTrial event populates the table.
            end
        end

        function onNewTrial_(obj, ~, event)
            if ~isvalid(obj) || isempty(obj.TableH) || ~isvalid(obj.TableH), return; end
            try
                D = event.Data;
                obj.LastEventData_ = D;

                names  = reshape(string(D.writeparams),1,[]);
                labels = names;
                units  = strings(1,numel(names));

                if isfield(D,'parameters') && numel(D.parameters) == numel(names)
                    raw = strings(1,numel(names));
                    for i = 1:numel(names)
                        raw(i)   = string(D.parameters(i).Name);
                        units(i) = string(D.parameters(i).Unit);
                    end
                    labels = raw;
                    for i = 1:numel(names)
                        if strlength(raw(i)) > 0 && sum(raw == raw(i)) == 1
                            continue
                        end
                        % ambiguous or empty display name: fall back to the
                        % validName, which is always unique
                        if strlength(raw(i)) == 0 || sum(raw == raw(i)) > 1
                            labels(i) = names(i);
                        end
                    end
                end

                obj.AvailableFields_ = names;
                obj.AvailableLabels_ = labels;
                obj.AvailableUnits_  = units;

                if ~obj.HasExplicitSelection_
                    obj.SelectedFields_       = obj.AvailableFields_;
                    obj.HasExplicitSelection_ = true;
                end

                obj.refresh_();
            catch ME
                vprintf(0,1, ME)
            end
        end

        function refresh_(obj)
            if isempty(obj.TableH) || ~isvalid(obj.TableH), return; end

            D = obj.LastEventData_;
            if isempty(D)
                obj.TableH.Data = cell(0,2);
                return
            end

            avail = obj.AvailableFields_;
            keep  = find(ismember(avail, obj.SelectedFields_));
            n     = numel(keep);
            data  = cell(n,2);

            for k = 1:n
                i    = keep(k);
                name = char(avail(i));

                label = obj.AvailableLabels_(i);
                if strlength(obj.AvailableUnits_(i)) > 0
                    label = sprintf('%s (%s)', label, obj.AvailableUnits_(i));
                end
                data{k,1} = char(label);

                col = i;
                if isfield(D,'writeParamIdx') && isfield(D.writeParamIdx, name)
                    col = D.writeParamIdx.(name);
                end
                raw = D.trials{D.NextTrialID, col};
                data{k,2} = obj.formatValue_(name, raw);
            end

            obj.TableH.Data = data;
        end

        function s = formatValue_(obj, name, raw)
            if isKey(obj.Formatters_, name)
                try
                    fcn = obj.Formatters_(name);
                    s = char(fcn(raw));
                    return
                catch ME
                    vprintf(2,'gui.NextTrial: formatter for "%s" failed: %s', name, ME.message)
                end
            end
            s = gui.NextTrial.defaultFormat_(raw);
        end

        function createContextMenu_(obj)
            f = ancestor(obj.Parent,'figure');
            if isempty(f) || ~isvalid(f), return; end

            try
                cm = uicontextmenu(f);
                obj.ContextMenu = cm;
                obj.ShowMenuH_  = uimenu(cm,'Text','Show Field');
                obj.FontMenuH_  = uimenu(cm,'Text','Font Size');
                uimenu(cm,'Text','Show All','Separator','on', ...
                    'MenuSelectedFcn',@(~,~) obj.showAll_());
                uimenu(cm,'Text','Reset to Default', ...
                    'MenuSelectedFcn',@(~,~) obj.resetToDefault_());
                obj.addPopOutMenu_(cm);

                try
                    cm.ContextMenuOpeningFcn = @(~,~) obj.refreshMenus_();
                catch
                    cm.Callback = @(~,~) obj.refreshMenus_();
                end
            catch ME
                vprintf(3,'gui.NextTrial: context menu unavailable: %s', ME.message)
                obj.ContextMenu = [];
                return
            end

            try
                obj.TableH.ContextMenu = cm;
            catch
                try
                    obj.TableH.UIContextMenu = cm; % legacy figure
                catch ME
                    vprintf(3,'gui.NextTrial: cannot attach context menu: %s', ME.message)
                end
            end
        end

        function refreshMenus_(obj)
            obj.refreshShowMenu_();
            obj.refreshFontMenu_();
        end

        function refreshFontMenu_(obj)
            % Presets plus a prompt, rebuilt on open so the check mark and
            % the custom entry follow a size set programmatically.
            m = obj.FontMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            sz = obj.FontSize_;
            for k = 1:numel(obj.FontPresets)
                n = obj.FontPresets(k);
                item = uimenu(m,'Text',sprintf('%g pt',n), ...
                    'MenuSelectedFcn',@(~,~) obj.setFontSize(n));
                item.Checked = sz == n;
            end

            uimenu(m,'Text','Larger','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.setFontSize(sz + 2));
            uimenu(m,'Text','Smaller', ...
                'MenuSelectedFcn',@(~,~) obj.setFontSize(sz - 2));

            item = uimenu(m,'Text','Custom...','Separator','on', ...
                'MenuSelectedFcn',@(~,~) obj.promptFontSize_());
            item.Checked = ~ismember(sz, obj.FontPresets);
        end

        function promptFontSize_(obj)
            % inputdlg opens its own dialog, so it works from a uifigure; a
            % cancelled or unparseable entry is ignored.
            try
                a = inputdlg({'Font size (points):'}, 'Font Size', [1 30], ...
                    {num2str(obj.FontSize_)});
            catch ME
                vprintf(0,1,'gui.NextTrial: cannot prompt for a font size: %s', ME.message)
                return
            end
            if isempty(a), return; end

            n = str2double(strtrim(a{1}));
            if ~isfinite(n) || n <= 0
                vprintf(1,'gui.NextTrial: "%s" is not a font size', strtrim(a{1}))
                return
            end
            obj.setFontSize(n);
        end

        function applyFontSize_(obj)
            if isempty(obj.TableH) || ~isvalid(obj.TableH), return; end
            try
                obj.TableH.FontSize = obj.FontSize_;
            catch ME
                vprintf(3,'gui.NextTrial: unable to set font size: %s', ME.message)
            end
        end

        function refreshShowMenu_(obj)
            % One checkable entry per declared field, plus Show All /
            % Reset to Default. Rebuilt on every open since the declared
            % field set can change (e.g. after a protocol recompile).
            m = obj.ShowMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            avail = obj.AvailableFields_;
            labels = obj.AvailableLabels_;
            sel = obj.SelectedFields_;
            for i = 1:numel(avail)
                item = uimenu(m,'Text',char(labels(i)), ...
                    'MenuSelectedFcn',@(~,~) obj.toggleField_(avail(i)));
                item.Checked = ismember(avail(i), sel);
            end

            if isempty(avail)
                uimenu(m,'Text','(no trial data yet)','Enable','off');
            end
        end

        function toggleField_(obj, name)
            sel = obj.SelectedFields_;
            if ismember(name, sel)
                sel(sel == name) = [];
            else
                sel(end+1) = name;
            end
            obj.setSelection_(sel);
        end

        function showAll_(obj)
            obj.setSelection_(obj.AvailableFields_);
        end

        function resetToDefault_(obj)
            d = obj.DefaultFields_;
            if isempty(d), d = obj.AvailableFields_; end
            obj.setSelection_(d);
        end

        function setSelection_(obj, fields)
            fields = unique(reshape(string(fields),1,[]), 'stable');
            obj.SelectedFields_       = fields;
            obj.HasExplicitSelection_ = true;
            obj.refresh_();
            obj.savePreferences_();
        end

        % ------------------------------------------------------------
        % Preference persistence (mirrors gui.ParameterScatter)

        function loadPreferences_(obj)
            try
                pname = obj.preferenceName_();
                if ~ispref(obj.PREF_GROUP, pname), return; end
                s = getpref(obj.PREF_GROUP, pname);
                if isfield(s,'SelectedFields')
                    obj.SelectedFields_       = reshape(string(s.SelectedFields),1,[]);
                    obj.HasExplicitSelection_ = true;
                end
                if isfield(s,'FontSize') && isscalar(s.FontSize) && isfinite(s.FontSize) ...
                        && s.FontSize > 0
                    obj.FontSize_ = min(max(round(s.FontSize), 6), 72);
                    obj.applyFontSize_();
                end
                vprintf(3,'gui.NextTrial: loaded saved preferences "%s"', pname)
            catch ME
                vprintf(2,'gui.NextTrial: failed to load preferences: %s', ME.message)
            end
        end

        function savePreferences_(obj)
            try
                s = struct('SelectedFields', {cellstr(obj.SelectedFields_)}, ...
                    'FontSize', obj.FontSize_);
                setpref(obj.PREF_GROUP, obj.preferenceName_(), s);
            catch ME
                vprintf(2,'gui.NextTrial: failed to save preferences: %s', ME.message)
            end
        end

        function n = preferenceName_(obj)
            % Preference key scoped to the hosting GUI: explicit tag, else
            % the ancestor figure Tag, else its Name, else 'default'.
            n = obj.PreferenceTag_;
            if isempty(n)
                try
                    f = ancestor(obj.Parent,'figure');
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

    methods (Static, Access = private)
        function s = defaultFormat_(raw)
            if (isnumeric(raw) || islogical(raw)) && isscalar(raw)
                s = num2str(raw);
            elseif ischar(raw)
                s = raw;
            elseif isstring(raw) && isscalar(raw)
                s = char(raw);
            else
                try
                    s = char(string(raw));
                catch
                    s = mat2str(raw);
                end
            end
        end
    end
end
