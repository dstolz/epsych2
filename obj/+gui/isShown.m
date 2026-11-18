function tf = isShown(h)
% tf = gui.isShown(h)
% False when graphics object H sits on a tab that is not the selected one
% of its tab group (at any depth), true otherwise.
%
% A display drawing into a hidden tab costs the redraw and shows nothing,
% so a per-trial display skips it while hidden and redraws when its tab is
% chosen (see gui.onShown). Figure visibility is not considered: a figure
% built hidden (a test, a screenshot) still draws.
%
% Parameters:
%   h - Graphics object (an axes, a panel, ...).
%
% Returns:
%   tf - Logical scalar.
%
% See also gui.onShown

tf = true;
if isempty(h) || ~isgraphics(h), return; end
p = h.Parent;
while ~isempty(p) && ~isa(p, 'matlab.ui.Figure')
    if isa(p, 'matlab.ui.container.Tab') && ~isempty(p.Parent) ...
            && isgraphics(p.Parent) && p.Parent.SelectedTab ~= p
        tf = false;
        return
    end
    p = p.Parent;
end
end
