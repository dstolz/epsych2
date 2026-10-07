function subject_list_SelectionChanged(self, hObj, ~)
% Prints subject, roster, session-history and protocol info to the command window when selection changes.
if isempty(hObj.Selection), return, end
idx = hObj.Selection(1);
S = self.CONFIG(idx).SUBJECT;
C = self.CONFIG(idx);

fprintf('\n--- Subject ---\n')
fprintf('  Name:     %s\n', S.Name);
fprintf('  Box ID:   %d\n', S.BoxID);
if ~isempty(S.Species)
    fprintf('  Species:  %s\n', S.Species);
end
if ~isempty(S.Sex)
    fprintf('  Sex:      %s\n', S.Sex);
end
if ~isnan(S.Weight)
    fprintf('  Weight:   %g g\n', S.Weight);
end
if ~isempty(strtrim(char(S.Notes)))
    fprintf('  Notes:    %s\n', strtrim(char(S.Notes)));
end

R = [];
try
    R = printRoster_(C.ROSTER);
catch ME
    vprintf(1, ME);
    fprintf('--- Roster ---\n  (could not read the roster)\n');
end

% Listing session files reads each one on the thread the trial loop runs on,
% so it waits for the gap between sessions, like gui.SessionBrowser.
if self.STATE < PRGMSTATE.RUNNING
    try
        printSessions_(self, S, R);
    catch ME
        vprintf(1, ME);
        fprintf('--- Sessions ---\n  (could not list session files)\n');
    end
end

protocolFile = char(C.protocol_fn);
[~,pfn,pext] = fileparts(protocolFile);
fprintf('--- Protocol ---\n')
fprintf('  File:     %s%s\n', pfn, pext);
fprintf('  Path:     %s\n', protocolFile);
if isempty(protocolFile) || ~isfile(protocolFile)
    fprintf('  Status:   FILE NOT FOUND\n');
else
    d = dir(protocolFile);
    fprintf('  Modified on disk: %s (%.1f KB)\n', d.date, d.bytes/1024);
end

proto = C.PROTOCOL;
if isa(proto,'epsych.Protocol') && isvalid(proto)
    fprintf('  Version:  %s\n', proto.meta.protocolVersion);
    fprintf('  Format:   %g\n', proto.meta.formatVersion);
    if isfield(proto.meta,'epsychVersion') && ~isempty(proto.meta.epsychVersion)
        fprintf('  Saved by: %s\n', proto.meta.epsychVersion);
    end
    if isfield(proto.meta,'createdDate') && ~isempty(proto.meta.createdDate)
        fprintf('  Created:  %s\n', proto.meta.createdDate);
    end
    if isfield(proto.meta,'lastModified') && ~isempty(proto.meta.lastModified)
        fprintf('  Modified: %s\n', proto.meta.lastModified);
    end
    if ~isempty(proto.Info)
        fprintf('  Info:     %s\n', proto.Info);
    end

    fprintf('  Needs compile: %s\n', mat2str(proto.needsCompile));
    if proto.COMPILED.ntrials > 0
        fprintf('  Trials:   %d', proto.COMPILED.ntrials);
        if ~isempty(proto.COMPILED.compiledAt) && ~isnat(proto.COMPILED.compiledAt)
            fprintf(' (compiled %s)', datestr(proto.COMPILED.compiledAt)); %#ok<DATST>
        end
        fprintf('\n');
    end

    fprintf('--- Options ---\n')
    opt = proto.Options;
    if isfield(opt,'trialFunc') && ~isempty(opt.trialFunc)
        fprintf('  trialFunc:         %s\n', func2str_(opt.trialFunc));
    end
    if isfield(opt,'compileAtRuntime')
        fprintf('  compileAtRuntime:  %s\n', mat2str(opt.compileAtRuntime));
    end
    if isfield(opt,'IncludeWAVBuffers')
        fprintf('  IncludeWAVBuffers: %s\n', mat2str(opt.IncludeWAVBuffers));
    end
    if isfield(opt,'ConnectionType')
        fprintf('  ConnectionType:    %s\n', char(opt.ConnectionType));
    end

    fprintf('--- Interfaces ---\n')
    if isempty(proto.Interfaces)
        fprintf('  (none defined)\n');
    end
    for i = 1:numel(proto.Interfaces)
        iface = proto.Interfaces(i);
        nModules = numel(iface.Module);
        nParams = 0;
        for m = 1:nModules
            nParams = nParams + numel(iface.Module(m).Parameters);
        end
        ifaceName = '';
        if isprop(iface,'Name') && ~isempty(iface.Name)
            ifaceName = char(iface.Name);
        end
        if isempty(ifaceName)
            fprintf('  %-16s %d module(s), %d parameter(s)\n', char(iface.Type), nModules, nParams);
        else
            fprintf('  %-16s "%s" - %d module(s), %d parameter(s)\n', char(iface.Type), ifaceName, nModules, nParams);
        end
    end

    report = proto.validate();
    nErr  = sum([report.severity] == 2);
    nWarn = sum([report.severity] == 1);
    fprintf('--- Validation ---\n')
    if isempty(report)
        fprintf('  OK - no issues found\n');
    else
        fprintf('  %d error(s), %d warning(s)\n', nErr, nWarn);
        for i = 1:numel(report)
            switch report(i).severity
                case 2, tag = 'ERROR';
                case 1, tag = 'WARN ';
                otherwise, tag = 'INFO ';
            end
            fprintf('    [%s] %s: %s\n', tag, report(i).field, report(i).message);
        end
    end
