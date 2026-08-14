function h = protocolHistory(self, subjectId, projectId)
% h = protocolHistory(self, subjectId, projectId)
% The protocols this subject has been on in this project, most recent first.
%
% The current protocol is NOT in the list — this is what revertProtocol can go
% back to. An empty result means the subject has only ever been on one
% protocol, so there is nothing to revert to.
%
% Parameters:
%   subjectId - SubjectID or subject Name.
%   projectId - ProjectID or project Name.
%
% Returns:
%   h - (1,:) struct array with fields File, Version, Stamp. Each entry also
%       carries OnDiskVersion (what the file holds now) and Recoverable (true
%       when those agree), because an .eprot saved over since is not the
%       protocol that entry names — see revertProtocol.
%
% See also: epsych.SubjectRoster.revertProtocol, epsych.SubjectRoster.rememberProtocol
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
end

h = struct('File', {}, 'Version', {}, 'Stamp', {}, ...
    'OnDiskVersion', {}, 'Recoverable', {});

rec = self.findMembership(subjectId, projectId);
if isempty(rec), return, end

entries = epsych.SubjectRoster.normalize_(rec.ProtocolHistory, ...
    epsych.SubjectRoster.blankHistory_());
if isempty(entries), return, end

for i = 1:numel(entries)
    onDisk = epsych.Protocol.versionOnDisk(entries(i).File);
    h(end+1) = struct('File', entries(i).File, 'Version', entries(i).Version, ...
        'Stamp', entries(i).Stamp, 'OnDiskVersion', onDisk, ...
        'Recoverable', ~isempty(onDisk) && strcmp(onDisk, entries(i).Version));
end
