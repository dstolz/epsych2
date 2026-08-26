classdef KeyBindings < handle
    % obj = gui.KeyBindings(fig)
    % Central keyboard-command processor for one figure.
    %
    % A MATLAB figure has exactly ONE WindowKeyPressFcn slot, so every
    % component that wanted a key used to claim it and silently take it
    % away from whoever claimed it first. This class owns both key slots
    % for a behavior GUI's figure and hands out bindings instead: a
    % component or a paradigm's build() asks for a chord, and every
    % binding coexists.
    %
    % Bindings are CODE, not operator preference. Nothing here is
    % persisted and there is no rebinding UI -- what a paradigm binds is
    % what the rig does, and showHelp lists it for the operator.
    %
    % Properties:
    %   Figure           - the figure whose key callbacks this owns
    %   CurrentModifiers - modifier keys held right now, as evt.Modifier
    %   ReviewModeFcn    - @() logical; bindings are suppressed when true
    %   Title            - help dialog title
    %
    % Methods:
    %   bind, unbind, isBound, list, showHelp, claimFigure, modifiersDown
    %   gui.KeyBindings.getOrCreate(fig) - the figure's shared instance
    %
    % Events:
    %   ModifiersChanged - the held modifier set changed
    %
    % Example:
    %   obj.Keys.bind('ctrl+r', @() obj.rewardNow(), ...
    %       Description = 'Deliver a reward', Owner = h);
    %
    % Two limitations worth knowing, neither of them fixable here:
    % a uifigure does not deliver window key events while an edit field or
    % text area has focus (which is also what keeps a shortcut from firing
    % while the operator types a note), and a modifier released while
    % another window has focus is not reported -- the held set corrects
    % itself at the next keystroke.
    %
    % See also gui.BehaviorGUI, gui.components.Parameter_Update, gui.components.RegenerateTrial
    % Documentation: documentation/gui/gui_KeyBindings.md

    properties (SetAccess = private)
        Figure                          % Figure whose key callbacks this owns
        CurrentModifiers (1,:) cell = {} % Modifiers held now, e.g. {'control','shift'}
    end

    properties
        ReviewModeFcn = []              % @() logical; empty means never in review
        Title (1,:) char = 'Keyboard Shortcuts' % Help dialog title
    end

    events
        ModifiersChanged                % Fired when CurrentModifiers changes
    end

    properties (Access = private)
        Bindings_                       % containers.Map: canonical chord -> binding struct
        Order_ (1,1) double = 0         % Bind counter, so help lists in bind order

        KeyPressHook_ = []              % This object's installed press callback
        KeyReleaseHook_ = []            % ... and release callback
        LegacyKeyPress_ = []            % Foreign callback found in the slot, chained on a miss
        LegacyKeyRelease_ = []
    end

    properties (Constant, Access = private)
        % evt.Key names that are modifiers in their own right. They are
        % state, never a chord: a bare Ctrl press must not look up 'ctrl'.
        MODIFIER_KEYS = {'control','shift','alt','command','ctrl','capslock','option','windows'}
    end

    methods
        function obj = KeyBindings(fig)
            % obj = gui.KeyBindings(fig)
            % Take over the figure's key callbacks. Whatever was already
            % wired there is kept and called for any key this object has
            % no binding for.
            arguments
                fig (1,1) matlab.ui.Figure
            end

            obj.Figure = fig;
            obj.Bindings_ = containers.Map('KeyType','char','ValueType','any');
            obj.claimFigure();

            % Register on the figure, so a component constructed without a
            % KeySource can find this instance (getOrCreate) instead of
            % claiming the key-callback slot for itself.
            setappdata(fig, 'epsych_KeyBindings', obj);
        end

        function delete(obj)
            % Put back what was found, but only where this object's hook is
            % still installed: something else may have claimed the slot
            % since, and restoring over it would break that neighbour.
            try
                fig = obj.Figure;
                if isempty(fig) || ~isvalid(fig), return; end
                if gui.KeyBindings.isInstalled_(fig.WindowKeyPressFcn, obj.KeyPressHook_)
                    fig.WindowKeyPressFcn = obj.LegacyKeyPress_;
                end
                if gui.KeyBindings.isInstalled_(fig.WindowKeyReleaseFcn, obj.KeyReleaseHook_)
                    fig.WindowKeyReleaseFcn = obj.LegacyKeyRelease_;
                end
                if isappdata(fig, 'epsych_KeyBindings') && ...
                        isequal(getappdata(fig, 'epsych_KeyBindings'), obj)
                    rmappdata(fig, 'epsych_KeyBindings');
                end
            catch ME
                vprintf(3, 'gui.KeyBindings: could not restore key callbacks (%s)', ME.message)
            end
        end

        function claimFigure(obj)
            % claimFigure(obj)
            % Install this object's key callbacks, keeping any foreign
            % callback found in the slot to chain on an unbound key.
            %
            % Idempotent, and meant to be called AGAIN after a GUI's
            % build() has run: a component constructed during build may
            % have assigned the slot itself, and this is what takes it back
            % without throwing that component's handler away.
            fig = obj.Figure;
            if isempty(fig) || ~isvalid(fig), return; end

            if ~gui.KeyBindings.isInstalled_(fig.WindowKeyPressFcn, obj.KeyPressHook_)
                obj.noteForeignClaim_(fig.WindowKeyPressFcn, 'WindowKeyPressFcn');
                obj.LegacyKeyPress_   = fig.WindowKeyPressFcn;
                obj.KeyPressHook_     = @(s,e) obj.dispatchKeyPress(e);
                fig.WindowKeyPressFcn = obj.KeyPressHook_;
            end

            if ~gui.KeyBindings.isInstalled_(fig.WindowKeyReleaseFcn, obj.KeyReleaseHook_)
                obj.LegacyKeyRelease_   = fig.WindowKeyReleaseFcn;
                obj.KeyReleaseHook_     = @(s,e) obj.dispatchKeyRelease(e);
                fig.WindowKeyReleaseFcn = obj.KeyReleaseHook_;
            end
        end

        function chord = bind(obj, chord, callback, options)
            % chord = bind(obj, chord, callback, ...)
            % Bind a chord to a zero-argument callback. Returns the
            % canonical chord.
            %
            %   Description    text for the help dialog
            %   Group          help dialog section; defaults to the owner's
            %                  class name, else 'General'
            %   Owner          component handle; the binding is dropped once
            %                  the owner is deleted
            %   EnableInReview fire during an epsych.ReviewSession too
            %   Replace        overwrite an existing binding instead of
            %                  erroring
            %
            % A duplicate chord is an error, not a warning: bindings are
            % written in code, so a collision is a paradigm bug and should
            % stop at the first run rather than leave one of the two
            % commands quietly dead.
            arguments
                obj
                chord (1,:) char
                callback (1,1) function_handle
                options.Description (1,:) char = ''
                options.Group (1,:) char = ''
                options.Owner = []
                options.EnableInReview (1,1) logical = false
                options.Replace (1,1) logical = false
            end

            chord = gui.KeyBindings.normalize(chord);

            if obj.Bindings_.isKey(chord) && ~options.Replace
                error('epsych:KeyBindings:duplicateChord', ...
                    '%s is already bound (%s). Pass Replace=true to override it.', ...
                    gui.KeyBindings.displayChord(chord), obj.Bindings_(chord).Description)
            end

            group = options.Group;
            if isempty(group)
                if ~isempty(options.Owner)
                    group = gui.KeyBindings.spacedClassName_(class(options.Owner));
                else
                    group = 'General';
                end
            end

            obj.Order_ = obj.Order_ + 1;
            obj.Bindings_(chord) = struct( ...
                'Callback',       callback, ...
                'Description',    options.Description, ...
                'Group',          group, ...
                'Owner',          options.Owner, ...
                'EnableInReview', options.EnableInReview, ...
                'Order',          obj.Order_);
        end

        function unbind(obj, chord)
            % unbind(obj, chord)
            arguments
                obj
                chord (1,:) char
            end
            c = gui.KeyBindings.normalize(chord);
            if obj.Bindings_.isKey(c)
                obj.Bindings_.remove(c);
            end
        end

        function tf = isBound(obj, chord)
            % tf = isBound(obj, chord)
            arguments
                obj
                chord (1,:) char
            end
            tf = obj.Bindings_.isKey(gui.KeyBindings.normalize(chord));
        end

        function L = list(obj)
            % L = list(obj)
            % Every binding, in the order it was bound: Chord, Display,
            % Description, Group, EnableInReview.
            L = struct('Chord',{},'Display',{},'Description',{},'Group',{},'EnableInReview',{});
            keys = obj.Bindings_.keys;
            if isempty(keys), return; end

            for i = 1:numel(keys)
                b = obj.Bindings_(keys{i});
                L(i) = struct('Chord', keys{i}, ...
                    'Display',        gui.KeyBindings.displayChord(keys{i}), ...
                    'Description',    b.Description, ...
                    'Group',          b.Group, ...
                    'EnableInReview', b.EnableInReview);
            end

            orders = cellfun(@(k) obj.Bindings_(k).Order, keys);
            [~, idx] = sort(orders);
            L = L(idx);
        end

        function tf = modifiersDown(obj, mods)
            % tf = modifiersDown(obj, mods)
            % Are all of `mods` (e.g. {'control','alt','shift'}) held now?
            arguments
                obj
                mods (1,:) cell
            end
            tf = all(ismember(mods, obj.CurrentModifiers));
        end

        showHelp(obj)
    end

    methods (Hidden)
        function dispatchKeyPress(obj, evt)
            % Installed WindowKeyPressFcn. Hidden rather than private so a
            % test can drive it with a synthesized event struct.
            obj.updateModifiers_(evt);

            key = gui.KeyBindings.eventKey_(evt);
            if isempty(key) || ismember(key, gui.KeyBindings.MODIFIER_KEYS)
                % A modifier is state, never a chord of its own -- but a
                % chained foreign handler still needs to see it going DOWN:
                % a legacy handler that tracks held modifiers itself (the
                % pre-KeyBindings gui.components.Parameter_Update pattern) arms its
                % Ctrl-hold gestures from exactly these presses, and a
                % release only ever reports a smaller held set.
                obj.callLegacy_(obj.LegacyKeyPress_, evt);
                return
            end

            chord = gui.KeyBindings.chordString_(gui.KeyBindings.eventModifiers_(evt), key);

            if ~obj.Bindings_.isKey(chord)
                obj.callLegacy_(obj.LegacyKeyPress_, evt);
                return
            end

            b = obj.Bindings_(chord);

            % An owner that has been deleted takes its binding with it, so
            % a chord is never answered by a dead component.
            if ~isempty(b.Owner) && ~isvalid(b.Owner)
                obj.Bindings_.remove(chord);
                vprintf(3, 'gui.KeyBindings: dropped %s; its component is gone', ...
                    gui.KeyBindings.displayChord(chord))
                obj.callLegacy_(obj.LegacyKeyPress_, evt);
                return
            end

            if ~b.EnableInReview && obj.inReview_()
                vprintf(2, 'gui.KeyBindings: %s ignored; a review replays a finished session', ...
                    gui.KeyBindings.displayChord(chord))
                return
            end

            try
                b.Callback();
            catch ME
                vprintf(0, 1, ME);
            end
        end

        function dispatchKeyRelease(obj, evt)
            % Installed WindowKeyReleaseFcn. A release event reports the
            % modifiers STILL held, so the same read tracks them down.
            obj.updateModifiers_(evt);
            obj.callLegacy_(obj.LegacyKeyRelease_, evt);
        end
    end

    methods (Access = private)
        function updateModifiers_(obj, evt)
            mods = gui.KeyBindings.eventModifiers_(evt);
            if isequal(sort(mods), sort(obj.CurrentModifiers)), return; end
            obj.CurrentModifiers = mods;
            notify(obj, 'ModifiersChanged');
        end

        function tf = inReview_(obj)
            tf = false;
            if isempty(obj.ReviewModeFcn), return; end
            try
                tf = logical(obj.ReviewModeFcn());
            catch ME
                vprintf(3, 'gui.KeyBindings: could not determine review mode (%s)', ME.message)
            end
        end

        function callLegacy_(obj, fcn, evt)
            % Call a foreign handler found in the slot. Never let it take
            % this dispatcher down with it: the bindings have to keep
            % working whatever else was wired to the same key. The figure
            % is passed as the source, because that is what MATLAB itself
            % would have passed a WindowKeyPressFcn -- a handler reading
            % src must keep working chained.
            if isempty(fcn), return; end
            try
                if isa(fcn, 'function_handle')
                    fcn(obj.Figure, evt);
                elseif ischar(fcn) || isstring(fcn)
                    evalin('base', char(fcn));
                elseif iscell(fcn)
                    fcn{1}(obj.Figure, evt, fcn{2:end});
                end
            catch ME
                vprintf(2, 'gui.KeyBindings: chained key callback failed: %s', ME.message)
            end
        end

        function noteForeignClaim_(~, fcn, slot)
            if isempty(fcn), return; end
            vprintf(2, ['gui.KeyBindings: %s was already claimed; it will be ' ...
                'called for keys with no binding. Bind through gui.KeyBindings instead.'], slot)
        end
    end

    methods (Static)
        function obj = getOrCreate(fig)
            % obj = gui.KeyBindings.getOrCreate(fig)
            % The figure's registered KeyBindings, creating and registering
            % one when the figure has none.
            %
            % This is how a component constructed WITHOUT a KeySource joins
            % the figure's keyboard: two components that each claimed the
            % figure's one WindowKeyPressFcn slot and chained what they
            % found could end up chained to each other, and every unbound
            % keystroke then recursed to MATLAB's recursion limit. One
            % shared dispatcher per figure makes that impossible.
            arguments
                fig (1,1) matlab.ui.Figure
            end
            obj = [];
            if isappdata(fig, 'epsych_KeyBindings')
                k = getappdata(fig, 'epsych_KeyBindings');
                if isa(k, 'gui.KeyBindings') && isvalid(k), obj = k; end
            end
            if isempty(obj)
                obj = gui.KeyBindings(fig);
            end
        end

        function chord = normalize(chord)
            % chord = gui.KeyBindings.normalize('Ctrl+Shift+R')
            % Canonical form: modifiers in a fixed order, lowercase, joined
            % with '+', e.g. 'ctrl+alt+shift+r'. Errors on an empty or
            % modifier-only chord.
            arguments
                chord (1,:) char
            end

            parts = strsplit(lower(strtrim(chord)), '+');
            parts = parts(~cellfun(@isempty, parts));
            if isempty(parts)
                error('epsych:KeyBindings:emptyChord', 'A chord needs at least a key.')
            end

            hasCtrl = false; hasAlt = false; hasShift = false;
            key = '';
            for i = 1:numel(parts)
                switch parts{i}
                    case {'ctrl','control','command','cmd'}
                        hasCtrl = true;
                    case {'alt','option'}
                        hasAlt = true;
                    case 'shift'
                        hasShift = true;
                    otherwise
                        if ~isempty(key)
                            error('epsych:KeyBindings:badChord', ...
                                'A chord names one key: "%s" has both "%s" and "%s".', ...
                                chord, key, parts{i})
                        end
                        key = gui.KeyBindings.aliasKey_(parts{i});
                end
            end

            if isempty(key)
                error('epsych:KeyBindings:modifiersOnly', ...
                    '"%s" names only modifiers; a chord needs a key.', chord)
            end

            chord = gui.KeyBindings.chordString_(...
                [repmat({'control'},1,hasCtrl), repmat({'alt'},1,hasAlt), repmat({'shift'},1,hasShift)], key);
        end

        function chord = chordOf(evt)
            % chord = gui.KeyBindings.chordOf(evt)
            % Canonical chord for a figure KeyData event, or '' when the
            % event carries only a modifier key.
            key = gui.KeyBindings.eventKey_(evt);
            if isempty(key) || ismember(key, gui.KeyBindings.MODIFIER_KEYS)
                chord = '';
                return
            end
            chord = gui.KeyBindings.chordString_(gui.KeyBindings.eventModifiers_(evt), key);
        end

        function s = displayChord(chord)
            % s = gui.KeyBindings.displayChord('ctrl+shift+slash')
            % The chord as an operator reads it: 'Ctrl+Shift+/'.
            parts = strsplit(gui.KeyBindings.normalize(chord), '+');
            out = cell(1, numel(parts));
            for i = 1:numel(parts)
                switch parts{i}
                    case 'control',    out{i} = 'Ctrl';
                    case 'alt',        out{i} = 'Alt';
                    case 'shift',      out{i} = 'Shift';
                    case 'return',     out{i} = 'Enter';
                    case 'slash',      out{i} = '/';
                    case 'backslash',  out{i} = '\';
                    case 'period',     out{i} = '.';
                    case 'comma',      out{i} = ',';
                    case 'space',      out{i} = 'Space';
                    case 'escape',     out{i} = 'Esc';
                    case 'leftarrow',  out{i} = 'Left Arrow';
                    case 'rightarrow', out{i} = 'Right Arrow';
                    case 'uparrow',    out{i} = 'Up Arrow';
                    case 'downarrow',  out{i} = 'Down Arrow';
                    case 'pageup',     out{i} = 'Page Up';
                    case 'pagedown',   out{i} = 'Page Down';
                    otherwise
                        if isscalar(parts{i})
                            out{i} = upper(parts{i});
                        else
                            out{i} = [upper(parts{i}(1)) parts{i}(2:end)];
                        end
                end
            end
            s = strjoin(out, '+');
        end
    end

    methods (Static, Access = private)
        function chord = chordString_(mods, key)
            % Modifiers in a fixed order so 'shift+ctrl+r' and 'ctrl+shift+r'
            % are the same binding.
            mods = lower(mods);
            parts = {};
            if any(ismember({'control','command'}, mods)), parts{end+1} = 'control'; end
            if any(ismember({'alt','option'}, mods)),       parts{end+1} = 'alt';     end
            if ismember('shift', mods),                     parts{end+1} = 'shift';   end
            parts{end+1} = key;
            chord = strjoin(parts, '+');
        end

        function key = aliasKey_(key)
            % Fold the names one key reports under into one, following what
            % epsych.RunExpt and epsych.ProtocolDesigner already special-case.
            key = lower(key);
            switch key
                case {'?','question'}
                    key = 'slash';
                case '/'
                    key = 'slash';
                case {'enter','cr'}
                    key = 'return';
                case 'esc'
                    key = 'escape';
                case 'del'
                    key = 'delete';
                otherwise
                    if startsWith(key, 'numpad') && numel(key) > 6
                        key = extractAfter(key, 'numpad');   % numpad3 answers to 3
                    end
            end
        end

        function key = eventKey_(evt)
            key = '';
            try
                if isempty(evt.Key), return; end
                key = gui.KeyBindings.aliasKey_(char(evt.Key));
            catch
                key = '';
            end
        end

        function mods = eventModifiers_(evt)
            mods = {};
            try
                m = evt.Modifier;
                if isempty(m), return; end
                if ischar(m) || isstring(m), m = cellstr(m); end
                mods = lower(reshape(cellstr(m), 1, []));
            catch
                mods = {};
            end
        end

        function name = spacedClassName_(cls)
            % gui.components.RegenerateTrial -> 'Regenerate Trial', matching how
            % gui.components.ComponentToolbar labels a component with no given name.
            %
            % The capture-group form is load bearing. The obvious
            % zero-width version, regexprep(name,'(?<=[a-z0-9])(?=[A-Z])',
            % ' '), matches but inserts NOTHING in MATLAB, so every group
            % heading came out as the unsplit class name (SCREENCAPTURE).
            % Consuming the two characters and putting them back with
            % '$1 $2' is what gui.components.ComponentToolbar.entryLabel already
            % does; an all-caps name like NAFC is left alone by both.
            parts = strsplit(cls, '.');
            name = parts{end};
            name = regexprep(name, '_', ' ');
            name = strtrim(regexprep(name, '([a-z0-9])([A-Z])', '$1 $2'));
        end

        function tf = isInstalled_(current, hook)
            % Is `current` this object's own hook?
            %
            % The isempty test is load bearing: an unset figure callback is
            % '' and an uninstalled hook is [], and isequal('',[]) is TRUE
            % in MATLAB -- both are 0x0 empty. Testing with isequal alone
            % reports the hook as installed on the bare figure every first
            % install starts from, so nothing is ever wired up.
            tf = ~isempty(hook) && isequal(current, hook);
        end
    end
end
