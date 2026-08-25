classdef Parameter_Update < handle
    % obj = gui.Parameter_Update(RUNTIME, parent)
    % Update button controller for committing pending parameter edits.
    %
    % This class owns a uibutton whose enabled state and label reflect
    % whether any watched parameter editors have uncommitted changes.
    %
    % Methods:
    %   set.watchedHandles - Register parameter editor handles to watch.
    %   commit_changes     - Commit pending changes to runtime/trials.
    %   reset_changes      - Discard pending changes (hold Ctrl and click).
    % Documentation: documentation/gui/Parameter_Update.md

    properties (SetAccess = immutable)
        Button % underlying uibutton object
        Figure
    end

    properties
        watchedHandles (1,:) % handles we are listening to

        color_needToUpdate      (1,1) = "#98fa98";
        color_nothingToUpdate   (1,1) = "#f0f0f0";
        color_updateImmediately (1,1) = "#e28743";
        color_resetChanges      (1,1) = "#f5a3a3";
    end

    properties (Access = private)
        RUNTIME
    end

    properties (Access = private)
        updateImmediately (1,1) logical = false
        resetPending (1,1) logical = false % true while Ctrl alone is held, arming the button to discard edits

        hl_values
        hl_modifiers    % listener on a gui.KeyBindings, when one was given
    end

    methods
        function obj = Parameter_Update(RUNTIME,parent,options)
            % obj = gui.Parameter_Update(RUNTIME, parent, KeySource=)
            %
            % KeySource is a gui.KeyBindings. Given one, the button takes
            % the held modifiers from its ModifiersChanged event instead of
            % claiming the figure's key callbacks -- there is one such
            % callback per figure, and claiming it takes the keys away from
            % every other component. Without one (a standalone window with
            % no behavior GUI around it) the figure's shared KeyBindings is
            % looked up, or started, for the same reason.
            arguments
                RUNTIME
                parent (1,1)
                options.KeySource = []
            end

            obj.RUNTIME = RUNTIME;

            obj.Button = uibutton(parent);
            obj.Button.Text = "Update Parameters";
            obj.Button.Tooltip = ["Hold Ctrl+Shift+Alt while clicking to update parameters immediately."; ...
                "Hold Ctrl while clicking to reset pending edits to their previous values."];
            obj.Button.Enable = 'off';
            obj.Button.FontWeight = 'bold';
            obj.Button.ButtonPushedFcn = @obj.button_pushed;
            obj.Button.WordWrap = "on";

            obj.Figure = ancestor(obj.Button,'figure');

            ks = options.KeySource;
            if isempty(ks)
                % Join (or start) the figure's shared KeyBindings rather
                % than assigning the key callbacks outright: assigning took
                % them away from every neighbour, and two components each
                % chaining what they displaced could recurse into each
                % other on every keystroke.
                ks = gui.KeyBindings.getOrCreate(obj.Figure);
            end
            obj.hl_modifiers = listener(ks, 'ModifiersChanged', ...
                @(src,~) obj.modifiers_changed(src.CurrentModifiers));

            obj.color_nothingToUpdate = rgb2hex(obj.Button.BackgroundColor);
        end

        function delete(obj)
            try
                delete(obj.hl_values);
            end
            try
                delete(obj.hl_modifiers);
            end
        end


        function set.watchedHandles(obj,h)
            obj.watchedHandles = h;
            obj.hl_values = arrayfun(@(a) listener(a,'ValueUpdated','PostSet',@obj.value_changed),h);
            obj.value_changed;
        end

        function value_changed(obj,src,event)
            vu = [obj.watchedHandles.ValueUpdated];

            if any(vu)
                obj.Button.BackgroundColor = obj.color_needToUpdate;
                obj.Button.Text = "Update Parameters";
                obj.Button.Enable = 'on';
            else
                obj.Button.BackgroundColor = obj.color_nothingToUpdate;
                obj.Button.Text = "Nothing to Update";
                obj.Button.Enable = 'off';
            end
            drawnow
        end

        function key_press(obj,src,event)
            obj.modifiers_changed(event.Modifier);
        end

        function key_release(obj,src,event)
            obj.modifiers_changed(event.Modifier);
        end

        function modifiers_changed(obj,mods)
            % modifiers_changed(obj,mods)
            % Repaint the button to advertise what a click will do given the
            % modifier keys currently held: Ctrl+Shift+Alt commits
            % immediately, Ctrl alone discards pending edits.
            obj.updateImmediately = all(ismember({'shift','control','alt'},mods));
            obj.resetPending = ~obj.updateImmediately && isscalar(mods) && isequal(char(mods{1}),'control');

            % The modifier listener is live from construction, before any
            % handles are watched; there is nothing to repaint yet.
            if isempty(obj.watchedHandles) || ~any([obj.watchedHandles.ValueUpdated])
                obj.resetPending = false;
                return
            end

            if obj.updateImmediately
                obj.Button.BackgroundColor = obj.color_updateImmediately;
                obj.Button.Text = "Update Parameters Immediately";
                drawnow
            elseif obj.resetPending
                obj.Button.BackgroundColor = obj.color_resetChanges;
                obj.Button.Text = "Reset Parameters";
                drawnow
            else
                obj.value_changed;
            end
        end

        function commitPending(obj)
            % commitPending(obj)
            % Commit the pending edits, or do nothing when there are none.
            %
            % This is what a keyboard shortcut calls rather than
            % commit_changes: the button is disabled when nothing is
            % pending, so a chord must be inert then too -- otherwise a
            % stray keystroke rewrites the trial table and logs a commit
            % that changed nothing.
            if isempty(obj.watchedHandles) || ~any([obj.watchedHandles.ValueUpdated])
                return
            end
            obj.commit_changes([], []);
        end

        function button_pushed(obj,src,event)
            if obj.resetPending
                obj.reset_changes(src,event);
            else
                obj.commit_changes(src,event);
            end
        end

        function reset_changes(obj,src,event)
            % reset_changes(obj)
            % Discard uncommitted edits, restoring each watched control to the
            % value its parameter currently holds. Nothing is written to
            % hardware or to the trial table.
            vu = [obj.watchedHandles.ValueUpdated];
            h = obj.watchedHandles(vu);

            vprintf(1,'Resetting %d pending parameter edit(s)',numel(h))

            for i = 1:length(h)
                h(i).reset_value;
            end

            obj.resetPending = false;
            obj.value_changed;
        end

        function commit_changes(obj,src,event)
            R = obj.RUNTIME;

            if obj.updateImmediately
                vprintf(0,1,'Updating Parameters Immediately')
            else
                vprintf(0,'Updating Parameters for the Next Trial')
            end

            % CURRENTLY ONLY WORKS FOR SINGLE SUBJECT
            T = R.TRIALS.trials;

            vu = [obj.watchedHandles.ValueUpdated];
            h = obj.watchedHandles(vu);

            loc = R.TRIALS.writeParamIdx;

            for i = 1:length(h)
                P = h(i).Parameter;

                % A control bound to a property other than Value (Min, Max,
                % isRandom, ...) edits host-side parameter state, not a trial
                % value: it has no trials-table column and takes effect the
                % moment it is written (e.g. Depth.Min is read by staircase
                % clamping on the next step). Committing it as P.Value would
                % silently write the wrong property.
                if ~isequal(h(i).BoundProperty,'Value')
                    curStr = h(i).boundValueText();
                    h(i).setBoundValue(h(i).Value);
                    vprintf(2,'Updated parameter "%s" %s: %s -> %s', ...
                        P.Name,h(i).BoundProperty,curStr,h(i).boundValueText())
                    h(i).reset_label;
                    continue
                end

                if obj.updateImmediately || P.Parent.Type == "Software"
                    curValStr = P.ValueStr;
                    P.Value = h(i).Value;
                    vprintf(2,'Updated parameter "%s": %s -> %s',P.Name,curValStr,P.ValueStr)
                end

                if isfield(loc,P.validName)
                    [T{:,loc.(P.validName)}] = deal(h(i).Value);
                end

                h(i).reset_label;
            end
            R.TRIALS.trials = T;

            obj.updateImmediately = false;

        end
    end

    
end
