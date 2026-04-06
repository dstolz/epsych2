function [value,success] = eval_rwdelay_training_mode(obj,~,event,Parameter)
% eval_rwdelay_training_mode(obj,src,event,Parameter)
% Toggle response-window-delay “training mode” and manage the associated
% gui.StaircaseTraining instance.
%
% This function is intended to be used as an EvaluatorFcn callback for a
% parameter toggle in the main GUI. When training mode is enabled, it forces
% the underlying parameter to non-random mode, opens (or focuses) the
% training GUI, and starts a NewData listener to update the parameter based
% on trial outcomes.
%
% Parameters:
%   obj - GUI controller instance (expects obj.RUNTIME and RWDelay handles).
%   src - Callback source (unused).
%   event - Callback event data (expects event.Value as logical/0/1).
%   Parameter - Parameter object for response-window delay; its isRandom
%       field is temporarily overridden while training mode is active.
%
% Returns:
%   value - The new toggle value (event.Value).
%   success - True if the callback completed without throwing an error.
%
% See also:
%   gui.StaircaseTraining (documentation/gui/StaircaseTraining.md)

success = false;

RUNTIME = obj.RUNTIME;

try

    value = event.Value; % the new value of the training mode toggle (true/false)
    if event.Value == 1
        % store the original isRandom value in the Parameter's UserData for later restoration
        Parameter.UserData.isRandom = Parameter.isRandom;
        Parameter.isRandom = false;

        % launch the training mode GUI
        if ~isempty(obj.h_RWDelayTrainingGUI) && isvalid(obj.h_RWDelayTrainingGUI) % if the GUI doesn't exist or has been deleted, create it
            vprintf(2,'locating Response Window Delay Training GUI')
            if isvalid(obj.h_RWDelayTrainingGUI.Parent) && isa(obj.h_RWDelayTrainingGUI.Parent,'matlab.ui.Figure')
                figure(obj.h_RWDelayTrainingGUI.Parent); % bring to front if it already exists
            end
        else
            vprintf(2,'Launching Response Window Delay Training GUI')
            h = gui.StaircaseTraining(Parameter, ...
                'MinValue', 100, ...
                'MaxValue', 4000, ...
                'StepUp', 350, ...
                'StepDown', 100, ...
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

function update_rwdelay_training_mode(~,~,h,RUNTIME)
% update_rwdelay_training_mode(src,event,h,RUNTIME)
% Update the training GUI parameter based on the most recent trial outcome.
%
% This function is called on each RUNTIME.HELPER NewData event while training
% mode is active. It maps response codes to an “up” or “down” update, applies
% the update via gui.StaircaseTraining, and writes the resulting value into
% the current trials table (for the parameter matching P.validName).
%
% Parameters:
%   src - Callback source (unused).
%   event - Callback event data (unused).
%   h - gui.StaircaseTraining instance.
%   RUNTIME - Runtime state (expects TRIALS.DATA, TRIALS.trials, and
%       TRIALS.writeParamIdx).
if isempty(h) || ~isvalid(h), return; end

p = RUNTIME.TRIALS.DATA(end).RespCode;
RC = epsych.BitMask.decode([p.Value]);
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
