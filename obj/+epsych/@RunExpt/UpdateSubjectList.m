function UpdateSubjectList(self)
% UpdateSubjectList — Populate the subject uitable and controls.
% Behavior
%   Reflects CONFIG contents in the table and toggles action buttons.
%   Flags any subject whose loaded protocol is behind the version
%   currently saved on disk by coloring its Version cell and updating
%   the table tooltip with concise update instructions.
%
%   A subject the roster HOLDS on an earlier version is behind the file on
%   purpose and is not flagged. The session carries no pin flag, so the
%   evidence is the load itself: epsych.Protocol.load always yields a file's
%   current content, so a loaded version that differs from the file's yet sits
%   in its archive can only have come from epsych.SubjectRoster.assignToSession
%   honouring a hold. Asked only for the rows that already disagree, so a
%   healthy list costs nothing extra.
arguments
    self
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

if isempty(self.CONFIG) || isempty(self.CONFIG(1).SUBJECT)
    set(self.H.subject_list,'data',[])
    set([self.H.setup_remove_subject self.H.view_trials],'Enable','off')
    return
end

nSubjects = length(self.CONFIG);
data = cell(nSubjects,4);
isOutdated = false(nSubjects,1);
outdatedInfo = cell(1,nSubjects);
nOutdated = 0;
for i = 1:nSubjects
    data{i,1} = self.CONFIG(i).SUBJECT.BoxID;
    data{i,2} = self.CONFIG(i).SUBJECT.Name;
    [~,fn,~] = fileparts(self.CONFIG(i).protocol_fn);
    data{i,3} = char(fn);
    loadedVersion = char(self.CONFIG(i).PROTOCOL.meta.protocolVersion);
    data{i,4} = loadedVersion;

    pfn = char(self.CONFIG(i).protocol_fn);
    diskVersion = epsych.Protocol.versionOnDisk(pfn);
    if epsych.Protocol.versionNumber(diskVersion) > epsych.Protocol.versionNumber(loadedVersion)
        if epsych.Protocol.hasVersion(pfn, loadedVersion)
            % Loaded out of the file's archive: held, not behind.
            data{i,4} = sprintf('%s (held)', loadedVersion);
        else
            isOutdated(i) = true;
            nOutdated = nOutdated + 1;
            outdatedInfo{nOutdated} = sprintf('%s: loaded %s, latest %s', ...
                self.CONFIG(i).SUBJECT.Name, loadedVersion, diskVersion);
        end
    end
end
outdatedInfo = outdatedInfo(1:nOutdated);
set(self.H.subject_list,'Data',data)

try
    removeStyle(self.H.subject_list);
catch
end
if any(isOutdated)
    style = uistyle('FontColor',[0.80 0.36 0.02],'FontWeight','bold');
    addStyle(self.H.subject_list, style, 'cell', [find(isOutdated), repmat(4,nnz(isOutdated),1)]);
    self.H.subject_list.Tooltip = [ ...
        {'Right-click a subject to edit, update, or change its protocol file.', '', ...
         'A newer protocol version is available:'}, outdatedInfo, ...
        {'', 'Right-click the subject and choose "Update to Latest Version" to update.'}];
else
    self.H.subject_list.Tooltip = 'Right-click a subject to edit, update, or change its protocol file';
end

if size(data,1) == 0
    set([self.H.setup_remove_subject self.H.view_trials],'Enable','off')
else
    set([self.H.setup_remove_subject self.H.edit_protocol self.H.view_trials],'Enable','on')
end
end
