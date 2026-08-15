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
    %   Methods:
    %     popOut      - open the pop-out window, or raise it if already open
    %     closePopOut - close it (the host component is unaffected)
    %     hasPopOut   - true while a pop-out window is open
    %
    %   Protected interface for adopting classes:
    %     createPopOut_(container)  - REQUIRED; return a sibling instance
    %     popOutHostContainer_()    - container this component was built into
    %     addPopOutMenu_(cm)        - append the menu item to a uicontextmenu
    %     popOutPreferenceTag_()    - preference key given to the sibling
    %     PopOutSize                - default window size, [width height]
    %     PopOutLabel               - window title; defaults to the class name
    %
    % Documentation: documentation/gui/gui_PopOut.md
    % See also gui.BehaviorGUI, gui.ParameterScatter, gui.History,
    % gui.SessionPerformance, gui.NextTrial, gui.Parameter_Monitor

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

    properties (Constant, Hidden)
        POPOUT_MENU_TAG = 'gui_PopOut_menu' % Tag on the menu item this mixin creates
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
            movegui(fig, 'onscreen');

            % A borderless panel, not a uigridlayout: components that place
            % themselves with normalized Units warn inside a layout cell.
            container = uipanel(fig, 'Units', 'normalized', 'Position', [0 0 1 1], ...
                'BorderType', 'none');

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
        end

        function closePopOut(obj)
            % closePopOut(obj)
            % Close the pop-out window and delete its component. The host
            % component and its window are unaffected.
            if isempty(obj.PopOutComponent) && isempty(obj.PopOutFigure), return; end
            gui.PopOut.teardownPopOut_(obj.PopOutComponent, obj.PopOutFigure, ...
                obj.popOutPreferenceTag_());
            obj.forgetPopOut_();
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

    methods (Static, Access = private)

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
