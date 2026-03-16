function [value,success] = eval_rwdelay_training_mode(obj,src,event,Parameter)
% eval_rwdelay_training_mode(obj,src,event,Parameter)
%
% implements the 'EvaluatorFcn' function

success = false;

RUNTIME = obj.RUNTIME;

try

    value = event.Value; % the new value of the training mode toggle (true/false)
    if event.Value == 1
        Parameter.UserData.isRandom = Parameter.isRandom;
        Parameter.isRandom = false;

        % launch the training mode GUI
        if ~isempty(obj.h_RWDelayTrainingGUI) && isvalid(obj.h_RWDelayTrainingGUI) % if the GUI doesn't exist or has been deleted, create it
            vprintf(2,'locating Response Window Delay Training GUI')
            uifigure(obj.h_RWDelayTrainingGUI.UIFigure); % bring to front if it already exists
        else
            vprintf(2,'Launching Response Window Delay Training GUI')
            h = ProgressiveTrainingGUI(Parameter, ...
                'MinValue', 100, ...
                'MaxValue', 4000, ...
                'StepUp', 20, ...
                'StepDown', 40, ...
                'StepDownLimits', [0 500], ...
                'StepUpLimits', [0 500], ...
                'MinValueLimits', [100 2000], ...
                'MaxValueLimits', [200 6000]);

            obj.hl_RWDelayTrainingGUI = addlistener(RUNTIME.HELPER,'NewData',@(src,event) update_rwdelay_training_mode(src,event,h,RUNTIME));
            obj.h_RWDelayTrainingGUI = h;
            
        end

        % disable the parameter control in the main GUI while training mode is active
        obj.h_RWDelayParameterControl.h_uiobj.Enable = 'off';

        success = true;
    else
        vprintf(2,'Closing Response Window Delay Training GUI')

        Parameter.isRandom = Parameter.UserData.isRandom;

        % close the training mode GUI if it's open
        delete(obj.h_RWDelayTrainingGUI);

        % re-enable the parameter control in the main GUI
        obj.h_RWDelayParameterControl.h_uiobj.Enable = 'on';

        % remove the event listener for training mode updates
        delete(obj.hl_RWDelayTrainingGUI);
    end

catch e
    vprintf(0,1,'Error evaluating Response Window Delay Training Mode: %s',getReport(e,'basic'))
    obj.h_RWDelayParameterControl.h_uiobj.Enable = 'on'; % ensure the parameter control is re-enabled if there's an error
    delete(obj.hl_RWDelayTrainingGUI);
    if ~isempty(obj.h_RWDelayTrainingGUI) && isvalid(obj.h_RWDelayTrainingGUI)
        delete(obj.h_RWDelayTrainingGUI);
    end
end

end

function update_rwdelay_training_mode(src,event,h,RUNTIME)
% This function is called whenever new trial data is available, and updates the training mode parameters
% based on the most recent trial data.
if isempty(h) || ~isvalid(h), return; end

RC = epsych.BitMask.decode(RUNTIME.TRIALS.DATA(end).RespCode);
if RC.Hit
    s = "up";
elseif RC.Abort % RC.Miss
    s = "down";
else
    return % only update parameters on Hit or Miss trials
end

vprintf(3,'Updating Response Window Delay Training Mode parameters based on trial outcome: %s',s)
newValue = h.updateParameter(s); % this will update the training parameters based on the trial outcome (Hit/Miss)

P = h.Parameter;

% CURRENTLY ONLY WORKS FOR SINGLE SUBJECT
if P.Parent.Type == "Software"
    curValStr = P.ValueStr;
    vprintf(3,'Updated parameter "%s": %s -> %s',P.Name,curValStr,P.ValueStr)
end

T = RUNTIME.TRIALS.trials;
loc = RUNTIME.TRIALS.writeParamIdx;

if isfield(loc,P.validName)
    [T{:,loc.(P.validName)}] = deal(newValue);
end


RUNTIME.TRIALS.trials = T;


end