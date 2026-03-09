function eval_rwdelay_randomization(obj,src,event,RWDelayParameter)
% eval_rwdelay_randomization(obj,src,event,RWDelayParameter)
% This function is called whenever the Response Window Delay Min/Max parameter is changed, 
% and randomizes the value within the specified range.
% This function will also check that the min and max values are valid before attempting to randomize.

global RUNTIME

pMin = RUNTIME.HW.find_parameter('ResponseWindowDelayMin');
pMax = RUNTIME.HW.find_parameter('ResponseWindowDelayMax');

if isempty(pMin) || isempty(pMax) || isempty(RWDelayParameter)      
    vprintf(0,1,'Error: Could not find parameters for Response Window Delay randomization')
    return
end

if pMin.Value > pMax.Value
    pMin.Value = pMax.Value; % reset min to max if min is greater than max
    vprintf(0,1,'Response Window Delay Min value (%d ms) cannot be greater than Max value (%d ms)',pMin.Value,pMax.Value)
end

if pMax.Value < pMin.Value
    pMax.Value = pMin.Value; % reset max to min if max is less than min
    vprintf(0,1,'Response Window Delay Max value (%d ms) cannot be less than Min value (%d ms)',pMax.Value,pMin.Value)
end

if pMin.Value < 0 || pMax.Value < 0
    pMin.Value = max(pMin.Value,0);
    pMax.Value = max(pMax.Value,0);
    vprintf(0,1,'Response Window Delay values cannot be negative. Resetting to minimum of 0 ms.')
    return
end

if pMin.Value == pMax.Value
    RWDelayParameter.Value = pMin.Value; % if min and max are the same, just set to that value
    vprintf(3,'Response Window Delay Min and Max values are the same (%d ms), setting parameter to that value',pMin.Value)
    return
end



try
    newVal = randi([pMin.Value, pMax.Value]);
    RWDelayParameter.Value = newVal;
    vprintf(3,'Randomized Response Window Delay parameter to %d ms (range: %d-%d ms)',newVal,pMin.Value,pMax.Value)
catch e
    vprintf(0,1,'Error randomizing Response Window Delay parameter: %s',getReport(e,'basic'))
end

end


