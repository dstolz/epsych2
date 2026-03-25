function [value,success] = eval_staircase_training_mode(obj,src,event,Parameter,options)
% [value,success] = eval_staircase_training_mode(obj,src,event,Parameter)
% [value,success] = eval_staircase_training_mode(obj,src,event,Parameter,Name=Value)
% Enable or disable staircase-training mode for a single hw.Parameter.
%
% This callback is intended for a state-button ValueChangedFcn. When
% enabled, it suspends Parameter.isRandom, opens or focuses a
% gui.StaircaseTraining window, and attaches a NewData listener that steps
% the parameter after selected trial outcomes. When disabled, it restores
% the previous randomisation state and removes the training GUI/listener.
%
% Inputs
%   obj - GUI controller exposing RUNTIME, StaircaseTrainingGUIs, and
%       StaircaseTrainingListeners.
%   src - gui.Parameter_Control to disable while training is active, or
%       [] to skip UI state changes.
%   event - Callback event whose Value field is the on/off toggle state.
%   Parameter - hw.Parameter adjusted by the staircase listener.
%
% Name-Value options
%   MinValue, MaxValue - Value clamp bounds passed to
%       gui.StaircaseTraining. Defaults use Parameter.Min/Max.
%   StepUp, StepDown - Positive step magnitudes passed to
%       gui.StaircaseTraining. Defaults are 350 and 100.
%   StepUpLimits, StepDownLimits - Two-element edit limits passed to
%       gui.StaircaseTraining. Defaults are [0 500].
%   MinValueLimits, MaxValueLimits - Two-element edit limits for the
%       staircase min/max controls.
%   StepUpResponse - Trial outcome that triggers an "up" step. Supported
%       values are "Hit", "Miss", "CorrectReject", "FalseAlarm", and
%       "Abort". The legacy spelling "CorrectRejct" is also accepted.
%   StepDownResponse - Trial outcome that triggers a "down" step. Uses the
%       same supported values as StepUpResponse.
%
% Returns
%   value - New toggle state copied from event.Value.
%   success - True when setup or teardown completes without error.
%
% See also gui.StaircaseTraining, documentation/StaircaseTraining.md,
% documentation/eval_staircase_training_mode.md

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
    options.StepUpResponse (1,1) string {mustBeMember(options.StepUpResponse,["Hit","Miss","CorrectReject","CorrectReject","FalseAlarm","Abort"])} = "Hit"
    options.StepDownResponse (1,1) string {mustBeMember(options.StepDownResponse,["Hit","Miss","CorrectReject","CorrectReject","FalseAlarm","Abort"])} = "Abort"
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
                @(src,ev) update_staircase_training(src, ev, h, RUNTIME, ...
                options.StepUpResponse, options.StepDownResponse));
            obj.StaircaseTrainingGUIs(pName) = h;
        end

        if ~isempty(src)
            src.h_uiobj.Enable = 'off';
        end
        success = true;

    else
        vprintf(2,'Closing %s Training GUI',pName)

        Parameter.isRandom = Parameter.UserData.isRandom;

        if obj.StaircaseTrainingGUIs.isKey(pName)
            delete(obj.StaircaseTrainingGUIs(pName));
            remove(obj.StaircaseTrainingGUIs, pName);
        end

        if ~isempty(src)
            src.h_uiobj.Enable = 'on';
        end

        if obj.StaircaseTrainingListeners.isKey(pName)
            delete(obj.StaircaseTrainingListeners(pName));
            remove(obj.StaircaseTrainingListeners, pName);
        end

        success = true;
    end

catch e
    vprintf(0,1,'Error in %s Training Mode: %s',pName,getReport(e,'basic'))
    if ~isempty(src)
        src.h_uiobj.Enable = 'on';
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


function update_staircase_training(~,~,h,RUNTIME,stepUpResponse,stepDownResponse)
% update_staircase_training(~,~,h,RUNTIME,stepUpResponse,stepDownResponse)
% Step the training parameter after matching trial outcomes.
%
% This NewData listener decodes the most recent response code and compares
% it against the configured StepUpResponse and StepDownResponse values.
% Matching trials step the parameter "up" or "down". Non-matching trials
% are ignored. For hardware-backed parameters (parent is not hw.Software),
% the updated value is also mirrored into RUNTIME.TRIALS.trials.
%
% Inputs
%   h - gui.StaircaseTraining instance managing the target parameter.
%   RUNTIME - Runtime state containing TRIALS.DATA, TRIALS.trials, and
%       TRIALS.writeParamIdx.
%   stepUpResponse - Trial outcome name that maps to an "up" step.
%   stepDownResponse - Trial outcome name that maps to a "down" step.

if isempty(h) || ~isvalid(h), return; end
if isempty(RUNTIME.TRIALS.DATA), return; end

RC = epsych.BitMask.decode(RUNTIME.TRIALS.DATA(end).RespCode);
if RC.(stepUpResponse)
    s = "up";
elseif RC.(stepDownResponse)
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


