function [value,success] = eval_rwdelay_training_mode(obj,src,event)
% [value,success] = eval_rwdelay_training_mode(obj,src,event)
%
% implements the 'EvaluatorFcn' function
success = true;

try
    
    if event.NewValue == 1
        % launch the training mode GUI
        if ~isvalid(obj.RWDelayTrainingGUI) % if the GUI doesn't exist or has been deleted, create it
            obj.h_RWDelayTrainingGUI = RWDelayTrainingGUI(obj.RUNTIME);
        else
            % if it already exists, just make it visible
            obj.h_RWDelayTrainingGUI.UIFigure.Visible = 'on';
        end
    else
        % close the training mode GUI if it's open
        if isvalid(obj.RWDelayTrainingGUI)
            obj.h_RWDelayTrainingGUI.UIFigure.Visible = 'off';
        end
    end

catch e
    success = false;
    value = event.PreviousValue; % return to previous value
    vprintf(0,1,'Error evaluating Response Window Delay Training Mode: %s',getReport(e,'basic'))
end

