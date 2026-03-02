function [value,success] = eval_rwdelay(obj,src,event)
% [value,success] = eval_rwdelay(obj,src,event)
%
% implements the 'EvaluatorFcn' function
success = true;

try
    % first find all gui objects we want to evaluate
    h = findobj(obj.h_uiobj,'Tag','RespWinDelayRange');

    if isempty(h), return; end % can happen during setup

    m = event.Value; % new mean
    r = h.Value; % new range
        
    value = m + randi([-r r]);
    value = max(0,value); % ensure non-negative response window delay

catch e
    success = false;
    value = event.PreviousValue; % return to previous value
    vprintf(0,1,'Error evaluating Response Window Delay: %s',getReport(e,'basic'))
end

