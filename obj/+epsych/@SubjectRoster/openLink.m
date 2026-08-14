function openLink(url)
% openLink(url)
% epsych.SubjectRoster.openLink(url)
% Open a project link in the default browser, or a local folder in the file
% manager.
%
% The address is validated here as well as on the way in, rather than trusting
% what is stored: a roster written by an older build, or edited by hand, reaches
% this point unchecked, and this is the moment something would actually run.
%
% Parameters:
%   url - address from a project's Links array.
%
% Throws:
%   epsych:SubjectRoster:UnsafeLink
%
% See also: epsych.SubjectRoster.isSafeUrl, gui.SubjectManager
arguments
    url (1,:) char
end

[ok, why, url] = epsych.SubjectRoster.isSafeUrl(url);
if ~ok
    error('epsych:SubjectRoster:UnsafeLink', '%s', why);
end

local = localPathFromFileUrl(url);
if ~isempty(local) && isfolder(local)
    % web() renders a folder as an unhelpful directory listing or nothing at
    % all, so a folder goes to the platform's file manager instead.
    if ispc
        winopen(local);
    elseif ismac
        system(sprintf('open "%s" &', local));
    else
        system(sprintf('xdg-open "%s" &', local));
    end
    vprintf(2, 'Opened folder: %s', local);
    return
end

web(url, '-browser');
vprintf(2, 'Opened link: %s', url);

end

% -----------------------------------------------------------------------
function pth = localPathFromFileUrl(url)
% file URL -> native path, or '' when the address is not a file URL.
pth = '';
if ~strncmpi(url, 'file:', 5), return, end

p = strrep(url(6:end), '%20', ' ');
if strncmp(p, '///', 3)
    pth = p(4:end);
elseif strncmp(p, '//', 2)
    pth = ['\\' p(3:end)];
else
    return
end

if ispc
    pth = strrep(pth, '/', '\');
end
end
