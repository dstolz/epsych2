function [value,success] = eval_parameter_randomization(~,~,event,changedParam,context)
% [value,success] = eval_parameter_randomization(~,~,event,changedParam,context)
% Validate and apply randomized min/max bounds for a parameter.
%
% This evaluator supports two calling patterns:
%   1) context = [pMin pMax pTarget]
%   2) context = RUNTIME, where the paired parameters are resolved from the
%      edited parameter name (for example StimDelayMin/StimDelayMax -> StimDelay).
%
% Parameters:
%   event - Callback event data with Value and PreviousValue.
%   changedParam - Parameter edited by the UI control.
%   context - Parameter triplet or runtime object used to resolve them.
%
% Returns:
%   value - Value to keep in the edited UI control.
%   success - True when the randomized parameter bounds were updated.

value = event.Value;
success = true;

try
    [pMin,pMax,pTarget] = resolve_randomization_parameters(changedParam,context);
catch ME
    vprintf(0,1,'Error resolving randomized parameter for "%s": %s', ...
        changedParam.Name,getReport(ME,'basic'))
    value = event.PreviousValue;
    success = false;
    return
end

if changedParam == pMin
    minValue = event.Value;
    maxValue = pMax.Value;
elseif changedParam == pMax
    minValue = pMin.Value;
    maxValue = event.Value;
else
    vprintf(0,1,'Error: changed parameter "%s" is not a randomized min/max control.',changedParam.Name)
    value = event.PreviousValue;
    success = false;
    return
end

parameterLabel = pTarget.validName;
if isempty(pTarget.Unit)
    unitSuffix = '';
else
    unitSuffix = [' ' pTarget.Unit];
end

if minValue > maxValue
    vprintf(0,1,'%s Min value (%g%s) cannot be greater than Max value (%g%s)', ...
        parameterLabel,minValue,unitSuffix,maxValue,unitSuffix)
    value = event.PreviousValue;
    return
end

if minValue < pMin.Min || maxValue > pMax.Max
    vprintf(0,1,'%s randomized range must remain within [%g %g]%s', ...
        parameterLabel,pMin.Min,pMax.Max,unitSuffix)
    value = event.PreviousValue;
    return
end

try
    pTarget.Min = minValue;
    pTarget.Max = maxValue;

    if minValue == maxValue
        vprintf(3,'%s Min and Max are the same (%g%s); using a fixed value.', ...
            parameterLabel,minValue,unitSuffix)
    else
        vprintf(3,'Randomized %s range: %g to %g%s', ...
            parameterLabel,minValue,maxValue,unitSuffix)
    end
catch ME
    vprintf(0,1,'Error randomizing %s parameter: %s',parameterLabel,getReport(ME,'basic'))
    value = event.PreviousValue;
    success = false;
end

end


function [pMin,pMax,pTarget] = resolve_randomization_parameters(changedParam,context)
if isa(context,'hw.Parameter') && numel(context) == 3
    pMin = context(1);
    pMax = context(2);
    pTarget = context(3);
    return
end

parameterBaseName = extractBefore(changedParam.Name,'Min');
isMinControl = true;
if strlength(parameterBaseName) == 0
    parameterBaseName = extractBefore(changedParam.Name,'Max');
    isMinControl = false;
end

if strlength(parameterBaseName) == 0
    error('Unable to infer randomized parameter name from "%s".',changedParam.Name)
end

runtime = context;
pMin = runtime.S.Module.find_parameter(char(parameterBaseName) + "Min");
pMax = runtime.S.Module.find_parameter(char(parameterBaseName) + "Max");
pTarget = runtime.HW.find_parameter(char(parameterBaseName));

if isempty(pMin) || isempty(pMax) || isempty(pTarget)
    error('Could not resolve randomized parameter triplet for "%s".',changedParam.Name)
end

if isMinControl && changedParam ~= pMin
    pMin = changedParam;
elseif ~isMinControl && changedParam ~= pMax
    pMax = changedParam;
end
end