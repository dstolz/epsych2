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
    end

    methods
        function obj = Parameter_Update(RUNTIME,parent)
            arguments
                RUNTIME
                parent (1,1)
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
            obj.Figure.WindowKeyPressFcn = @obj.key_press;
            obj.Figure.WindowKeyReleaseFcn  = @obj.key_release;

            obj.color_nothingToUpdate = rgb2hex(obj.Button.BackgroundColor);
        end

        function delete(obj)
            try
                delete(obj.hl_values);
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

            if ~any([obj.watchedHandles.ValueUpdated])
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
