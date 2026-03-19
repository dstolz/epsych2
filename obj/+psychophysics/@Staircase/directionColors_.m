function c = directionColors_(obj, direction)
% c = directionColors_(obj, direction)
% Map step directions to hex colors.
%
% Parameters:
%   obj — psychophysics.Staircase instance
%   direction — numeric vector (positive=up, negative=down) or string labels
%
% Returns:
%   c — Nx1 string array of hex colors

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

c(isUp) = obj.StepColor;
c(isDown) = obj.LineColor;
