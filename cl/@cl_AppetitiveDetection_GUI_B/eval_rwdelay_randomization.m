function [value,success] = eval_rwdelay_randomization(~,~,event,changedParam,p)
% [value,success] = eval_rwdelay_randomization(~,~,event,changedParam,p)
% This function is called whenever the Response Window Delay Min/Max parameter is changed, 
% does some basic error checking on the min and max values, and updates the RWDelayParameter Min/Max settings accordingly.

value = event.Value; % new value
success = true;
if isempty(p) || numel(p) ~= 3
    vprintf(0,1,'Error: Could not find parameters for Response Window Delay randomization')
    return
end

pMin   = p(1);
pMax   = p(2);
pDelay = p(3);

if changedParam == pMin
    A = event.Value;
    B = pMax.Value;
elseif changedParam == pMax
    A = pMin.Value;
    B = event.Value;
end


if A == B
    value = A; % if min and max are the same, just set to that value
    vprintf(3,'Response Window Delay Min and Max values are the same (%d ms), setting parameter to that value',A)
    return
end

if A > B
    value = event.PreviousValue; % reset to previous value if min is greater than max
    vprintf(0,1,'Response Window Delay Min value (%d ms) cannot be greater than Max value (%d ms)',A,B)
    return
end

if B < A
    value = event.PreviousValue; % reset to previous value if max is less than min
    vprintf(0,1,'Response Window Delay Max value (%d ms) cannot be less than Min value (%d ms)',B,A)
    return
end

if A < 0 || B < 0
    value = event.PreviousValue; % reset to previous value if either value is negative
    vprintf(0,1,'Response Window Delay values cannot be negative. Resetting to minimum of 0 ms.')
    return
end



try
    pDelay.Min = A;
    pDelay.Max = B;
    
    vprintf(3,'Randomized Response Window Delay range: %d-%d ms',A,B)
catch e
    vprintf(0,1,'Error randomizing Response Window Delay parameter: %s',getReport(e,'basic'))
    success = false;
end

end


