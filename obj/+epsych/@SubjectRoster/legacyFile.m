function f = legacyFile()
% f = epsych.SubjectRoster.legacyFile()
% The per-user roster that earlier builds fell back to, or '' when none exists.
%
% Until 2026-08-14 a rig with no configured roster silently wrote to
% <prefdir>/epsych/subjects.esub. That was a bad place for the only copy of a
% lab's animal records: prefdir is release-specific, so the file went missing
% on a MATLAB upgrade, and nothing about it is anywhere an operator would think
% to look or back up. There is no fallback any more -- see configuredFile.
%
% This exists only so that the file a rig already accumulated can be adopted,
% once, by the first roster the operator names. Sibling release folders are
% searched as well, because the roster built under R2024a is exactly the one
% worth keeping when the rig moves to R2024b, and the newest is returned when
% several exist.
%
% Returns:
%   f - full path to the most recently written legacy roster, or '' if there
%       is none.
%
% See also: epsych.SubjectRoster.setConfiguredFile, epsych.SubjectRoster.configuredFile

name = ['subjects' epsych.SubjectRoster.FILE_EXTENSION];

% prefdir is <...>/MathWorks/MATLAB/<release>, so its parent holds every
% release this user has run.
candidates = {fullfile(prefdir, 'epsych', name)};

releaseRoot = fileparts(prefdir);
d = dir(releaseRoot);
if ~isempty(d)
    d = d([d.isdir] & ~ismember({d.name}, {'.','..'}));
    candidates = [candidates, arrayfun( ...
        @(x) fullfile(releaseRoot, x.name, 'epsych', name), d(:)', 'uni', 0)];
end

f = '';
newest = -Inf;
for i = 1:numel(candidates)
    info = dir(candidates{i});
    if isempty(info) || info(1).isdir, continue, end
    if info(1).datenum > newest
        newest = info(1).datenum;
        f = candidates{i};
    end
end

if ~isempty(f)
    vprintf(3, 'Legacy subject roster found: %s', f);
end
