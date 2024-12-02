classdef Parameter_Update < handle

    properties (SetAccess = immutable)
        Button % underlying uibutton object
    end

    properties
        watchedHandles (1,:) % handles we are listening to

        color_needToUpdate (1,:) = '#98fa98';
        color_nothingToUpdate (1,:) = 'f0f0f0'; 
    end

    methods
        function obj = Parameter_Update(parent)
            obj.Button = uibutton(parent);
            obj.Button.Text = "Update Parameters";
            obj.Button.Enable = 'off';
            obj.Button.FontWeight = 'bold';
            obj.Button.ButtonPushedFcn = @obj.commit_changes;

            obj.color_nothingToUpdate = obj.Button.BackgroundColor;
        end


        function set.watchedHandles(obj,h)
            obj.watchedHandles = h;
            arrayfun(@(a) addlistener(a,'ValueUpdated','PostSet',@obj.value_changed),h);
        end

        function value_changed(obj,src,event)
            % THIS IS NOT CORRECT. THE BUTTON SHOULD ENABLE WITH ONE OR
            % MORE CHANGES, AND DISABLE WHEN NO CHANGES

            vu = [obj.watchedHandles.ValueUpdated];

            if any(vu)
                obj.Button.BackgroundColor = obj.color_needToUpdate;
                obj.Button.Enable = 'on';
            else
                obj.Button.BackgroundColor = obj.color_nothingToUpdate;
                obj.Button.Enable = 'off';
            end
        end

        function commit_changes(obj,src,event)
            
            % TO DO: ACTUALLY UPDATE THE PARAMETERS

           
            vu = [obj.watchedHandles.ValueUpdated];
            h = obj.watchedHandles(vu);

            for i = 1:length(h)
                P = h(i).Parameter;
                P.Value = h(i).Value;
                h(i).reset_label;
            end

        end
    end
    
end