elseif isstruct(proto) && isfield(proto,'OPTIONS')
    opt = proto.OPTIONS;
    if isfield(opt,'numReps'), fprintf('  Reps:     %d\n', opt.numReps); end
    if isfield(opt,'ISI'),     fprintf('  ISI:      %d ms\n', opt.ISI); end
    if isfield(opt,'randomize'), fprintf('  Randomize:%s\n', mat2str(opt.randomize)); end
    if isfield(proto,'ntrials') && proto.ntrials > 0
        fprintf('  Trials:   %d\n', proto.ntrials);
    end
end
end

function R = printRoster_(link)
% Roster record, project, membership and protocol status for a roster subject.
% Returns the open roster so the session listing can reuse it, [] when the
% subject did not come from one.
R = [];
if isempty(link) || ~isstruct(link) || isempty(link.File), return, end

R = epsych.SubjectRoster(link.File);
fprintf('--- Roster ---\n')
if ~R.IsBound || ~isempty(R.LoadError)
    fprintf('  Roster:   %s (unreadable: %s)\n', link.File, R.LoadError);
    R = [];
    return
end

subj = R.findSubject(link.SubjectID);
proj = R.findProject(link.ProjectID);
mem  = R.findMembership(link.SubjectID, link.ProjectID);
if isempty(subj) || isempty(mem)
    fprintf('  Roster:   %s\n  No longer in the roster or project it was added from.\n', link.File);
    return
end

fprintf('  Roster:   %s\n', link.File);
fprintf('  Project:  %s', proj.Name);
if ~mem.Active, fprintf('  (retired from this project)'); end
fprintf('\n');
if ~isempty(proj.Investigator)
    fprintf('  Investigator: %s\n', proj.Investigator);
end
if ~isempty(proj.IACUCProtocol)
    fprintf('  IACUC:    %s\n', proj.IACUCProtocol);
end
otherProjects = setdiff(string({R.projectsForSubject(subj.SubjectID).Name}), string(proj.Name));
if ~isempty(otherProjects)
    fprintf('  Also in:  %s\n', strjoin(otherProjects, ', '));
end
if subj.Retired
    fprintf('  Status:   RETIRED\n');
end
if ~isempty(subj.NameHistory)
    fprintf('  Formerly: %s\n', strjoin(subj.NameHistory, ', '));
end
if ~isnat(subj.Created)
    fprintf('  In roster since: %s\n', char(subj.Created, 'yyyy-MM-dd'));
end
if ~isnan(mem.LastBoxID)
    fprintf('  Last box: %d\n', mem.LastBoxID);
end

if ~isempty(mem.DefaultDataPath)
    fprintf('  Data path:    %s\n', mem.DefaultDataPath);
end
if ~isempty(mem.SavingFcn)
    fprintf('  Saving fcn:   %s\n', mem.SavingFcn);
end
if ~isempty(mem.BehaviorGUI)
    fprintf('  Behavior GUI: %s\n', mem.BehaviorGUI);
end
if ~isnan(mem.TimerPeriod)
    fprintf('  Timer period: %g s\n', mem.TimerPeriod);
end
if ~isnan(mem.RecordVideo)
    fprintf('  Record video: %s\n', string(mem.RecordVideo > 0));
end
if ~isempty(mem.ParameterDefaults)
    fprintf('  Parameter defaults: %d\n', numel(mem.ParameterDefaults));
end

st = R.protocolStatus(subj.SubjectID, proj.ProjectID);
fprintf('  Protocol status: %s', st.Status);
if ~isempty(st.Message), fprintf(' - %s', st.Message); end
fprintf('\n');
end

function printSessions_(self, S, R)
% Count and most recent of the subject's saved sessions.
if isempty(R)
    L = epsych.SessionFiles.locations(S.Name, RunExpt=self);
else
    L = epsych.SessionFiles.locations(S.Name, Roster=R, RunExpt=self);
end
T = epsych.SessionFiles.scan(L.Names, Roots=L.Roots, VideoRoots=L.VideoRoots);

fprintf('--- Sessions ---\n')
T = T(T.IsSession, :);
if isempty(T)
    fprintf('  None found\n');
    return
end
fprintf('  Saved:    %d session(s), %d trial(s) in all\n', height(T), sum(T.Trials));
last = T(1,:);
fprintf('  Latest:   %s, %d trial(s)', char(last.StartTime, 'yyyy-MM-dd HH:mm'), last.Trials);
if ~isnan(last.Duration)
    fprintf(', %s', char(last.Duration));
end
fprintf('\n');
if strlength(last.Paradigm) > 0
    fprintf('  Paradigm: %s\n', last.Paradigm);
end
end

function s = func2str_(f)
% Render Options.trialFunc (char, string, or function_handle) as text.
if isa(f,'function_handle')
    s = func2str(f);
else
    s = char(string(f));
end
end
