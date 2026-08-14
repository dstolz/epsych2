function report = importFromConfig(self, configFile, options)
% report = importFromConfig(self, configFile)
% report = importFromConfig(self, configFile, ProjectID=..., Actions=...)
% Bring the subjects in a .ecfg file into the roster.
%
% Non-destructive by construction: a name that already exists is LINKED, never
% overwritten. A colleague's config must not be able to redefine a curated
% record, and there is no undo for a shared file.
%
% The .ecfg is read for subject structs and protocol paths only — no Protocol
% object is reconstructed, so this is cheap and cannot fail on a protocol whose
% hardware backend is unavailable.
%
% Parameters:
%   configFile - path to a .ecfg file.
%
% Options:
%   ProjectID - project to enrol imported subjects in; '' to import without
%               enrolling (default '')
%   Actions   - per-subject 'import' | 'link' | 'skip', overriding the default
%               (link on a name match, import otherwise)
%
% Returns:
%   report - struct with fields imported, linked, skipped (each a (1,:) struct
%            of Name/SubjectID) and message.
%
% See also: epsych.SubjectRoster.fromSubject, epsych.RunExpt.LoadConfig
arguments
    self
    configFile (1,:) char
    options.ProjectID (1,:) char = ''
    options.Actions cell = {}
end

report = struct( ...
    'imported', struct('Name', {}, 'SubjectID', {}), ...
    'linked',   struct('Name', {}, 'SubjectID', {}), ...
    'skipped',  struct('Name', {}, 'reason', {}), ...
    'message',  '');

found = epsych.SubjectRoster.readConfigSubjects_(configFile);
if isempty(found)
    report.message = sprintf('No subjects found in "%s".', configFile);
    return
end

[~, cfgName, cfgExt] = fileparts(configFile);
provenance = [cfgName cfgExt];

for i = 1:numel(found)
    name = found(i).Name;

    existing = self.findSubject(name);
    action = 'import';
    if ~isempty(existing)
        action = 'link';
    end
    if numel(options.Actions) >= i && ~isempty(options.Actions{i})
        action = lower(options.Actions{i});
    end

    switch action
        case 'skip'
            report.skipped(end+1) = struct('Name', name, 'reason', 'skipped by the operator');
            continue

        case 'link'
            if isempty(existing)
                report.skipped(end+1) = struct('Name', name, ...
                    'reason', 'asked to link, but no roster subject has that name');
                continue
            end
            id = existing.SubjectID;
            report.linked(end+1) = struct('Name', name, 'SubjectID', id);

        otherwise
            try
                id = self.fromSubject(found(i), ImportedFrom = provenance);
            catch ME
                vprintf(0, 1, ME);
                report.skipped(end+1) = struct('Name', name, 'reason', ME.message);
                continue
            end
            report.imported(end+1) = struct('Name', name, 'SubjectID', id);
    end

    if ~isempty(options.ProjectID)
        try
            self.assign(id, options.ProjectID);
            if ~isempty(found(i).protocol_fn)
                self.rememberProtocol(id, options.ProjectID, found(i).protocol_fn);
            end
        catch ME
            vprintf(0, 1, ME);
        end
    end
end

report.message = sprintf('%d imported, %d linked, %d skipped.', ...
    numel(report.imported), numel(report.linked), numel(report.skipped));
vprintf(1, 'Subject import from "%s": %s', provenance, report.message);
