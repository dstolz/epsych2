classdef Parameter_Update < handle

    properties (SetAccess = immutable)
        Button % underlying uibutton object
    end

    properties
        watchedHandles (1,:) % handles we are listening to

        color_needToUpdate (1,:) double = [0 .6 0];
        color_nothingToUpdate (1,:) double
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
            obj.watchedHandles = arrayfun(@(a) addlistener(a,'ValueUpdated','PostSet',@obj.value_changed),h);
        end

        function value_changed(obj,src,event)
            obj.Button.BackgroundColor = obj.color_needToUpdate;
            obj.Button.Enable = 'on';
        end

        function commit_changes(obj,src,event)
            
            % TO DO: ACTUALLY UPDATE THE TRIALS TABLE

            arrayfun(@(a) a.Object{1}.reset_label,obj.watchedHandles);
            obj.Button.Enable = 'off';
            obj.Button.BackgroundColor = obj.color_nothingToUpdate;
        end
    end
    
end