function [value,success] = eval_staircase_training_mode(obj,src,event,Parameter,options)
% [value,success] = eval_staircase_training_mode(obj,src,event,Parameter)
% [value,success] = eval_staircase_training_mode(obj,src,event,Parameter,Name,Value)
%
% Toggle staircase training mode for any hw.Parameter. Intended as a
% ValueChangedFcn callback for a state button. When enabled, randomisation
% is suspended, a gui.StaircaseTraining window is opened, and a NewData
% listener adjusts the parameter on each trial outcome. When disabled, the
% previous random state is restored and the GUI/listener are torn down.
%
% If src is a gui.Parameter_Control, its UI widget is disabled while
% training mode is active and re-enabled on close. Pass [] to skip.
%
%   obj       - GUI controller (must expose obj.RUNTIME,
%               obj.StaircaseTrainingGUIs, obj.StaircaseTrainingListeners).
%   src       - gui.Parameter_Control to disable during training, or [].
%   event     - Callback event; event.Value is logical on/off toggle.
%   Parameter - hw.Parameter whose value the staircase adjusts.
%
% Name-Value options (forwarded to gui.StaircaseTraining):
%   MinValue, MaxValue       - Value clamp bounds (default: Parameter.Min/Max).
%   StepUp, StepDown         - Step magnitudes (default: 350, 100).
%   StepUpLimits, StepDownLimits   - Two-element limit vectors (default: [0 500]).
%   MinValueLimits, MaxValueLimits - Two-element limit vectors.
%
%   value   - New toggle state (event.Value).
%   success - True when the callback completes without error.
%
% See also gui.StaircaseTraining, documentation/StaircaseTraining.md

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


function update_staircase_training(~,~,h,RUNTIME)
% update_staircase_training(src,event,h,RUNTIME)
%
% NewData listener callback that steps the staircase parameter after each
% trial. Hit responses step "up"; Abort responses step "down"; all other
% codes are ignored. For hardware-backed parameters (parent is not
% hw.Software), the new value is also written into RUNTIME.TRIALS.trials.
%
%   h       - gui.StaircaseTraining instance managing the parameter.
%   RUNTIME - Runtime state (TRIALS.DATA, TRIALS.trials, TRIALS.writeParamIdx).

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
