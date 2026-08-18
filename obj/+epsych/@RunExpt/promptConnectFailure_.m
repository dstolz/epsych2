function action = promptConnectFailure_(self, iface, ME)
% action = promptConnectFailure_(self, iface, ME)
% Ask the operator what to do about an interface that would not connect.
%
% Returns one of:
%   "recover" - run the backend's own fix (hw.Interface.recoverConnection)
%   "retry"   - try connecting again as-is, for something fixed at the rig
%   "offline" - run the session with this backend disconnected
%   "cancel"  - abandon the command
%
% Only the choices a backend actually supports are offered, so an interface
% that declares neither recovery nor offline operation shows the Retry/Cancel
% pair — the same two outcomes as before, minus having to restart the command
% to get at the first one. uiconfirm renders at most four buttons, which is
% exactly what a fully-capable backend asks for.
%
% See also: connectInterfaces_, hw.Interface.connectionRecoveryLabel

label = iface.displayLabel();

recoverLabel = iface.connectionRecoveryLabel();
offlineLabel = 'Continue Without It';

opts = {};
if ~isempty(recoverLabel)
    opts{end+1} = recoverLabel;
end
opts{end+1} = 'Retry';
if iface.canRunOffline()
    opts{end+1} = offlineLabel;
end
opts{end+1} = 'Cancel';

msg = sprintf('%s could not be connected:\n\n%s\n\n', label, ME.message);
if iface.canRunOffline()
    % Spelled out because the consequence is silent: nothing downstream
    % errors, the session simply runs with that device doing nothing.
    msg = [msg sprintf(['Fix it at the rig and Retry, or continue without it — the session ' ...
        'will run normally but %s will accept no commands for its duration.'], label)];
else
    msg = [msg 'Fix it at the rig and Retry, or cancel and start again.'];
end

fig = self.H.figure1;
ontop = self.AlwaysOnTop(false);
% Option 1 is whatever the backend can actually do about it — its own fix
% when it has one, Retry otherwise. Continuing without the device is never
% the default: it has to be chosen deliberately.
sel = uiconfirm(fig, msg, 'EPsych — Hardware Connection', ...
    'Options', opts, 'DefaultOption', 1, ...
    'CancelOption', numel(opts), 'Icon', 'warning');
self.AlwaysOnTop(ontop);

switch sel
    case recoverLabel
        action = "recover";
    case 'Retry'
        action = "retry";
    case offlineLabel
        action = "offline";
    otherwise
        action = "cancel";
end
end
