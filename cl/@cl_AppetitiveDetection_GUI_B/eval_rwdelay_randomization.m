function eval_rwdelay_randomization(obj,src,value)
% eval_rwdelay_randomization(~,~,event,RWDelayParameter)
% This function is called whenever the Response Window Delay Min/Max parameter is changed, 
% and randomizes the value within the specified range.
% This function will also check that the min and max values are valid before attempting to randomize.

global RUNTIME


pMin = RUNTIME.S.find_parameter('RespWinDelayMin');
pMax = RUNTIME.S.find_parameter('RespWinDelayMax');

RWDelayParameter = RUNTIME.HW.find_parameter('RespWinDelay');

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
end

if pMin.Value == pMax.Value
    RWDelayParameter.Value = pMin.Value; % if min and max are the same, just set to that value
    vprintf(3,'Response Window Delay Min and Max values are the same (%d ms), setting parameter to that value',pMin.Value)
    return
end



try
    RWDelayParameter.Min = pMin.Value;
    RWDelayParameter.Max = pMax.Value;
    RWDelayParameter.isRandom = true; % enable randomization for this parameter
    idx=RUNTIME.TRIALS.writeParamIdx.RespWinDelay;
    RUNTIME.TRIALS.trials(:,idx) = {RWDelayParameter.Value}; % update the trial structure with the new randomized values for this parameter
    vprintf(3,'Randomized Response Window Delay range: %d-%d ms',pMin.Value,pMax.Value)
catch e
    vprintf(0,1,'Error randomizing Response Window Delay parameter: %s',getReport(e,'basic'))
end

end


