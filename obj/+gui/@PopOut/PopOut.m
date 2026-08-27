classdef (Abstract) PopOut < handle
    %POPOUT Mixin giving a display component an independent pop-out window.
    %   gui.PopOut adds one right-click menu item -- "Open in Separate
    %   Window" -- and the popOut method behind it, to any component that
    %   can be built into a container. Choosing it constructs a NEW instance
    %   of the same class over the same data source in a window of its own.
    %
    %   The embedded component is never reparented, resized, or otherwise
    %   touched: the two are separate objects with separate graphics,
    %   listeners, and saved preferences (the pop-out's preference key is
    %   the host's with the class name and a '_PopOut' suffix appended), so
    %   re-selecting parameters, resorting, restyling, or closing the
    %   pop-out cannot disturb the GUI it came from. Closing the host GUI
    %   does close the pop-out, so no orphan window is left listening to the
    %   runtime.
    %
    %   Adopting the mixin takes three steps:
    %     1. classdef MyComponent < gui.PopOut
    %     2. implement createPopOut_(container) -- construct and return a
    %        sibling instance parented to container, seeded from this
    %        object's current settings
    %     3. call obj.addPopOutMenu_(cm) where the context menu is built,
    %        and override popOutHostContainer_ so the pop-out inherits this
    %        GUI's preference scoping
    %
    %   Popping out a pop-out is allowed and yields a third independent
    %   window, which is how a second view of the same data is obtained.
    %
    %   Properties (read-only):
    %     PopOutComponent - the sibling instance while its window is open
    %     PopOutFigure    - the window hosting it
    %
    %   In its own window a component also offers "Keep Window on Top",
    %   which pins that window above everything else (WindowStyle
    %   'alwaysontop') so a plot stays readable while the operator works in
    %   another application. The item appears ONLY in a window holding a
    %   single component -- a pop-out, or one gui.components.ComponentToolbar opened --
    %   never on the embedded copy, whose window belongs to the behavior GUI.
    %   The choice is remembered per window alongside its position, so a
    %   pinned pop-out reopens pinned.
    %
    %   Methods:
    %     popOut      - open the pop-out window, or raise it if already open
    %     closePopOut - close it (the host component is unaffected)
    %     hasPopOut   - true while a pop-out window is open
    %
    %   Events:
    %     PopOutStateChanged - the window opened or closed. It is what lets a
    %       gui.BehaviorGUI with RestorePopOuts remember which displays were
    %       open without polling for them. Raising an already-open window is
    %       not a change and does not notify, and neither does the teardown
    %       that follows the host component's own destruction.
    %
    %   Static, for windows built outside this mixin:
    %     markStandaloneWindow(fig, prefTag) - declare a one-component window
    %     isAlwaysOnTop(fig) / setAlwaysOnTop(fig, tf)
    %
    %   Protected interface for adopting classes:
    %     createPopOut_(container)  - REQUIRED; return a sibling instance
    %     popOutHostContainer_()    - container this component was built into
    %     addPopOutMenu_(cm)        - append the menu item to a uicontextmenu
    %                                 (and the always-on-top item, in a
    %                                 window the component has to itself)
    %     popOutPreferenceTag_()    - preference key given to the sibling
    %     PopOutSize                - default window size, [width height]
    %     PopOutLabel               - window title; defaults to the class name
    %
    % Documentation: documentation/gui/gui_PopOut.md
    % See also gui.BehaviorGUI, gui.components.ParameterScatter, gui.components.BufferPlot, gui.components.History,
    % gui.components.SessionPerformance, gui.components.NextTrial, gui.components.Parameter_Monitor

    properties (SetAccess = private, Transient)
        PopOutComponent = []    % Sibling instance while its window is open, else []
        PopOutFigure = []       % Window hosting the sibling, else []
    end

    properties (Access = protected)
        PopOutSize (1,2) double {mustBePositive} = [780 560] % Default window [width height]
        PopOutLabel (1,:) char = ''  % Window title; empty derives one from the class name
    end

    properties (Access = private)
        PopOutDestroyListener_ = event.listener.empty
    end

    events
        PopOutStateChanged % The pop-out window opened or closed
    end

    properties (Constant, Hidden)
        POPOUT_MENU_TAG = 'gui_PopOut_menu' % Tag on the menu item this mixin creates
        ALWAYSONTOP_MENU_TAG = 'gui_PopOut_alwaysOnTop_menu' % Tag on the always-on-top item
        STANDALONE_APPDATA = 'gui_PopOut_StandaloneTag' % Appdata marking a one-component window
    end

    methods (Abstract, Access = protected)
        % h = createPopOut_(obj, container)
        % Construct a sibling instance of this component parented to
        % container and return it. Seed it from this object's current
        % settings so the window opens showing what the host shows, and
        % give it PreferenceTag = obj.popOutPreferenceTag_() so its later
        % changes are remembered separately. Return [] to cancel.
        h = createPopOut_(obj, container)
    end

    methods

        function h = popOut(obj)
            % h = popOut(obj)
            % Open this component in a window of its own, or raise the
            % window if it is already open. Returns the pop-out instance, or
            % [] if one could not be created.
            if obj.hasPopOut()
                obj.raisePopOut_();
                h = obj.PopOutComponent;
                return
            end
            obj.forgetPopOut_();

            tag = obj.popOutPreferenceTag_();
            fig = uifigure('Name', obj.popOutWindowName_(), 'Tag', tag, 'Visible', 'off');
            fig.Position = gui.BehaviorGUI.getSavedFigurePosition(tag, obj.defaultPopOutPosition_());

            % Marked -- and put back on top if that is how it was last left --
            % BEFORE the component is built, so the context menu it builds in
            % its constructor can find the window and show the right tick.
            gui.PopOut.markStandaloneWindow(fig, tag);

            container = gui.PopOut.makeContentPanel(fig);

            try
                h = obj.createPopOut_(container);
            catch ME
                vprintf(0,1, ME)
                delete(fig)
                h = [];
                return
            end

            if isempty(h) || ~isvalid(h)
                delete(fig)
                h = [];
                return
            end

            obj.PopOutComponent = h;
            obj.PopOutFigure    = fig;

            fig.CloseRequestFcn = @(~,~) obj.closePopOut();

            % The host owns the window. Its own destruction (the BehaviorGUI
            % closing, say) must take the pop-out with it, and the handles
            % are captured rather than read back off a half-deleted object.
            obj.PopOutDestroyListener_ = listener(obj, 'ObjectBeingDestroyed', ...
                @(~,~) gui.PopOut.teardownPopOut_(h, fig, tag));

            fig.Visible = 'on';
            vprintf(2, '%s: opened pop-out window "%s"', class(obj), fig.Name)
            obj.notifyPopOutState_();
        end

        function closePopOut(obj)
            % closePopOut(obj)
            % Close the pop-out window and delete its component. The host
            % component and its window are unaffected.
            if isempty(obj.PopOutComponent) && isempty(obj.PopOutFigure), return; end
            gui.PopOut.teardownPopOut_(obj.PopOutComponent, obj.PopOutFigure, ...
                obj.popOutPreferenceTag_());
            obj.forgetPopOut_();
            obj.notifyPopOutState_();
        end

        function tf = hasPopOut(obj)
            % tf = hasPopOut(obj)
            % True while this component's pop-out window is open.
            tf = ~isempty(obj.PopOutComponent) && isvalid(obj.PopOutComponent) ...
                && ~isempty(obj.PopOutFigure) && isvalid(obj.PopOutFigure);
        end
    end

    methods (Access = protected)

        function m = addPopOutMenu_(obj, cm, options)
            % m = addPopOutMenu_(obj, cm, Text=..., Separator=...)
            % Append the pop-out item to a uicontextmenu. Returns [] when
            % the menu could not be created, which is never fatal: the
            % popOut method stays available to the hosting GUI either way.
            arguments
                obj
                cm
                options.Text (1,:) char = 'Open in Separate Window'
                options.Separator (1,1) logical = true
            end

            m = [];
            if isempty(cm) || ~isvalid(cm), return; end
            try
                m = uimenu(cm, 'Text', options.Text, 'Tag', obj.POPOUT_MENU_TAG, ...
                    'Separator', matlab.lang.OnOffSwitchState(options.Separator), ...
                    'MenuSelectedFcn', @(~,~) obj.popOut());
            catch ME
                vprintf(3, '%s: pop-out menu unavailable: %s', class(obj), ME.message)
            end

            % An adopter gets the always-on-top item for free: it appears only
            % in a window this component has to itself, so no adopter has to
            % know whether it is the embedded copy or the popped-out one.
            obj.addAlwaysOnTopMenu_(cm);
        end

        function m = addAlwaysOnTopMenu_(obj, cm, options)
            % m = addAlwaysOnTopMenu_(obj, cm, Text=..., Separator=...)
            % Append the "Keep Window on Top" toggle to a uicontextmenu, but
            % ONLY when this component sits in a window of its own -- a
            % pop-out, or a window gui.components.ComponentToolbar opened for it. In an
            % embedded component the item is omitted rather than disabled:
            % pinning the behavior GUI itself is not what the operator asked
            % for, and there is no per-component window to pin. Returns [].
            arguments
                obj
                cm
                options.Text (1,:) char = 'Keep Window on Top'
                options.Separator (1,1) logical = false
            end

            m = [];
            if isempty(cm) || ~isvalid(cm), return; end
            try
                fig = gui.PopOut.standaloneWindowOf_(cm);
                if isempty(fig), return; end
                m = uimenu(cm, 'Text', options.Text, 'Tag', obj.ALWAYSONTOP_MENU_TAG, ...
                    'Separator', matlab.lang.OnOffSwitchState(options.Separator), ...
                    'Checked', matlab.lang.OnOffSwitchState(gui.PopOut.isAlwaysOnTop(fig)), ...
                    'MenuSelectedFcn', @(src,~) gui.PopOut.toggleAlwaysOnTop_(src, fig));
            catch ME
                vprintf(3, '%s: always-on-top menu unavailable: %s', class(obj), ME.message)
            end
        end

        function c = popOutHostContainer_(~)
            % c = popOutHostContainer_(obj)
            % Container this component was built into. Override it: the
            % pop-out's preference key and window title are scoped by the
            % hosting figure, exactly as the component's own preferences are.
            c = [];
        end

        function tag = popOutPreferenceTag_(obj)
            % tag = popOutPreferenceTag_(obj)
            % Preference key (and figure Tag) for this component's pop-out:
            % the hosting figure's key, the component class, and a _PopOut
            % suffix. Two components of different classes in one GUI
            % therefore get distinct keys, and the pop-out never writes over
            % the preferences of the component it came from.
            label = gui.PopOut.classLabel_(obj);
            base  = char(obj.popOutBaseTag_());
            if isempty(base)
                base = label;
            elseif ~contains(base, label)
                base = [base '_' label];
            end
            tag = matlab.lang.makeValidName([base '_PopOut']);
        end

        function tag = popOutBaseTag_(obj)
            % tag = popOutBaseTag_(obj)
            % Hosting figure's Tag (else Name), matching how every component
            % in this toolbox scopes its saved preferences.
            tag = '';
            try
                f = ancestor(obj.popOutHostContainer_(), 'figure');
                if ~isempty(f) && isvalid(f)
                    if ~isempty(f.Tag)
                        tag = f.Tag;
                    elseif ~isempty(f.Name)
                        tag = f.Name;
                    end
                end
            catch
            end
        end

        function name = popOutWindowName_(obj)
            % name = popOutWindowName_(obj)
            % Window title: the component's label, qualified by the hosting
            % figure's name so several behavior GUIs' pop-outs stay tellable apart.
            name = obj.PopOutLabel;
            if isempty(name)
                name = regexprep(gui.PopOut.classLabel_(obj), '([a-z0-9])([A-Z])', '$1 $2');
                name = strrep(name, '_', ' ');
            end
            try
                f = ancestor(obj.popOutHostContainer_(), 'figure');
                if ~isempty(f) && isvalid(f) && ~isempty(f.Name)
                    name = sprintf('%s | %s', f.Name, name);
                end
            catch
            end
        end

        function pos = defaultPopOutPosition_(obj)
            % pos = defaultPopOutPosition_(obj)
            % Centered [x y w h] used the first time this pop-out is opened.
            sz = obj.PopOutSize;
            try
                s = get(groot, 'ScreenSize');
                pos = [max(1, round((s(3)-sz(1))/2)), max(1, round((s(4)-sz(2))/2)), sz];
            catch
                pos = [120 120 sz];
            end
        end
    end

    methods (Access = private)

        function raisePopOut_(obj)
            try
                figure(obj.PopOutFigure);
            catch
                obj.PopOutFigure.Visible = 'on';
            end
        end

        function notifyPopOutState_(obj)
            % Announce that the window opened or closed. A listener that
            % throws is logged rather than allowed back out into the click
            % that opened the window: the pop-out itself is already open.
            try
                obj.notify('PopOutStateChanged');
            catch ME
                vprintf(2, '%s: PopOutStateChanged listener failed: %s', ...
                    class(obj), ME.message)
            end
        end

        function forgetPopOut_(obj)
            % Drop the handles and the destruction listener without touching
            % the window, which teardownPopOut_ has already dealt with.
            try
                delete(obj.PopOutDestroyListener_);
            catch
            end
            obj.PopOutDestroyListener_ = event.listener.empty;
            obj.PopOutComponent = [];
            obj.PopOutFigure    = [];
        end
    end

    methods (Static, Hidden)

        function p = makeContentPanel(fig)
            % p = gui.PopOut.makeContentPanel(fig)
            % Borderless panel filling fig, for a window built to hold ONE
            % component. gui.components.ComponentToolbar builds the windows it owns the
            % same way.
            %
            % A panel rather than a bare uigridlayout, because a component
            % that places its own children with normalized Units warns inside
            % a layout cell -- but the panel is PARENTED to a 1x1 layout
            % rather than given Position [0 0 1 1] in normalized units. A
            % uipanel positioned that way in a uifigure keeps the pixel size
            % it was created at: shrink the window and the panel stays as
            % tall as the window used to be, anchored at the bottom, so the
            % component inside it is laid out for a window that is no longer
            % there -- rows clipped off the top with empty space below.
            g = uigridlayout(fig, [1 1], 'Padding', [0 0 0 0], ...
                'RowHeight', {'1x'}, 'ColumnWidth', {'1x'});
            p = uipanel(g, 'BorderType', 'none');
        end

        function markStandaloneWindow(fig, prefTag)
            % markStandaloneWindow(fig, prefTag)
            % Declare fig a window built to hold ONE component, so that
            % component's context menu offers "Keep Window on Top", and
            % restore the pinned state the operator last left it in. Call it
            % after the figure is made and BEFORE the component is built into
            % it. gui.components.ComponentToolbar calls this for the windows it owns.
            if isempty(fig) || ~isvalid(fig), return; end
            try
                setappdata(fig, gui.PopOut.STANDALONE_APPDATA, char(prefTag));
            catch
                return
            end
            gui.PopOut.setAlwaysOnTop(fig, gui.PopOut.savedAlwaysOnTop_(prefTag));
        end

        function tf = isAlwaysOnTop(fig)
            % tf = gui.PopOut.isAlwaysOnTop(fig)
            % True while fig is pinned above other windows.
            tf = false;
            try
                tf = strcmpi(char(fig.WindowStyle), 'alwaysontop');
            catch
            end
        end

        function setAlwaysOnTop(fig, tf)
            % gui.PopOut.setAlwaysOnTop(fig, tf)
            % Pin or unpin fig, and remember the choice under the preference
            % tag the window was marked with. Failure is never fatal: a
            % release or platform that will not honour WindowStyle leaves the
            % window where it is rather than taking the click down with it.
            if isempty(fig) || ~isvalid(fig), return; end
            tf = logical(tf);
            try
                if tf
                    fig.WindowStyle = 'alwaysontop';
                else
                    fig.WindowStyle = 'normal';
                end
            catch ME
                vprintf(1, 'gui.PopOut: cannot pin "%s" on top: %s', fig.Name, ME.message)
                return
            end
            gui.PopOut.saveAlwaysOnTop_(getappdata(fig, gui.PopOut.STANDALONE_APPDATA), tf);
        end
    end

    methods (Static, Access = private)

        function fig = standaloneWindowOf_(h)
            % Figure h lives in, but only if it was marked as belonging to
            % one component; [] otherwise.
            fig = [];
            try
                f = ancestor(h, 'figure');
                if ~isempty(f) && isvalid(f) && isappdata(f, gui.PopOut.STANDALONE_APPDATA)
                    fig = f;
                end
            catch
            end
        end

        function toggleAlwaysOnTop_(src, fig)
            % Flip from the WINDOW's current state, not the menu's tick: the
            % tick is only refreshed when this item is used, so reading the
            % figure is what keeps the first click after an outside change
            % doing the obvious thing.
            if isempty(fig) || ~isvalid(fig), return; end
            gui.PopOut.setAlwaysOnTop(fig, ~gui.PopOut.isAlwaysOnTop(fig));
            try
                src.Checked = matlab.lang.OnOffSwitchState(gui.PopOut.isAlwaysOnTop(fig));
            catch
            end
        end

        function tf = savedAlwaysOnTop_(prefTag)
            tf = false;
            try
                if isempty(prefTag), return; end
                tf = logical(getpref(char(prefTag), 'AlwaysOnTop', false));
            catch
                tf = false;
            end
        end

        function saveAlwaysOnTop_(prefTag, tf)
            try
                if isempty(prefTag), return; end
                setpref(char(prefTag), 'AlwaysOnTop', logical(tf));
            catch
            end
        end

        function teardownPopOut_(h, fig, tag)
            % Save the window position, delete the component, then the
            % window. CloseRequestFcn is cleared first so deleting the
            % figure cannot re-enter this through closePopOut.
            try
                if ~isempty(fig) && isvalid(fig)
                    fig.CloseRequestFcn = '';
                    gui.BehaviorGUI.saveFigurePosition(tag, fig.Position);
                end
            catch
            end
            try
                if ~isempty(h) && isvalid(h)
                    delete(h);
                end
            catch
            end
            try
                if ~isempty(fig) && isvalid(fig)
                    delete(fig);
                end
            catch
            end
        end

        function label = classLabel_(obj)
            % Class name without its package, e.g. 'ParameterScatter'.
            parts = strsplit(class(obj), '.');
            label = parts{end};
        end
    end
end
