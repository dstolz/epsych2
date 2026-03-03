function [value,success] = eval_rwdelay_training_mode(obj,src,event,Parameter)
% [value,success] = eval_rwdelay_training_mode(obj,src,event,Parameter)
%
% implements the 'EvaluatorFcn' function

global RUNTIME % TO DO: FIND A BETTER WAY TO ACCESS RUNTIME.HELPER

success = true;

try
    
    if event.NewValue == 1
        % launch the training mode GUI
        if isvalid(obj.h_RWDelayTrainingGUI) % if the GUI doesn't exist or has been deleted, create it
            uifigure(obj.h_RWDelayTrainingGUI.UIFigure); % bring to front if it already exists
        else
            h = ProgressiveTrainingGUI(Parameter);
            obj.hl_RWDelayTrainingGUI = addlistener(RUNTIME.HELPER,'NewData',@(src,event) update_rwdelay_training_mode(src,event,h));
            obj.h_RWDelayTrainingGUI = h;
        end
    else
        % close the training mode GUI if it's open
        delete(obj.h_RWDelayTrainingGUI);
    end

catch e
    success = false;
    value = 0; % default to 0 (training mode off) on error
    vprintf(0,1,'Error evaluating Response Window Delay Training Mode: %s',getReport(e,'basic'))
end

end

function update_rwdelay_training_mode(src,event,h)
    % This function is called whenever new trial data is available, and updates the training mode parameters
    % based on the most recent trial data.
global RUNTIME


RC = epsych.BitMask.decodeResponseCodes(RUNTIME.TRIALS.DATA(end).RespCode);
if RC.Hit
    s = "down";
elseif RC.Miss
    s = "up";
else
    return % only update parameters on Hit or Miss trials
end
h.update_training_mode(s);

end