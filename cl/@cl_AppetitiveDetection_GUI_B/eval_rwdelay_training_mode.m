function [value,success] = eval_rwdelay_training_mode(obj,src,event,Parameter)
% [value,success] = eval_rwdelay_training_mode(obj,src,event,Parameter)
%
% implements the 'EvaluatorFcn' function
success = true;

try
    
    if event.NewValue == 1
        % launch the training mode GUI
        if isvalid(obj.h_ProgressiveTrainingGUI) % if the GUI doesn't exist or has been deleted, create it
            obj.h_ProgressiveTrainingGUI = ProgressiveTrainingGUI(Parameter);
        else
            uifigure(obj.h_ProgressiveTrainingGUI.UIFigure); % bring to front if it already exists
        end
    else
        % close the training mode GUI if it's open
        delete(obj.h_ProgressiveTrainingGUI);
    end

catch e
    success = false;
    value = 0; % default to 0 (training mode off) on error
    vprintf(0,1,'Error evaluating Response Window Delay Training Mode: %s',getReport(e,'basic'))
end

