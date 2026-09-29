function [D, source, message] = lookup(link, options)
% [D, source, message] = epsych.ParameterDefaults.lookup(link)
% [D, source, message] = epsych.ParameterDefaults.lookup(link, Roster=R)
% The defaults a CONFIG entry's subject has NOW, read from its roster.
%
% Read at Run rather than trusted from the commit, so a default edited after
% the subject was added to the session still counts. When the roster cannot be
% read -- the share is offline, the file moved -- the defaults as they stood at
% commit (link.ParameterDefaults) are used instead and message says so: the
% last known defaults are a better run than none.
%
% Parameters:
%   link - the entry's ROSTER struct (epsych.ParameterDefaults.rosterLink), or
%          [] for a subject that did not come from a roster.
%
% Options:
%   Roster - an already-open epsych.SubjectRoster to read, reused when its
%            FilePath is link.File; a session of several subjects reads the
%            file once this way.
%
% Returns:
%   D       - record array (possibly empty).
%   source  - 'roster', 'snapshot' (the commit-time copy), or 'none'.
%   message - '' or a sentence for the log and status bar.
%
% See also: epsych.ParameterDefaults.applyToConfigEntry, epsych.SubjectRoster.parameterDefaults
arguments
    link = []
    options.Roster = []
end

D = epsych.ParameterDefaults.empty();
source = 'none';
message = '';

if isempty(link) || ~isstruct(link) || ~isscalar(link) ...
        || ~isfield(link, 'SubjectID') || isempty(link.SubjectID) ...
        || ~isfield(link, 'ProjectID') || isempty(link.ProjectID)
    return
end

snapshot = epsych.ParameterDefaults.empty();
if isfield(link, 'ParameterDefaults')
    snapshot = epsych.ParameterDefaults.normalize(link.ParameterDefaults);
end

R = options.Roster;
if isempty(R) || ~isa(R, 'epsych.SubjectRoster') || ~isvalid(R) ...
        || ~localSameFile(R.FilePath, link.File)
    R = [];
    if ~isempty(link.File)
        R = epsych.SubjectRoster(link.File);
    end
end

if isempty(R) || ~R.IsBound || ~isempty(R.LoadError) || ~isfile(R.FilePath)
    D = snapshot;
    source = 'snapshot';
    if ~isempty(D)
        message = sprintf(['The subject roster "%s" could not be read, so the parameter ' ...
            'defaults as they stood when the subject was added were used.'], link.File);
    end
    return
end

source = 'roster';
m = R.findMembership(link.SubjectID, link.ProjectID);
if isempty(m)
    if ~isempty(snapshot)
        message = sprintf(['Subject %s is no longer a member of the project it was added ' ...
            'from, so none of its parameter defaults were applied.'], link.SubjectID);
    end
    return
end
D = epsych.ParameterDefaults.normalize(m.ParameterDefaults);
end

% -----------------------------------------------------------------------
function tf = localSameFile(a, b)
a = strrep(char(a), '/', filesep);
b = strrep(char(b), '/', filesep);
if ispc
    tf = strcmpi(a, b);
else
    tf = strcmp(a, b);
end
end
