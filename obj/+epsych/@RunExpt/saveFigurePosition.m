function saveFigurePosition(position)
% saveFigurePosition(position)
% Persist the RunExpt window rectangle when position is a valid 4-element vector.

if ~isnumeric(position) || numel(position) ~= 4 || any(~isfinite(position))
    return
end

setpref('RunExpt','FigurePosition',double(reshape(position,1,[])));
end