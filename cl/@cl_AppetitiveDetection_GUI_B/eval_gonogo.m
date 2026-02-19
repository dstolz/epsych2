function [value,success] = eval_gonogo(obj,src,event)
% [value,success] = eval_gonogo(obj,src,event)
%
% implements the 'EvaluatorFcn' function
success = true;

value = event.Value; % new value

% first find all gui objects we want to evaluate
h = ancestor(src.parent,'figure','toplevel');
h = findall(h,'-property','tag');
if isempty(h), return; end


isMin = endsWith(src.Name,'_min');

if isMin
    i = endsWith(get(h,'Tag'),'ConsecutiveNOGO_max');
else
    i = endsWith(get(h,'Tag'),'ConsecutiveNOGO_min');
end
h = h(i);

if isempty(h), return; end % can happen during setup

% the handle to the Parameter object is included in the gui object's
% UserData

if isMin
    success = h.Value >= value;
else
    success = h.Value <= value;
end


if ~success
    value = event.PreviousValue; % return to previous value
    vprintf(0,1,'Max NoGo trials can''t be lower than Min NoGo trials')
end
