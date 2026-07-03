function UpdateRecentConfigsMenu(self)
% UpdateRecentConfigsMenu(self)
% Rebuild the recent-config menu items at the bottom of the Config menu.
% Inputs
%   self (epsych.RunExpt) - Scalar RunExpt instance.
% Outputs
%   None.
% Notes
%   Menu items are sourced from GetRecentConfigs, which applies the seven-day
%   recent window and removes stale preference entries. Existing recent-config
%   items are identified by Tag so they can be cleared without disturbing the
%   other Config menu items.

if ~isfield(self.H,'mnu_config') || ~isgraphics(self.H.mnu_config)
    return
end

delete(findobj(allchild(self.H.mnu_config),'Tag','recent_config_item'))

recent = self.GetRecentConfigs;
if isempty(recent)
    return
end

sepState = {'off','on'};
for i = 1:numel(recent)
    [~, name, ext] = fileparts(recent{i});
    uimenu(self.H.mnu_config, ...
        'Tag','recent_config_item', ...
        'Separator',sepState{(i==1)+1}, ...
        'Label',sprintf('%d %s%s', i, name, ext), ...
        'MenuSelectedFcn', @(~,~) self.LoadRecentConfig(recent{i}));
end
