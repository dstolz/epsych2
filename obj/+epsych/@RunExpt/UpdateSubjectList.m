function UpdateSubjectList(self)
% UpdateSubjectList — Populate the subject uitable and controls.
% Behavior
%   Reflects CONFIG contents in the table and toggles action buttons.
%   Flags any subject whose loaded protocol is behind the version
%   currently saved on disk by coloring its Version cell and updating
%   the table tooltip with concise update instructions.
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

    diskVersion = readProtocolVersionOnDisk_(self.CONFIG(i).protocol_fn);
    if protocolVersionNumber_(diskVersion) > protocolVersionNumber_(loadedVersion)
        isOutdated(i) = true;
        nOutdated = nOutdated + 1;
        outdatedInfo{nOutdated} = sprintf('%s: loaded %s, latest %s', ...
            self.CONFIG(i).SUBJECT.Name, loadedVersion, diskVersion);
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

function n = protocolVersionNumber_(verStr)
% Parse the leading integer from a 'vN.YYMMDD' protocol version string.
tok = regexp(char(verStr), '^v(\d+)\.', 'tokens', 'once');
if isempty(tok)
    n = NaN;
else
    n = str2double(tok{1});
end
end

function v = readProtocolVersionOnDisk_(pfn)
% Lightweight peek at a protocol file's stored version, without
% reconstructing the full Protocol object graph (see epsych.Protocol.load).
v = '';
pfn = char(pfn);
if isempty(pfn) || ~isfile(pfn), return, end

try
    [~,~,ext] = fileparts(pfn);
    if strcmpi(ext,'.json')
        S = jsondecode(fileread(pfn));
        if isfield(S,'protocolVersion')
            v = char(S.protocolVersion);
        end
    else
        S = load(pfn,'-mat');
        if isfield(S,'protocol') && isstruct(S.protocol) && isfield(S.protocol,'protocolVersion')
            v = char(S.protocol.protocolVersion);
        elseif isfield(S,'protocol_struct') && isfield(S.protocol_struct,'protocolVersion')
            v = char(S.protocol_struct.protocolVersion);
        end
    end
catch
    v = '';
end
end
