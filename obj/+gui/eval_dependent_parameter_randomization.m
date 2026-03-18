function [value,success] = eval_dependent_parameter_randomization(src,event,changedParam,p)
% [value,success] = eval_dependent_parameter_randomization(src,event,changedParam,p)
% Validate and apply randomized min/max bounds for a parameter.
%
% Parameters:
%   event - Callback event data with Value and PreviousValue.
%   changedParam - Parameter edited by the UI control.
%   p - Parameter triplet ordered as [pMin pMax pTarget].
%
% Returns:
%   value - Value to keep in the edited UI control.
%   success - True when the randomized parameter bounds were updated.

value = event.Value;
success = true;

if isempty(p) || numel(p) ~= 3
    vprintf(0,1,'Error: expected [pMin pMax pTarget] for randomized parameter evaluation.')
    value = event.PreviousValue;
    success = false;
    return
end

pMin = p(1);
pMax = p(2);
pTarget = p(3);

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
    % update the randomized parameter's bounds based on the edited min/max values
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