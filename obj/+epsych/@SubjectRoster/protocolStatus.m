function report = protocolStatus(self, subjectIds, projectId)
% report = protocolStatus(self, subjectIds)
% report = protocolStatus(self, subjectIds, projectId)
% Answer "is this subject on the current protocol?" for one subject or many.
%
% Two different things can make an answer no, and they are not the same
% problem, so they are reported separately:
%
%   * the protocol FILE was re-saved since this subject last ran it — the
%     recorded version is behind what epsych.Protocol.versionOnDisk now reads;
%   * the subject is pointed at a DIFFERENT file from the project's default.
%
% The first is what the roster is uniquely able to notice: an .eprot is
% overwritten in place on every save, so nothing but the version recorded by
% rememberProtocol can say what a subject was last on.
%
% This takes no graphics and returns plain structs, so the whole check is
% usable from a script and testable with no figure open.
%
% Parameters:
%   subjectIds - SubjectID or Name; char for one, cellstr/string for many.
%   projectId  - project context. '' resolves protocols across every project
%                the subject belongs to, as lastProtocol does.
%
% Returns:
%   report - (1,:) struct, one per requested subject:
%     SubjectID, Name    - who
%     Protocol           - resolved .eprot path, or ''
%     Source             - 'remembered' | 'project default' | 'none'
%     Version            - protocolVersion recorded for this subject, or ''
%     LatestVersion      - protocolVersion in the file right now, or ''
%     DefaultProtocol    - the project's default, or ''
%     MatchesDefault     - true when Protocol is the project's default
%     IsOutdated         - true when the file is a newer version than recorded
%     Status             - 'current' | 'outdated' | 'differs' | 'unknown' |
%                          'missing' | 'none'
%     Message            - one line naming what is wrong, or ''
%
% Example:
%   st = R.protocolStatus({R.subjectsInProject(p).SubjectID}, p);
%   behind = st([st.IsOutdated]);
%
% See also: epsych.SubjectRoster.updateProtocol, epsych.SubjectRoster.revertProtocol,
%   epsych.SubjectRoster.rememberProtocol, epsych.Protocol.versionOnDisk
arguments
    self
    subjectIds
    projectId (1,:) char = ''
end

subjectIds = cellstr(string(subjectIds));

report = struct('SubjectID', {}, 'Name', {}, 'Protocol', {}, 'Source', {}, ...
    'Version', {}, 'LatestVersion', {}, 'DefaultProtocol', {}, ...
    'MatchesDefault', {}, 'IsOutdated', {}, 'Status', {}, 'Message', {});

if isempty(subjectIds), return, end

defaultProtocol = '';
if ~isempty(projectId)
    p = self.findProject(projectId);
    if ~isempty(p), defaultProtocol = p.DefaultProtocol; end
end

% One peek per distinct file, not one per subject: a project of sixteen
% animals on one protocol must not read the same .eprot sixteen times, and
% this runs on every repaint of the manager's table.
versionCache = containers.Map('KeyType', 'char', 'ValueType', 'char');

for i = 1:numel(subjectIds)
    rec = self.findSubject(subjectIds{i});
    if isempty(rec)
        report(end+1) = localEntry(subjectIds{i}, subjectIds{i}, '', 'none', ...
            '', '', defaultProtocol, false, false, 'none', ...
            'Not in the roster.');
        continue
    end

    version = '';
    source  = 'none';

    m = self.findMembership(rec.SubjectID, projectId);
    if ~isempty(m) && ~isempty(m.LastProtocol)
        protocol = m.LastProtocol;
        version  = m.LastProtocolVersion;
        source   = 'remembered';
    else
        % No membership record to read (or nothing remembered in it): fall back
        % to exactly what lastProtocol would propose, so the status describes
        % the protocol that would actually be used.
        protocol = self.lastProtocol(rec.SubjectID, projectId);
        if ~isempty(protocol)
            source = 'project default';
            if isempty(projectId)
                % Across-projects fallback: whatever it resolved to came from
                % some membership, so report its version if we can find it.
                [protocol, version, source] = localAcrossProjects(self, rec.SubjectID, protocol);
            end
        end
    end

    if isempty(protocol)
        report(end+1) = localEntry(rec.SubjectID, rec.Name, '', 'none', ...
            '', '', defaultProtocol, false, false, 'none', ...
            'No protocol: none remembered and the project has no default.');
        continue
    end

    matchesDefault = isempty(defaultProtocol) || localSamePath(protocol, defaultProtocol);

    if ~isfile(protocol)
        report(end+1) = localEntry(rec.SubjectID, rec.Name, protocol, source, ...
            version, '', defaultProtocol, matchesDefault, false, 'missing', ...
            sprintf('The protocol file is missing: %s', protocol));
        continue
    end

    if isKey(versionCache, protocol)
        latest = versionCache(protocol);
    else
        latest = epsych.Protocol.versionOnDisk(protocol);
        versionCache(protocol) = latest;
    end

    isOutdated = epsych.Protocol.versionNumber(latest) > epsych.Protocol.versionNumber(version);

    if isOutdated
        status  = 'outdated';
        message = sprintf('The protocol has been saved since this subject last ran it: %s on record, %s in the file.', ...
            version, latest);
    elseif ~matchesDefault
        status  = 'differs';
        [~, dn, de] = fileparts(defaultProtocol);
        message = sprintf('Not the project default (%s%s).', dn, de);
    elseif isempty(version)
        status  = 'unknown';
        message = 'No version on record yet; it is recorded the first time this subject is added to a session.';
    else
        status  = 'current';
        message = '';
    end

    report(end+1) = localEntry(rec.SubjectID, rec.Name, protocol, source, ...
        version, latest, defaultProtocol, matchesDefault, isOutdated, status, message);
end

end

% -----------------------------------------------------------------------
function e = localEntry(id, name, protocol, source, version, latest, ...
    defaultProtocol, matchesDefault, isOutdated, status, message)
e = struct('SubjectID', id, 'Name', name, 'Protocol', protocol, ...
    'Source', source, 'Version', version, 'LatestVersion', latest, ...
    'DefaultProtocol', defaultProtocol, 'MatchesDefault', matchesDefault, ...
    'IsOutdated', isOutdated, 'Status', status, 'Message', message);
end

% -----------------------------------------------------------------------
function [protocol, version, source] = localAcrossProjects(self, subjectId, protocol)
% In the All Subjects view there is no project context, so lastProtocol may
% have resolved through any membership. Find the one holding this file to
% recover the version recorded with it.
version = '';
source  = 'remembered';

if isempty(self.Memberships), source = 'project default'; return, end

mine = self.Memberships(strcmp({self.Memberships.SubjectID}, subjectId));
hit  = find(arrayfun(@(m) localSamePath(m.LastProtocol, protocol), mine), 1);
if isempty(hit)
    source = 'project default';
    return
end
version = mine(hit).LastProtocolVersion;
end

% -----------------------------------------------------------------------
function tf = localSamePath(a, b)
% Compare two protocol paths the way the filesystem would.
a = char(a); b = char(b);
if isempty(a) || isempty(b)
    tf = isempty(a) && isempty(b);
    return
end
a = strrep(a, '/', filesep); b = strrep(b, '/', filesep);
if ispc
    tf = strcmpi(a, b);
else
    tf = strcmp(a, b);
end
end
