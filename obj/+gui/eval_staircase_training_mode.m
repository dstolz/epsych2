function [value,success] = eval_staircase_training_mode(obj,src,event,Parameter,options)
% [value,success] = eval_staircase_training_mode(obj,src,event,Parameter,Name,Value)
% Toggle staircase "training mode" for any parameter and manage the
% associated gui.StaircaseTraining instance.
%
% This function is intended to be used as a ValueChangedFcn callback for a
% state button in the main GUI. When training mode is enabled, it forces
% the underlying parameter to non-random mode, opens (or focuses) the
% training GUI, and starts a NewData listener to update the parameter based
% on trial outcomes. When disabled, it restores the previous random state,
% closes the GUI, and removes the listener.
%
% Parameters:
%   obj              - GUI controller instance (expects obj.RUNTIME).
%   src              - Callback source (unused).
%   event            - Callback event data (expects event.Value as logical).
%   Parameter        - hw.Parameter object whose value is adjusted by the
%                      staircase procedure.
%   Name-Value pairs forwarded to gui.StaircaseTraining constructor:
%       MinValue, MaxValue, StepUp, StepDown,
%       StepDownLimits, StepUpLimits, MinValueLimits, MaxValueLimits
%
% Returns:
%   value   - The new toggle value (event.Value).
%   success - True if the callback completed without error.
%
% See also:
%   gui.StaircaseTraining (documentation/StaircaseTraining.md)

arguments
    obj
    src
    event
    Parameter
    options.MinValue       (1,1) double = Parameter.Min
    options.MaxValue       (1,1) double = Parameter.Max
    options.StepUp         (1,1) double = 350
    options.StepDown       (1,1) double = 100
    options.StepDownLimits (1,2) double = [0 500]
    options.StepUpLimits   (1,2) double = [0 500]
    options.MinValueLimits (1,2) double = [Parameter.Min Parameter.Max]
    options.MaxValueLimits (1,2) double = [Parameter.Min Parameter.Max]
end

success = false;
RUNTIME = obj.RUNTIME;
pName = Parameter.Name;

% initialise maps on first call
if isempty(obj.StaircaseTrainingGUIs) || ~isa(obj.StaircaseTrainingGUIs,'containers.Map')
    obj.StaircaseTrainingGUIs = containers.Map('KeyType','char','ValueType','any');
end
if isempty(obj.StaircaseTrainingListeners) || ~isa(obj.StaircaseTrainingListeners,'containers.Map')
    obj.StaircaseTrainingListeners = containers.Map('KeyType','char','ValueType','any');
end

try
    value = event.Value;

    if value == 1
        Parameter.UserData.isRandom = Parameter.isRandom;
        Parameter.isRandom = false;

        % launch or focus the training mode GUI
        if obj.StaircaseTrainingGUIs.isKey(pName) && isvalid(obj.StaircaseTrainingGUIs(pName))
            vprintf(2,'Locating %s Training GUI',pName)
            h = obj.StaircaseTrainingGUIs(pName);
            if isvalid(h.Parent) && isa(h.Parent,'matlab.ui.Figure')
                figure(h.Parent);
            end
        else
            vprintf(2,'Launching %s Training GUI',pName)
            nvArgs = namedargs2cell(options);
            h = gui.StaircaseTraining(Parameter, nvArgs{:});

            obj.StaircaseTrainingListeners(pName) = addlistener( ...
                RUNTIME.HELPER, 'NewData', ...
                @(src,ev) update_staircase_training(src, ev, h, RUNTIME));
            obj.StaircaseTrainingGUIs(pName) = h;
        end

        if ~isempty(ParameterControl)
            ParameterControl.h_uiobj.Enable = 'off';
        end
        success = true;

    else
        vprintf(2,'Closing %s Training GUI',pName)

        Parameter.isRandom = Parameter.UserData.isRandom;

        if obj.StaircaseTrainingGUIs.isKey(pName)
            delete(obj.StaircaseTrainingGUIs(pName));
            remove(obj.StaircaseTrainingGUIs, pName);
        end

        if ~isempty(ParameterControl)
            ParameterControl.h_uiobj.Enable = 'on';
        end

        if obj.StaircaseTrainingListeners.isKey(pName)
            delete(obj.StaircaseTrainingListeners(pName));
            remove(obj.StaircaseTrainingListeners, pName);
        end

        success = true;
    end

catch e
    vprintf(0,1,'Error in %s Training Mode: %s',pName,getReport(e,'basic'))
    if ~isempty(ParameterControl)
        ParameterControl.h_uiobj.Enable = 'on';
    end
    if obj.StaircaseTrainingListeners.isKey(pName)
        delete(obj.StaircaseTrainingListeners(pName));
        remove(obj.StaircaseTrainingListeners, pName);
    end
    if obj.StaircaseTrainingGUIs.isKey(pName)
        delete(obj.StaircaseTrainingGUIs(pName));
        remove(obj.StaircaseTrainingGUIs, pName);
    end
end

end


function update_staircase_training(~,~,h,RUNTIME)
% update_staircase_training(src,event,h,RUNTIME)
% Update the staircase parameter based on the most recent trial outcome.
%
% Called on each RUNTIME.HELPER NewData event while training mode is
% active. Maps response codes to "up" or "down", applies the update via
% gui.StaircaseTraining, and writes the resulting value into the current
% trials table when the parameter is backed by hardware (non-Software).
%
% Parameters:
%   src     - Callback source (unused).
%   event   - Callback event data (unused).
%   h       - gui.StaircaseTraining instance.
%   RUNTIME - Runtime state.

if isempty(h) || ~isvalid(h), return; end

RC = epsych.BitMask.decode(RUNTIME.TRIALS.DATA(end).RespCode);
if RC.Hit
    s = "up";
elseif RC.Abort
    s = "down";
else
    return
end

P = h.Parameter;
vprintf(3,'Updating %s Training Mode: %s',P.Name,s)

curValStr = P.ValueStr;
newValue = h.updateParameter(s);
vprintf(3,'Updated parameter "%s": %s -> %s',P.Name,curValStr,P.ValueStr)

% only update the trials table for hardware-backed parameters
if isa(P.Parent,'hw.Software')
    return
end

T = RUNTIME.TRIALS.trials;
loc = RUNTIME.TRIALS.writeParamIdx;

if isfield(loc, P.validName)
    [T{:,loc.(P.validName)}] = deal(newValue);
end

RUNTIME.TRIALS.trials = T;

end
