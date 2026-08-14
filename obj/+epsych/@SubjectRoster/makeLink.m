function L = makeLink(label, url)
% L = epsych.SubjectRoster.makeLink(url)
% L = epsych.SubjectRoster.makeLink(label, url)
% Build one validated link record, for scripting a project's Links array.
%
% Parameters:
%   label - what to show; defaults to the host, address, or file name.
%   url   - the address; normalized by isSafeUrl.
%
% Returns:
%   L - (1,1) link record.
%
% Throws:
%   epsych:SubjectRoster:UnsafeLink
%
% Examples:
%   L = [epsych.SubjectRoster.makeLink('Lab notebook','https://elog.lab.edu/gap'), ...
%        epsych.SubjectRoster.makeLink('\\nas\gapdetect\logs')];
%
%   % Assign the field rather than passing it to struct(): struct('Links', L)
%   % would build one project per link instead of one project holding them all.
%   P = struct();
%   P.Links = L;
%   R.updateProject(id, P);
%
% See also: epsych.SubjectRoster.isSafeUrl, epsych.SubjectRoster.updateProject
arguments
    label (1,:) char
    url   (1,:) char = ''
end

% One argument is the address, not the label: the address is the part that
% cannot be guessed, and makeLink can fill in a label but not a URL.
if isempty(url)
    url   = label;
    label = '';
end

L = epsych.SubjectRoster.blankLink_();
L.Label = label;
L.URL   = url;

L = epsych.SubjectRoster.normalizeLinks_(L, Validate = true);

if isempty(L)
    error('epsych:SubjectRoster:UnsafeLink', 'The link has no address.');
end
