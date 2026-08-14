function L = normalizeLinks_(links, options)
% L = epsych.SubjectRoster.normalizeLinks_(links)
% L = epsych.SubjectRoster.normalizeLinks_(links, Validate = true)
% Coerce whatever a caller or an older file offers into (1,:) link records.
%
% normalize_ shapes the outer project record only; a nested array needs its own
% pass, and this is it. It is the single authority for what a stored link looks
% like, so a link built by makeLink, typed into the project dialog, or read off
% disk all come out identical.
%
% Validation is opt-in and off by default on purpose: a write must reject an
% unsafe address, but a read must not, or one operator's typo would make the
% shared roster unopenable for the whole lab. openLink is the backstop.
%
% Parameters:
%   links - struct array with Label/URL fields, or empty.
%
% Options:
%   Validate - reject an address isSafeUrl refuses (default false). When true,
%              addresses are also normalized (bare host -> https://, path ->
%              file:///).
%
% Returns:
%   L - (1,:) struct array of link records; entries with no address are dropped.
%
% Throws:
%   epsych:SubjectRoster:InvalidLinks
%   epsych:SubjectRoster:UnsafeLink
%
% See also: epsych.SubjectRoster.makeLink, epsych.SubjectRoster.isSafeUrl
arguments
    links
    options.Validate (1,1) logical = false
end

template = epsych.SubjectRoster.blankLink_();

if isempty(links)
    L = repmat(template, 1, 0);
    return
end

if ~isstruct(links)
    error('epsych:SubjectRoster:InvalidLinks', ...
        'Links must be a struct array with Label and URL fields, not a %s.', class(links));
end

L = epsych.SubjectRoster.normalize_(links, template);

keep = true(1, numel(L));
for i = 1:numel(L)
    L(i).Label = strtrim(char(string(L(i).Label)));
    L(i).URL   = strtrim(char(string(L(i).URL)));

    % An address-less row is a half-finished edit, not data: the dialog's table
    % always carries a blank row at the bottom.
    if isempty(L(i).URL)
        keep(i) = false;
        continue
    end

    if options.Validate
        [ok, why, url] = epsych.SubjectRoster.isSafeUrl(L(i).URL);
        if ~ok
            error('epsych:SubjectRoster:UnsafeLink', '%s', why);
        end
        L(i).URL = url;
    end

    if isempty(L(i).Label)
        L(i).Label = localAutoLabel(L(i).URL);
    end
end

L = L(keep);

end

% -----------------------------------------------------------------------
function label = localAutoLabel(url)
% Something readable for a link the operator pasted without naming.
label = url;

if strncmpi(url, 'mailto:', 7)
    label = url(8:end);
    return
end

if strncmpi(url, 'file:', 5)
    % The leaf of the path is what a person calls the thing.
    parts = strsplit(strrep(url, '%20', ' '), '/');
    parts = parts(~cellfun(@isempty, parts));
    if ~isempty(parts)
        label = parts{end};
    end
    return
end

host = regexp(url, '^[A-Za-z][A-Za-z0-9+.\-]*://([^/?#]+)', 'tokens', 'once');
if ~isempty(host)
    label = regexprep(host{1}, '^www\.', '');
end
end
