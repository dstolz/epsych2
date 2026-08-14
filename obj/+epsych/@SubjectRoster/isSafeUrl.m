function [tf, why, url] = isSafeUrl(candidate)
% [tf, why, url] = epsych.SubjectRoster.isSafeUrl(candidate)
% True when candidate is an address this toolbox is willing to open.
%
% A roster is a shared file, often on a network drive, and a link in it is
% therefore untrusted input: 'matlab:!del /q ...' typed into a project by one
% person would run on every rig that clicks it. Only schemes that can do
% nothing but navigate are accepted -- http, https, mailto, file -- so an .esub
% file can never become executable.
%
% Two conveniences, because they are what an operator actually pastes:
% a bare host ('elog.lab.edu/study') gains https://, and a local or UNC path
% ('\\nas\logs') is rewritten as a file URL.
%
% Parameters:
%   candidate - the address as typed or as stored.
%
% Returns:
%   tf  - logical scalar.
%   why - char explanation when tf is false, '' otherwise.
%   url - the normalized address; unchanged from candidate when tf is false.
%
% Examples:
%   epsych.SubjectRoster.isSafeUrl('docs.google.com/x')  % -> https://docs...
%   epsych.SubjectRoster.isSafeUrl('matlab:rmdir(''.'')')% -> false
%
% See also: epsych.SubjectRoster.openLink, epsych.SubjectRoster.makeLink
arguments
    candidate (1,:) char
end

ALLOWED = {'http', 'https', 'mailto', 'file'};

tf  = false;
why = '';
url = strtrim(candidate);

if isempty(url)
    why = 'The link has no address.';
    return
end

% Paths are tested before schemes because a drive letter looks exactly like a
% one-character scheme: 'C:\logs' would otherwise parse as scheme 'c'.
isDrive = ~isempty(regexp(url, '^[A-Za-z]:[\\/]', 'once'));
isUNC   = strncmp(url, '\\', 2) || strncmp(url, '//', 2);
if isDrive || isUNC
    url = localFileUrl(url);
    tf  = true;
    return
end

scheme = regexp(url, '^([A-Za-z][A-Za-z0-9+.\-]*):', 'tokens', 'once');

if isempty(scheme)
    % A host has a dot in it before any slash. Anything else -- a bare word, a
    % sentence, a relative path -- is too ambiguous to guess at, and guessing
    % wrong would hand the operator a dead link that looks live.
    if isempty(regexp(url, '^[^\s/]+\.[^\s/]+', 'once'))
        why = sprintf(['"%s" is not an address. Use http://, https://, mailto:, ' ...
            'or a full file path.'], candidate);
        return
    end
    url = ['https://' url];
    tf  = true;
    return
end

scheme = lower(scheme{1});
if ~ismember(scheme, ALLOWED)
    why = sprintf(['Links may only use %s. "%s:" is refused because a roster is a ' ...
        'shared file, and an address that runs code would run it on every rig ' ...
        'that opens the project.'], strjoin(ALLOWED, ', '), scheme);
    return
end

tf = true;

end

% -----------------------------------------------------------------------
function url = localFileUrl(pth)
% Local or UNC path -> file URL. Spaces are escaped because a raw space ends
% the address for most browsers.
p = strrep(strtrim(pth), '\', '/');
if strncmp(p, '//', 2)
    url = ['file:' p];        % file://server/share/...
else
    url = ['file:///' p];     % file:///C:/...
end
url = strrep(url, ' ', '%20');
end
