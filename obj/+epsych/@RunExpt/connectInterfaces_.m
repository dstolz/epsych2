function connectInterfaces_(self, interfaces)
% connectInterfaces_(self, interfaces)
% Connect every interface the session needs, offering the operator a way out
% of a failure that is theirs to fix.
%
% A peripheral nobody switched on, or a USB-serial adapter that renumbered
% when it moved sockets, used to end the whole command in
% HardwareInitializationFailed with the protocol's port still wrong — the
% operator's only recourse being to edit the protocol in ProtocolDesigner and
% start over. Backends that can describe a fix (hw.Interface.recoverConnection,
% e.g. hw.NE1000's port picker) now get to offer it in place, and those a
% session can run without (hw.Interface.canRunOffline) can be left offline.
%
% Interfaces are connected here rather than by epsych.Runtime.Interfaces so
% that this dialog is not run from inside a property setter; the setter's own
% loop then finds them already connected and passes over them.
%
% Throws epsych:RunExpt:HardwareConnectionCancelled when the operator cancels,
% having first disconnected whatever this call had connected — a session that
% is not starting must not leave half the rig live.
%
% See also: hw.Interface.recoverConnection, hw.Interface.canRunOffline,
%           epsych.Runtime.Interfaces

connectedHere = hw.Interface.empty(1, 0);

for p = interfaces(:).'
    % A decision to run without this backend belongs to one run only; the
    % pump may well have been switched on since.
    p.RunOffline = false;

    % An interface left connected by an earlier command is not this call's to
    % tear down if the operator later cancels.
    wasConnected = p.IsConnected;

    settled = false;
    while ~settled
        [ok, ME] = local_tryConnect_(p);
        if ok
            if ~wasConnected
                connectedHere(end+1) = p;
            end
            break
        end

        vprintf(0, 1, ME);

        % Loop on the prompt: cancelling the recovery dialog returns here
        % rather than costing another connect attempt (a serial timeout is
        % seconds long, and nothing about the rig has changed).
        decided = false;
        while ~decided
            switch self.promptConnectFailure_(p, ME)
                case "recover"
                    decided = p.recoverConnection(self.H.figure1);

                case "retry"
                    decided = true;

                case "offline"
                    p.RunOffline = true;
                    vprintf(0, 1, ['%s will run OFFLINE for this session by operator choice: ' ...
                        'it will accept no commands and report its last known values'], class(p));
                    self.setStatus(sprintf('%s is offline for this session.', ...
                        p.displayLabel()), 'the session will run without it.');
                    decided = true;
                    settled = true;

                case "cancel"
                    local_rollback_(connectedHere);
                    error('epsych:RunExpt:HardwareConnectionCancelled', ...
                        '%s could not be connected, and starting was cancelled.', p.displayLabel());
            end
        end
    end
end
end


function [ok, ME] = local_tryConnect_(p)
% Attempt one connection, reporting a backend that fails silently as an
% error of its own: Runtime.Interfaces asserts on exactly this case, and the
% operator needs something to act on either way.
ME = MException.empty;
try
    if ~p.IsConnected
        p.connect();
    end
    ok = p.IsConnected;
    if ~ok
        ME = MException('epsych:RunExpt:HardwareConnectionFailed', ...
            'The interface reported no connection after connect() returned.');
    end
catch ME
    ok = false;
end
end


function local_rollback_(connectedHere)
% Release the interfaces this call connected. Best effort: a teardown that
% throws must not replace the cancellation the operator asked for.
for p = connectedHere(:).'
    try
        p.disconnect();
    catch ME
        vprintf(0, 1, ME);
    end
end
end
