function UpdateRecentConfigsMenu(self)
% UpdateRecentConfigsMenu(self)
% Rebuild the recent-config submenu from persisted recent entries.
% Inputs
%   self (epsych.RunExpt) - Scalar RunExpt instance.
% Outputs
%   None.
% Notes
%   Menu items are sourced from GetRecentConfigs, which applies the seven-day
%   recent window and removes stale preference entries.

if ~isfield(self.H,'mnu_recent_configs') || ~isgraphics(self.H.mnu_recent_configs)
    return
end

delete(allchild(self.H.mnu_recent_configs))

recent = self.GetRecentConfigs;
if isempty(recent)
    uimenu(self.H.mnu_recent_configs,'Label','(none)','Enable','off');
    self.H.mnu_recent_configs.Enable = 'off';
    return
end

self.H.mnu_recent_configs.Enable = 'on';
for i = 1:numel(recent)
    [~, name, ext] = fileparts(recent{i});
    uimenu(self.H.mnu_recent_configs, ...
        'Label',sprintf('%d %s%s', i, name, ext), ...
        'MenuSelectedFcn', @(~,~) self.LoadRecentConfig(recent{i}));
end