function UpdateRecentConfigsMenu(self)
% UpdateRecentConfigsMenu(self)
% Rebuild the items in the Config > Recent Configs submenu.
% Inputs
%   self (epsych.RunExpt) - Scalar RunExpt instance.
% Outputs
%   None.
% Notes
%   Menu items are sourced from GetRecentConfigs, which applies the seven-day
%   recent window and removes stale preference entries. When that leaves
%   nothing, a disabled placeholder keeps the submenu discoverable instead of
%   letting the entry point disappear.

if ~isfield(self.H,'mnu_recent_configs') || ~isgraphics(self.H.mnu_recent_configs)
    return
end

delete(allchild(self.H.mnu_recent_configs))

recent = self.GetRecentConfigs;

if isempty(recent)
    uimenu(self.H.mnu_recent_configs, ...
        'Tag','recent_config_placeholder', ...
        'Label','(none in the past 7 days)', ...
        'Enable','off');
    return
end

for i = 1:numel(recent)
    [~, name, ext] = fileparts(recent{i});
    uimenu(self.H.mnu_recent_configs, ...
        'Tag','recent_config_item', ...
        'Label',sprintf('&%d %s%s', i, name, ext), ...
        'Tooltip',recent{i}, ...
        'MenuSelectedFcn', @(~,~) self.LoadRecentConfig(recent{i}));
end

uimenu(self.H.mnu_recent_configs, ...
    'Tag','recent_config_clear', ...
    'Label','Clear List', ...
    'Separator','on', ...
    'MenuSelectedFcn', @(~,~) self.ClearRecentConfigs);
