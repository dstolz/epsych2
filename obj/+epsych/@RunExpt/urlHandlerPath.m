function p = urlHandlerPath()
% p = epsych.RunExpt.urlHandlerPath()
% Absolute path to the OS handler script for the "epsych://" URL protocol,
% resolved from the current EPsych repository location. Returns "" if the
% repository root cannot be located.
%
% See also: epsych.RunExpt.registerURLProtocol

root = fileparts(which('epsych_startup'));
if isempty(root)
    p = "";
    return
end
p = string(fullfile(root, 'helpers', 'url', 'epsych_url_handler.vbs'));
