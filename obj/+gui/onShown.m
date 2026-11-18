function L = onShown(h, fcn)
% L = gui.onShown(h, fcn)
% Call FCN whenever a tab group holding graphics object H changes its
% selected tab -- clicked, or set from code -- so a display that skipped
% its redraws while hidden (gui.isShown) can catch up when it is shown.
%
% Listeners rather than the tab group's SelectionChangedFcn: that callback
% is a single slot the GUI that built the tabs owns, and taking it would
% silently disconnect whatever the GUI put there.
%
% Parameters:
%   h   - Graphics object (an axes, a panel, ...).
%   fcn - Function handle taking no arguments. Called on every selection
%         change of every tab group above H; check gui.isShown inside it.
%
% Returns:
%   L - event.listener array, empty when H is in no tab group. The caller
%       owns it and deletes it with the display.
%
% See also gui.isShown

L = event.listener.empty(1, 0);
if isempty(h) || ~isgraphics(h), return; end

% The tab groups above H, nearest first.
groups = gobjects(1, 0);
p = h.Parent;
while ~isempty(p) && ~isa(p, 'matlab.ui.Figure')
    if isa(p, 'matlab.ui.container.TabGroup')
        groups = [groups, p];
    end
    p = p.Parent;
end

pairs = cell(1, numel(groups));
for k = 1:numel(groups)
    pairs{k} = [listener(groups(k), 'SelectionChanged', @(~,~) fcn()), ...
                listener(groups(k), 'SelectedTab', 'PostSet', @(~,~) fcn())];
end
L = [L, pairs{:}];
end
