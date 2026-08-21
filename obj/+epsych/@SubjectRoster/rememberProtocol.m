function rememberProtocol(self, subjectId, projectId, protocolFile, boxID, options)
% rememberProtocol(self, subjectId, projectId, protocolFile)
% rememberProtocol(self, subjectId, projectId, protocolFile, boxID)
% rememberProtocol(..., Version = 'v3.260814')
% Record what a subject just ran, so next session proposes the same thing.
%
% Called by assignToSession after a successful commit. Silently does nothing
% when the subject is not in the project — assigning to a session does not
% require membership, and a stray call must not create one.
%
% The protocol's version is recorded alongside the path. That is the only way
% the roster can later answer "has this protocol been edited since this subject
% last ran it": an .eprot is overwritten in place on every save, so the file
% itself keeps no record of what it used to be. When Version is not supplied it
% is read off the file (epsych.Protocol.versionOnDisk); pass it explicitly when
% the protocol is already loaded, to save re-reading the file.
%
% Whenever the file or its version actually changes, the outgoing pair is
% pushed onto the membership's ProtocolHistory, which is what revertProtocol
% offers back.
%
% A PINNED membership is the one case where the incoming version does not
% simply win. revertProtocol pins a subject that was put back on a version
% living only in the file's archive, and assignToSession then loads that
% version rather than the file's current content -- so the version it hands
% back here is the pinned one and the pin survives untouched. Anything
% recording a DIFFERENT file or version is moving the subject forward, which
% is exactly what releases the hold, so the pin is cleared. Without that rule
% adding a subject to a session silently undid the revert: the session loaded
% whatever the file held and recorded it straight over the restored version.
%
% Parameters:
%   subjectId    - SubjectID or subject Name.
%   projectId    - ProjectID or project Name.
%   protocolFile - full path to the .eprot that was used.
%   boxID        - (optional) box it ran in; NaN leaves the stored value alone.
%
% Options:
%   Version - protocolVersion to record. Default: read from the file.
%
% See also: epsych.SubjectRoster.lastProtocol, epsych.SubjectRoster.protocolStatus,
%   epsych.SubjectRoster.revertProtocol, epsych.SubjectRoster.assignToSession
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
    protocolFile (1,:) char
    boxID (1,1) double = NaN
    options.Version (1,:) char = char.empty
end

[rec, idx] = self.findMembership(subjectId, projectId);
if isempty(idx)
    vprintf(3, 'rememberProtocol: "%s" is not in "%s"; nothing recorded.', ...
        subjectId, projectId);
    return
end

sid = rec.SubjectID;
pid = rec.ProjectID;

version = options.Version;
if isempty(version)
    version = epsych.Protocol.versionOnDisk(protocolFile);
end

self.mutate_(@applyRemember);

vprintf(3, 'Remembered protocol for "%s" in "%s": %s (%s)', subjectId, projectId, ...
    protocolFile, localOrUnknown(version));

    function applyRemember(r)
        [~, k] = r.findMembership(sid, pid);
        if isempty(k), return, end

        prior = r.Memberships(k);

        % Only a real change earns a history entry. Re-running the same
        % protocol every day for a month must not bury the file this subject
        % was moved off, which is the one thing history exists to keep.
        changed = ~strcmp(prior.LastProtocol, protocolFile) || ...
                  ~strcmp(prior.LastProtocolVersion, version);
        if changed && ~isempty(prior.LastProtocol)
            r.Memberships(k).ProtocolHistory = epsych.SubjectRoster.pushHistory_( ...
                prior.ProtocolHistory, prior.LastProtocol, prior.LastProtocolVersion);
        end

        r.Memberships(k).LastProtocol        = protocolFile;
        r.Memberships(k).LastProtocolVersion = version;
        % `changed` is the release condition: the hold survives only a record
        % of exactly what it was already holding.
        if changed
            r.Memberships(k).ProtocolPinned = false;
        end
        if ~isnan(boxID)
            r.Memberships(k).LastBoxID = boxID;
        end
        r.Memberships(k).Modified = datetime('now');
    end

end

% -----------------------------------------------------------------------
function s = localOrUnknown(version)
s = version;
if isempty(s), s = 'version unknown'; end
end
