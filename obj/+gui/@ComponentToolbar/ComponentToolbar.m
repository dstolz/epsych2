classdef ComponentToolbar < handle
    %COMPONENTTOOLBAR Icon toolbar that opens a GUI's displays in their own windows.
    %   One tool per display component, so an operator can put the history,
    %   the performance summary or the scatter on a second monitor without
    %   hunting for the right right-click menu. A component the GUI does not
    %   display at all gets a tool too, built the first time it is clicked --
    %   which is what lets a paradigm offer a display without spending screen
    %   space, listeners or a polling timer on it up front.
    %
    %   Created only through gui.BehaviorGUI.addComponentToolbar, which
    %   registers it for teardown and feeds it the automatic entries:
    %
    %       function build(obj, fig)
    %           tb = obj.addComponentToolbar(fig);
    %           tb.addLazyComponent('Performance', ...
    %               @(c) gui.SessionPerformance(obj.RUNTIME, c), ...
    %               Icon='sessionperformance');
    %           ... the rest of the layout ...
    %       end
    %
    %   Two kinds of entry, which differ in who owns the window:
    %
    %     automatic - a gui.PopOut component registered by build. Clicking
    %                 calls its popOut method, so the toolbar is another way
    %                 in to the window its right-click menu already offers,
    %                 and the component keeps ownership of it.
    %     lazy      - a factory declared by addLazyComponent. The toolbar
    %                 makes the window, calls the factory into it, and owns
    %                 both; closing deletes the component, and clicking again
    %                 builds a fresh one. Window position persists either way.
    %
    %   Order is declaration order: lazy entries as they are declared, then
    %   the automatic ones after a separator, because those are not known
    %   until build has returned.
    %
    %   Both kinds take part in gui.BehaviorGUI's RestorePopOuts memory: a
    %   lazy window reports itself to the parent GUI as it opens and closes,
    %   and is reopened by name next session -- so a display the GUI never
    %   shows can still be one the operator always has up.
    %
    %   Style='toggle' makes every tool show whether its window is open. A
    %   toggle reads the component rather than its own button state when
    %   clicked, so a window opened from a right-click menu -- which the
    %   toolbar is not told about -- still closes on the first click.
    %
    % Documentation: documentation/gui/gui_ComponentToolbar.md
    % See also gui.BehaviorGUI, gui.PopOut, gui.toolbarIcon

    properties (SetAccess = private)
        ToolbarH                % uitoolbar holding the tools
        ParentGUI               % gui.BehaviorGUI this toolbar belongs to
        Style (1,1) string = "push" % Default tool style, "push" or "toggle"
    end

    properties (Dependent)
        Names (1,:) string      % Entry names, in toolbar order
    end

    properties (Access = private)
        Entries_ struct = gui.ComponentToolbar.emptyEntries_() % one per tool; see blankEntry_
        Exclude_ (1,:) string = string.empty(1,0)
        AutoDiscover_ (1,1) logical = true
        AutoAdded_ (1,1) logical = false % populateAuto_ runs once, after build
    end

    methods

        function obj = ComponentToolbar(parentGUI, fig, options)
            % obj = ComponentToolbar(parentGUI, fig, Style=..., Exclude=..., AutoDiscover=...)
            % Call gui.BehaviorGUI.addComponentToolbar instead: it registers
            % the toolbar for teardown and arranges automatic discovery.
            arguments
                parentGUI (1,1) gui.BehaviorGUI
                fig (1,1) matlab.ui.Figure
                options.Style (1,1) string {mustBeMember(options.Style,["push","toggle"])} = "push"
                options.Exclude (1,:) string = string.empty(1,0)
                options.AutoDiscover (1,1) logical = true
            end

            obj.ParentGUI     = parentGUI;
            obj.Style         = options.Style;
            obj.Exclude_      = options.Exclude;
            obj.AutoDiscover_ = options.AutoDiscover;
            obj.ToolbarH      = uitoolbar(fig, 'Tag', 'ComponentToolbar');
        end

        function tool = addLazyComponent(obj, name, factory, options)
            % tool = addLazyComponent(obj, name, factory, Icon=..., Tooltip=..., WindowSize=..., Style=..., Separator=...)
            % Declare a component that the GUI does not display. Nothing is
            % constructed until the operator first clicks the tool.
            %
            %  name    - what to call it: the tooltip, the window title, and
            %            the key its window position is remembered under.
            %  factory - h = factory(container), where container is a
            %            borderless panel filling a new window. Return the
            %            component, or [] to cancel the window. Components
            %            that place themselves with normalized Units are the
            %            reason this is a panel and not a uigridlayout.
            %  Icon    - a gui.toolbarIcon name. Left out, the generic
            %            two-window glyph is used.
            %
            % Each factory call gets a fresh window, so a component that
            % remembers its own settings by PreferenceTag reopens as it was.
            arguments
                obj
                name (1,1) string {mustBeNonzeroLengthText}
                factory (1,1) function_handle
                options.Icon (1,1) string = "component"
                options.Tooltip (1,1) string = ""
                options.WindowSize (1,2) double {mustBePositive} = [780 560]
                options.Style (1,1) string {mustBeMember(options.Style,["","push","toggle"])} = ""
                options.Separator (1,1) logical = false
            end

            e            = gui.ComponentToolbar.blankEntry_();
            e.name       = obj.uniqueName_(name);
            e.kind       = "lazy";
            e.style      = obj.resolveStyle_(options.Style);
            e.factory    = factory;
            e.iconName   = options.Icon;
            e.windowSize = options.WindowSize;
            e.separator  = options.Separator;
            e.tooltip    = obj.resolveTooltip_(options.Tooltip, e.name);
            e.prefTag    = matlab.lang.makeValidName( ...
                sprintf('%s_%s_Tool', obj.ParentGUI.PreferenceTag, e.name));

            obj.Entries_(end+1) = e;
            tool = obj.makeTool_(numel(obj.Entries_));
        end

        function names = get.Names(obj)
            if isempty(obj.Entries_)
                names = string.empty(1,0);
            else
                names = [obj.Entries_.name];
            end
        end

        function delete(obj)
            % Drop every sync listener, then close the windows this toolbar
            % owns. Listeners go first so closing cannot re-enter through a
            % callback while the toolbar is coming apart. Automatic entries
            % are left alone: their windows belong to the components, which
            % the GUI's own registry has already taken down.
            for i = 1:numel(obj.Entries_)
                e = obj.Entries_(i);
                try
                    delete(e.syncListener)
                catch
                end
                if e.kind == "lazy"
                    gui.ComponentToolbar.teardownWindow_(e.comp, e.fig, e.prefTag);
                end
            end
            obj.Entries_(:) = [];
        end
    end

    methods (Hidden)

        function populateAuto_(obj, comps, labels)
            % populateAuto_(obj, comps, labels)
            % Append a tool for each gui.PopOut component the GUI registered.
            % Called once by gui.BehaviorGUI after build returns, which is the
            % first moment the registry holds everything build made.
            if obj.AutoAdded_, return; end
            obj.AutoAdded_ = true;
            if ~obj.AutoDiscover_, return; end

            first = true;
            for i = 1:numel(comps)
                c   = comps{i};
                lab = labels(i);
                if obj.isExcluded_(c, lab)
                    vprintf(3, 'gui.ComponentToolbar: "%s" excluded', lab)
                    continue
                end

                e           = gui.ComponentToolbar.blankEntry_();
                e.name      = obj.uniqueName_(lab);
                e.kind      = "auto";
                e.style     = obj.Style;
                e.comp      = c;
                e.iconName  = gui.ComponentToolbar.iconNameForClass(class(c));
                e.tooltip   = obj.resolveTooltip_("", e.name);
                e.separator = first;
                first       = false;

                if e.name ~= lab
                    % A lazy entry already claimed the name. Both tools stay:
                    % one raises the embedded component's window, the other
                    % builds a standalone instance, and those are not the same
                    % thing. Use Exclude to drop one.
                    vprintf(2, ['gui.ComponentToolbar: "%s" is already on the ' ...
                        'toolbar; the registered component is listed as "%s"'], lab, e.name)
                end

                obj.Entries_(end+1) = e;
                obj.makeTool_(numel(obj.Entries_));
            end
        end

        function names = openLazyNames_(obj)
            % names = openLazyNames_(obj)
            % Lazy entries whose window is open, in toolbar order. Automatic
            % entries are deliberately left out: their windows belong to the
            % components, and a gui.BehaviorGUI remembering its layout counts
            % those from the components themselves.
            names = string.empty(1,0);
            for i = 1:numel(obj.Entries_)
                e = obj.Entries_(i);
                if e.kind == "lazy" && ~isempty(e.fig) && isvalid(e.fig)
                    names(end+1) = e.name;
                end
            end
        end

        function tf = openLazyByName_(obj, name)
            % tf = openLazyByName_(obj, name)
            % Open the lazy entry called name, or raise its window if it is
            % already up. False means no such lazy entry — a paradigm that
            % renamed or dropped one since a layout was remembered — which is
            % the caller's cue to say so rather than to fail.
            tf = false;
            i = obj.findEntry_(name);
            if i == 0 || obj.Entries_(i).kind ~= "lazy", return; end
            tf = true;

            if ~isempty(obj.Entries_(i).fig) && isvalid(obj.Entries_(i).fig)
                gui.ComponentToolbar.raise_(obj.Entries_(i).fig);
                return
            end
            obj.openLazy_(i);
            obj.syncTool_(i);
        end
    end

    methods (Access = private)

        function tool = makeTool_(obj, i)
            % Build the tool for entry i and store the handle on the entry.
            e  = obj.Entries_(i);
            nm = e.name;
            args = { ...
                'Tag',       matlab.lang.makeValidName(sprintf('ctb_%s', nm)), ...
                'Icon',      gui.ComponentToolbar.resolveIcon_(e.iconName), ...
                'Tooltip',   char(e.tooltip), ...
                'Separator', matlab.lang.OnOffSwitchState(e.separator), ...
                'ClickedCallback', @(~,~) obj.onClicked_(nm)};

            if e.style == "toggle"
                tool = uitoggletool(obj.ToolbarH, args{:});
            else
                tool = uipushtool(obj.ToolbarH, args{:});
            end
            obj.Entries_(i).tool = tool;
        end

        function onClicked_(obj, name)
            % One handler for both kinds and both styles. A toggle decides
            % from whether the window is actually open, not from the state the
            % click just put the button in, so a window opened or closed
            % behind the toolbar's back still flips the right way.
            try
                i = obj.findEntry_(name);
                if i == 0, return; end
                e = obj.Entries_(i);

                if e.kind == "auto"
                    if isempty(e.comp) || ~isvalid(e.comp)
                        vprintf(2, 'gui.ComponentToolbar: "%s" is gone; disabling its tool', name)
                        obj.setToolEnable_(i, false);
                        return
                    end
                    if e.style == "toggle" && e.comp.hasPopOut()
                        e.comp.closePopOut();
                    else
                        e.comp.popOut();
                        obj.attachSync_(i, e.comp.PopOutFigure);
                    end
                else
                    isOpen = ~isempty(e.fig) && isvalid(e.fig);
                    if e.style == "toggle" && isOpen
                        obj.closeLazy_(name);
                    elseif isOpen
                        gui.ComponentToolbar.raise_(e.fig);
                    else
                        obj.openLazy_(i);
                    end
                end
                obj.syncTool_(obj.findEntry_(name));
            catch ME
                vprintf(0,1, ME)
            end
        end

        function openLazy_(obj, i)
            % Make the window, run the factory into it, and take ownership.
            e   = obj.Entries_(i);
            tag = e.prefTag;

            fig = uifigure('Name', obj.windowName_(e.name), 'Tag', tag, 'Visible', 'off');
            fig.Position = gui.BehaviorGUI.getSavedFigurePosition(tag, obj.defaultPosition_(e.windowSize));
            movegui(fig, 'onscreen');

            % This window holds one component, so it gets the same "Keep
            % Window on Top" item a pop-out has -- marked before the factory
            % runs, since the component builds its menu in its constructor.
            gui.PopOut.markStandaloneWindow(fig, tag);

            % Same borderless, window-filling panel a pop-out is built into,
            % so a lazily-made component resizes with its window too.
            container = gui.PopOut.makeContentPanel(fig);

            try
                h = e.factory(container);
            catch ME
                vprintf(0,1, ME)
                delete(fig)
                return
            end

            if isempty(h) || ~isa(h, 'handle') || ~isvalid(h)
                vprintf(2, 'gui.ComponentToolbar: factory for "%s" made nothing', e.name)
                delete(fig)
                return
            end

            obj.Entries_(i).comp = h;
            obj.Entries_(i).fig  = fig;

            nm = e.name;
            fig.CloseRequestFcn = @(~,~) obj.closeLazy_(nm);

            % Backstop for a window deleted without going through its close
            % request -- the component would otherwise outlive its window.
            obj.Entries_(i).syncListener = listener(fig, 'ObjectBeingDestroyed', ...
                @(~,~) obj.closeLazy_(nm));

            fig.Visible = 'on';
            vprintf(2, 'gui.ComponentToolbar: opened "%s"', fig.Name)
            obj.noteParent_();
        end

        function closeLazy_(obj, name)
            % Save the position, delete the component, then the window.
            if ~isvalid(obj), return; end
            i = obj.findEntry_(name);
            if i == 0, return; end

            e = obj.Entries_(i);
            try
                delete(e.syncListener)
            catch
            end
            obj.Entries_(i).syncListener = event.listener.empty;
            obj.Entries_(i).comp = [];
            obj.Entries_(i).fig  = [];

            gui.ComponentToolbar.teardownWindow_(e.comp, e.fig, e.prefTag);
            obj.syncTool_(i);
            obj.noteParent_();
        end

        function noteParent_(obj)
            % Tell the behavior GUI a window it does not own opened or
            % closed, so one that remembers its layout records the change.
            % The toolbar's own destructor does not come through here: it
            % tears the windows down directly, which is what keeps closing
            % the GUI from erasing what was open when it closed.
            try
                g = obj.ParentGUI;
                if ~isempty(g) && isvalid(g)
                    g.notePopOutStateChanged_();
                end
            catch ME
                vprintf(3, 'gui.ComponentToolbar: could not report a window change: %s', ME.message)
            end
        end

        function attachSync_(obj, i, fig)
            % Release the toggle when the component's pop-out window goes,
            % whichever way it goes: close box, closePopOut, or the host
            % component being destroyed all end in that figure's deletion.
            if obj.Entries_(i).style ~= "toggle", return; end
            try
                delete(obj.Entries_(i).syncListener)
            catch
            end
            obj.Entries_(i).syncListener = event.listener.empty;
            if isempty(fig) || ~isvalid(fig), return; end

            nm = obj.Entries_(i).name;
            obj.Entries_(i).syncListener = listener(fig, 'ObjectBeingDestroyed', ...
                @(~,~) obj.onAutoClosed_(nm));
        end

        function onAutoClosed_(obj, name)
            if ~isvalid(obj), return; end
            i = obj.findEntry_(name);
            if i == 0, return; end
            try
                delete(obj.Entries_(i).syncListener)
            catch
            end
            obj.Entries_(i).syncListener = event.listener.empty;
            obj.setToolState_(i, false);
        end

        function syncTool_(obj, i)
            % Point a toggle at what is actually open. Push tools carry no
            % state, so there is nothing to reconcile for them.
            if i == 0 || i > numel(obj.Entries_), return; end
            e = obj.Entries_(i);
            if e.style ~= "toggle", return; end
            if e.kind == "auto"
                isOpen = ~isempty(e.comp) && isvalid(e.comp) && e.comp.hasPopOut();
            else
                isOpen = ~isempty(e.fig) && isvalid(e.fig);
            end
            obj.setToolState_(i, isOpen);
        end

        function setToolState_(obj, i, tf)
            t = obj.Entries_(i).tool;
            if isempty(t) || ~isvalid(t), return; end
            t.State = matlab.lang.OnOffSwitchState(tf);
        end

        function setToolEnable_(obj, i, tf)
            t = obj.Entries_(i).tool;
            if isempty(t) || ~isvalid(t), return; end
            t.Enable = matlab.lang.OnOffSwitchState(tf);
        end

        function i = findEntry_(obj, name)
            % Entries are found by name, not index, so a callback bound at
            % creation keeps working however the list is rearranged later.
            i = 0;
            if isempty(obj.Entries_), return; end
            j = find([obj.Entries_.name] == name, 1);
            if ~isempty(j), i = j; end
        end

        function name = uniqueName_(obj, base)
            name = string(base);
            n = 1;
            while obj.findEntry_(name) > 0
                n = n + 1;
                name = sprintf('%s %d', base, n);
            end
        end

        function tf = isExcluded_(obj, comp, label)
            if isempty(obj.Exclude_), tf = false; return; end
            cls   = string(class(comp));
            parts = split(cls, '.');
            tf    = any(strcmpi(obj.Exclude_, cls)) ...
                 || any(strcmpi(obj.Exclude_, parts(end))) ...
                 || any(strcmpi(obj.Exclude_, label));
        end

        function s = resolveStyle_(obj, requested)
            s = requested;
            if s == "", s = obj.Style; end
        end

        function t = resolveTooltip_(~, requested, name)
            t = requested;
            if t == "", t = sprintf('Open %s in a separate window', name); end
        end

        function name = windowName_(obj, entryName)
            base = obj.ParentGUI.h_figure.Name;
            if isempty(base)
                name = char(entryName);
            else
                name = sprintf('%s | %s', base, entryName);
            end
        end

        function pos = defaultPosition_(~, sz)
            scr = get(groot, 'ScreenSize');
            pos = [max(1, round((scr(3)-sz(1))/2)), max(1, round((scr(4)-sz(2))/2)), sz];
        end
    end

    methods (Static)

        function label = entryLabel(cls, registerName)
            % label = gui.ComponentToolbar.entryLabel(cls, registerName)
            % What to call a component on the toolbar: the name it was
            % registered under, else its class name split into words.
            arguments
                cls (1,1) string
                registerName (1,:) char = ''
            end
            if ~isempty(registerName)
                label = string(registerName);
                return
            end
            parts = split(cls, '.');
            nm    = strrep(char(parts(end)), '_', ' ');
            label = string(regexprep(nm, '([a-z0-9])([A-Z])', '$1 $2'));
        end

        function nm = iconNameForClass(cls)
            % nm = gui.ComponentToolbar.iconNameForClass(cls)
            % gui.toolbarIcon name for a component class: the class name
            % without its package, lowercased, underscores removed.
            arguments
                cls (1,1) string
            end
            parts = split(cls, '.');
            nm    = lower(string(strrep(char(parts(end)), '_', '')));
        end
    end

    methods (Static, Access = private)

        function icon = resolveIcon_(name)
            % A component with no glyph of its own gets the generic one, so a
            % new gui.PopOut adopter reaches the toolbar before anyone draws
            % for it. Only the unknown-name error is swallowed.
            try
                icon = gui.toolbarIcon(name);
            catch ME
                if ~strcmp(ME.identifier, 'epsych:gui:UnknownToolbarIcon')
                    rethrow(ME)
                end
                vprintf(3, ['gui.ComponentToolbar: no "%s" glyph in gui.toolbarIcon; ' ...
                    'using the generic one'], name)
                icon = gui.toolbarIcon("component");
            end
        end

        function teardownWindow_(h, fig, tag)
            % Save the window position, delete the component, then the
            % window. CloseRequestFcn is cleared first so deleting the figure
            % cannot re-enter this through the close request.
            try
                if ~isempty(fig) && isvalid(fig)
                    fig.CloseRequestFcn = '';
                    gui.BehaviorGUI.saveFigurePosition(tag, fig.Position);
                end
            catch
            end
            try
                if ~isempty(h) && isa(h, 'handle') && isvalid(h)
                    delete(h)
                end
            catch
            end
            try
                if ~isempty(fig) && isvalid(fig)
                    delete(fig)
                end
            catch
            end
        end

        function raise_(fig)
            try
                figure(fig);
            catch
                fig.Visible = 'on';
            end
        end

        function e = emptyEntries_()
            % Empty entry list that still carries the fields: growing a
            % fieldless struct([]) by indexed assignment is an error, not an
            % append.
            e = gui.ComponentToolbar.blankEntry_();
            e(1) = [];
        end

        function e = blankEntry_()
            % Prototype entry. A 0x0 struct with these fields also serves as
            % the empty initial value of Entries_.
            e = struct( ...
                'name',         "", ...
                'kind',         "auto", ...     % "auto" | "lazy"
                'style',        "push", ...     % "push" | "toggle"
                'tool',         [], ...
                'comp',         [], ...         % the component, once it exists
                'fig',          [], ...         % lazy window; auto windows belong to comp
                'factory',      [], ...
                'iconName',     "component", ...
                'tooltip',      "", ...
                'windowSize',   [780 560], ...
                'separator',    false, ...
                'prefTag',      '', ...
                'syncListener', event.listener.empty);
        end
    end
end
