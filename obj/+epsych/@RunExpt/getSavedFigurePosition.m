function position = getSavedFigurePosition(defaultPosition)
% position = getSavedFigurePosition(defaultPosition)
% Return the saved RunExpt window rectangle, or defaultPosition when invalid.

arguments
    defaultPosition (1,4) double
end

position = getpref('RunExpt','FigurePosition',defaultPosition);

if ~isnumeric(position) || numel(position) ~= 4 || any(~isfinite(position))
    position = defaultPosition;
end

position = double(reshape(position,1,[]));
end