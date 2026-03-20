function [value,success] = eval_dependent_parameter_randomization(src,event,changedParam,pMin,pMax,pTarget)
% [value,success] = eval_dependent_parameter_randomization(src,event,changedParam,pMin,pMax,pTarget)
% Validate and apply randomized min/max bounds for a parameter.
%
% Parameters:
%   src - Parameter control that invoked the evaluator.
%   event - Callback event data with Value and PreviousValue.
%   changedParam - Parameter edited by the UI control.
%   pMin, pMax, pTarget - Randomized range parameters for the edited
%       minimum, maximum, and target randomized parameter.
%
% Returns:
%   value - Value to keep in the edited UI control.
%   success - True when the randomized parameter bounds were updated.

arguments
    src (1,1) gui.Parameter_Control
    event (1,1) struct
    changedParam (1,1) hw.Parameter
    pMin (1,1) hw.Parameter
    pMax (1,1) hw.Parameter
    pTarget (1,1) hw.Parameter
end

value = event.Value;
success = true;
controlName = src.Name;

if changedParam == pMin
    minValue = event.Value;
    maxValue = pMax.Value;
elseif changedParam == pMax
    minValue = pMin.Value;
    maxValue = event.Value;
else
    vprintf(0,1,'Error: control "%s" changed parameter "%s", which is not a randomized min/max control.', ...
        controlName,changedParam.Name)
    value = event.PreviousValue;
    success = false;
    return
end

parameterLabel = pTarget.validName;

if minValue > maxValue
    vprintf(0,1,'%s Min value (%g%s) cannot be greater than Max value (%g %s)', ...
        parameterLabel,minValue,pTarget.Unit,maxValue,pTarget.Unit)
    value = event.PreviousValue;
    return
end

if minValue < pMin.Min || maxValue > pMax.Max
    vprintf(0,1,'%s randomized range must remain within [%g %g] %s', ...
        parameterLabel,pMin.Min,pMax.Max,pTarget.Unit)
    value = event.PreviousValue;
    return
end

try
    % update the randomized parameter's bounds based on the edited min/max values
    pTarget.Min = minValue;
    pTarget.Max = maxValue;

    if minValue == maxValue
        vprintf(3,'%s Min and Max are the same (%g%s); using a fixed value.', ...
            parameterLabel,minValue,pTarget.Unit)
    else
        vprintf(3,'Randomized %s range: %g to %g%s', ...
            parameterLabel,minValue,maxValue,pTarget.Unit)
    end
catch ME
    vprintf(0,1,'Error randomizing %s parameter: %s',parameterLabel,getReport(ME,'basic'))
    value = event.PreviousValue;
    success = false;
end

end