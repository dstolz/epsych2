classdef Parameter_Update < handle

    properties (SetAccess = immutable)
        Button % underlying uibutton object
        Figure
    end

    properties
        watchedHandles (1,:) % handles we are listening to

        color_needToUpdate (1,:) = '#98fa98';
        color_nothingToUpdate (1,:) = '#f0f0f0'; 
        color_updateImmediately (1,:) = '#e28743';
    end

    properties (Access = private)
        updateImmediately (1,1) logical = false

        hl_values
    end

    methods
        function obj = Parameter_Update(parent)
            obj.Button = uibutton(parent);
            obj.Button.Text = "Update Parameters";
            obj.Button.Tooltip = "Hold Ctrl+Shift+Alt while clicking to update parameters immediately.";
            obj.Button.Enable = 'off';
            obj.Button.FontWeight = 'bold';
            obj.Button.ButtonPushedFcn = @obj.commit_changes;
            obj.Button.WordWrap = "on";

            obj.Figure = ancestor(obj.Button,'figure');
            obj.Figure.WindowKeyPressFcn = @obj.key_press;
            obj.Figure.WindowKeyReleaseFcn  = @obj.key_release;

            obj.color_nothingToUpdate = obj.Button.BackgroundColor;
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
            obj.updateImmediately = all(ismember({'shift','control','alt'},event.Modifier));
            if obj.updateImmediately && any([obj.watchedHandles.ValueUpdated])
                obj.Button.BackgroundColor = obj.color_updateImmediately;
                obj.Button.Text = "Update Parameters Immediately";
            end
            drawnow    
        end

        function key_release(obj,src,event)
            obj.updateImmediately = all(ismember({'shift','control','alt'},event.Modifier));
            obj.value_changed;
        end

        function commit_changes(obj,src,event)
            global RUNTIME % must be global

            if obj.updateImmediately
                vprintf(0,1,'Updating Parameters Immediately')
            else
                vprintf(0,'Updating Parameters for the Next Trial')
            end

            % CURRENTLY ONLY WORKS FOR SINGLE SUBJECT
            T = RUNTIME.TRIALS.trials;

            vu = [obj.watchedHandles.ValueUpdated];
            h = obj.watchedHandles(vu);

            loc = RUNTIME.TRIALS.writeParamIdx;

            for i = 1:length(h)
                P = h(i).Parameter;
                vstr = sprintf(P.Format,h(i).Value);
                vprintf(2,'Updating parameter "%s". New value = "%s"',P.Name,vstr)
                
                if obj.updateImmediately
                    P.Value = h(i).Value;
                end

                if isfield(loc,P.validName)
                    [T{:,loc.(P.validName)}] = deal(h(i).Value);
                end

                h(i).reset_label;                
            end
            RUNTIME.TRIALS.trials = T;
            vprintf(0,'Updated %d parameters',length(h))

            obj.updateImmediately = false;
        end
    end
    
end