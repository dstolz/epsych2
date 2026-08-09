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

% Floor the height: below this the right-side button stack outgrows its row
% and 'Save Data' is clipped. Positions stored by earlier versions were saved
% before the status bar took a row, so a saved height is raised rather than
% trusted.
MIN_HEIGHT = 260;
position(4) = max(position(4), MIN_HEIGHT);
end