function eval_rwdelay_training_mode(obj,src,event,Parameter)
% eval_rwdelay_training_mode(obj,src,event,Parameter)
%
% implements the 'EvaluatorFcn' function

global RUNTIME % TO DO: FIND A BETTER WAY TO ACCESS RUNTIME.HELPER


try
    
    if event.Value == 1
        % launch the training mode GUI
        if ~isempty(obj.h_RWDelayTrainingGUI) && isvalid(obj.h_RWDelayTrainingGUI) % if the GUI doesn't exist or has been deleted, create it
            uifigure(obj.h_RWDelayTrainingGUI.UIFigure); % bring to front if it already exists
        else
            h = ProgressiveTrainingGUI(Parameter, ...
                'MinValue', 100, ...
                'MaxValue', 4000, ...
                'StepUp', 20, ...
                'StepDown', 40, ...
                'StepDownLimits', [0 500], ...
                'StepUpLimits', [0 500], ...
                'MinValueLimits', [100 2000], ...
                'MaxValueLimits', [200 6000]);

            obj.hl_RWDelayTrainingGUI = addlistener(RUNTIME.HELPER,'NewData',@(src,event) update_rwdelay_training_mode(src,event,h));
            obj.h_RWDelayTrainingGUI = h;
        end
    else
        % close the training mode GUI if it's open
        delete(obj.h_RWDelayTrainingGUI);
    end

catch e
    vprintf(0,1,'Error evaluating Response Window Delay Training Mode: %s',getReport(e,'basic'))
end

end

function update_rwdelay_training_mode(src,event,h)
    % This function is called whenever new trial data is available, and updates the training mode parameters
    % based on the most recent trial data.
global RUNTIME

if isempty(h) || ~isvalid(h), return; end

RC = epsych.BitMask.decodeResponseCodes(RUNTIME.TRIALS.DATA(end).RespCode);
if RC.Hit
    s = "down";
elseif RC.Miss
    s = "up";
else
    return % only update parameters on Hit or Miss trials
end

vprintf(3,'Updating Response Window Delay Training Mode parameters based on trial outcome: %s',s)
h.updateParameter(s); % this will update the training parameters based on the trial outcome (Hit/Miss)

end