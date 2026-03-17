function c = directionColors_(obj, direction)
% c = directionColors_(obj, direction)
% Map step directions to RGB colors.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%   direction — numeric vector (positive=up, negative=down) or string labels
%
% Returns:
%   c — Nx3 RGB colors

n = numel(direction);
c = repmat(obj.NeutralColor, n, 1);

if n == 0
    return
end

if isstring(direction) || ischar(direction)
    direction = string(direction);
    isUp = lower(direction) == "up";
    isDown = lower(direction) == "down";
else
    isUp = direction > 0;
    isDown = direction < 0;
end

c(isUp,:) = repmat(obj.StepColor, nnz(isUp), 1);
c(isDown,:) = repmat(obj.LineColor, nnz(isDown), 1);
