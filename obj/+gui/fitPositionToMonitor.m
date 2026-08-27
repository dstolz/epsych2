function position = fitPositionToMonitor(position, monitors)
% position = gui.fitPositionToMonitor(position [, monitors])
% Clamp a saved figure rectangle onto the monitor it was last on.
%
% This is the replacement for movegui(fig,'onscreen') on the restore path.
% movegui picks its reference monitor from the FIRST corner of the window it
% finds strictly inside a monitor rectangle, so a window the operator left
% hanging a little off the bottom or the side of a secondary monitor is
% attributed to whichever neighbour a stray corner touched — usually the
% primary — and then clamped onto it. The window reopens on the wrong
% monitor. Choosing by overlap AREA instead cannot be fooled that way: the
% monitor holding most of the window is the monitor it was on.
%
%  position - [x y w h] in pixels, MATLAB screen coordinates.
%  monitors - Nx4 monitor rectangles to fit against. Defaults to the
%             attached displays; supplied only by the smoke test, since
%             MonitorPositions is read-only and the arrangements worth
%             testing are the ones nobody has plugged in.
%
% Returns
%   position - the same rectangle when it already fits on its monitor
%              (an unchanged monitor layout restores exactly), otherwise the
%              nearest rectangle that fits on that monitor.
%
% A window whose monitor is gone — unplugged, or a laptop off its dock —
% has no overlap anywhere and falls back to the primary display, which is
% the only screen certain to exist.
%
% See also: gui.BehaviorGUI.getSavedFigurePosition, movegui

arguments
    position (1,4) double
    monitors (:,4) double = localMonitors()
end

% Room kept above the window for its title bar: Windows will not let an
% operator drag a title bar off the top of a screen, so a rectangle that was
% legitimately placed already satisfies this and is left alone. It matters
% only when clamping a window that would otherwise reopen ungrabbable.
TITLE_BAR = 30;

if isempty(monitors), return; end   % headless or unreadable; leave it alone

% Overlap area against each monitor. The window's own monitor keeps most of
% it even when an edge hangs off, which is exactly the case movegui loses.
overlap = zeros(size(monitors, 1), 1);
for k = 1:numel(overlap)
    w = min(position(1) + position(3), monitors(k,1) + monitors(k,3)) ...
        - max(position(1), monitors(k,1));
    h = min(position(2) + position(4), monitors(k,2) + monitors(k,4)) ...
        - max(position(2), monitors(k,2));
    overlap(k) = max(w, 0) * max(h, 0);
end

[best, k] = max(overlap);
if best <= 0, k = 1; end            % that monitor is gone; primary is not
mon = monitors(k,:);

% Shrink before moving: a window wider or taller than the monitor cannot be
% placed on it at all, and its size is worth less than being reachable.
position(3) = min(position(3), mon(3));
position(4) = min(position(4), mon(4) - TITLE_BAR);

position(1) = min(max(position(1), mon(1)), mon(1) + mon(3) - position(3));
position(2) = min(max(position(2), mon(2)), ...
    mon(2) + mon(4) - position(4) - TITLE_BAR);
end


function monitors = localMonitors()
% Monitor rectangles in pixels, or empty when they cannot be trusted.
monitors = [];
try
    oldUnits = get(0, 'Units');
    c = onCleanup(@() set(0, 'Units', oldUnits));
    set(0, 'Units', 'pixels');
    m = get(0, 'MonitorPositions');
catch
    return
end
if ~isnumeric(m) || isempty(m) || size(m, 2) ~= 4 || any(~isfinite(m(:)))
    return
end
% A headless session reports a placeholder screen; clamping a real window
% into it would be worse than leaving the position alone.
m = m(m(:,3) > 1 & m(:,4) > 1, :);
if isempty(m), return; end
monitors = double(m);
end
