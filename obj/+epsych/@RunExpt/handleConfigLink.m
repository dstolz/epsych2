function handleConfigLink(url)
% epsych.RunExpt.handleConfigLink(url)
% Entry point invoked (via the MATLAB Automation Server) by the OS handler
% that is registered for the "epsych://" URL protocol. Decodes the config
% path from the link, brings up or reuses the RunExpt session, and loads the
% configuration without interrupting a running experiment.
%
% Parameters:
%   url - The full "epsych://load?config=<base64url>" link string passed by
%         the OS handler script (helpers/url/epsych_url_handler.vbs).
%
% See also: epsych.RunExpt.parseConfigURL, epsych.RunExpt.loadConfigFromLink,
%           epsych.RunExpt.registerURLProtocol
arguments
    url (1,1) string
end

configPath = epsych.RunExpt.parseConfigURL(url);
if strlength(configPath) == 0
    vprintf(0,1,'Ignoring epsych:// link with no config token: %s', url);
    return
end

vprintf(1,'Received epsych:// link requesting config: ''%s''', configPath);

% Reuse an open RunExpt window if present, otherwise create one. MATLAB is
% already running (the link reached us through the automation server), so
% opening the GUI here is expected and cheap.
app = epsych.RunExpt(BringToFront=true);
app.loadConfigFromLink(configPath);
