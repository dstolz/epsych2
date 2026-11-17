classdef SessionRecord
    % epsych.SessionRecord
    % rec = epsych.SessionRecord.fromRun(RUNTIME, CONFIG, i)
    % rec = epsych.SessionRecord.blank()
    % What one subject's finished session was, as plain data, for whoever
    % records sessions outside EPsych (see epsych.SubjectRegistry).
    %
    % Built by epsych.RunExpt AFTER the saving function returns, from the
    % runtime and the session CONFIG together: a saving function receives only
    % RUNTIME, which knows neither the protocol file nor the roster subject the
    % animal came from, so building it here is what makes it work with every
    % saving function, a lab's own included. It reads no hardware and never
    % throws: what cannot be found is left empty and named in Problems.
    %
    % Fields (every one present, scalar):
    %   SessionUID        - the session's identity (Info.SessionUID; epsych.newUUID)
    %   Subject           - the animal's Name in this session
    %   SubjectID, ProjectID, Project, RosterFile
    %                     - where it came from in the roster ("" when not from one)
    %   RegistryID, ProjectRegistryID
    %                     - the roster's links to the lab's subject registry
    %   Sex, Species      - as the session's subject carried them
    %   BoxID             - the box it ran in
    %   DataFile          - the saved file, absolute, "" when it is not on disk
    %   DataFileExpected  - the path the saving function was handed
    %   StartTime, EndTime- zoned (this computer's zone); EndTime is the last
    %                       trial's computerTimestamp, NaT with no trials
    %   NumTrials         - completed trials
    %   ProtocolFile, ProtocolName, ProtocolVersion, Paradigm, SelectorClass
    %   BehaviorGUI, SavingFcn
    %   NotesText         - the operator's notes for this subject's file
    %   Host, User        - the computer and its login
    %   EPsychVersion, EPsychChecksum, StimgenChecksum
    %   EndedWithError, ErrorMessage
    %   IsTest            - a Preview (never recorded by RunExpt; kept so a
    %                       caller building one by hand can tell)
    %   Problems          - (1,:) string, what could not be determined
    %
    % See also: epsych.SubjectRegistry, epsych.SessionSnapshot, epsych.RunExpt

    methods
        function obj = SessionRecord()
            % Not constructible: a namespace for two static functions.
            error('epsych:SessionRecord:NotConstructible', ...
                'epsych.SessionRecord has only static methods.');
        end
    end

    methods (Static)
        function rec = blank()
            % rec = epsych.SessionRecord.blank()
            % Every field at its empty value.
            rec = struct( ...
                'SessionUID', "", 'Subject', "", 'SubjectID', "", 'ProjectID', "", ...
                'Project', "", 'RosterFile', "", 'RegistryID', "", 'ProjectRegistryID', "", ...
                'Sex', "", 'Species', "", 'BoxID', NaN, ...
                'DataFile', "", 'DataFileExpected', "", ...
                'StartTime', NaT('TimeZone', 'local'), 'EndTime', NaT('TimeZone', 'local'), ...
                'NumTrials', 0, ...
                'ProtocolFile', "", 'ProtocolName', "", 'ProtocolVersion', "", ...
                'Paradigm', "", 'SelectorClass', "", 'BehaviorGUI', "", 'SavingFcn', "", ...
                'NotesText', "", 'Host', "", 'User', "", ...
                'EPsychVersion', "", 'EPsychChecksum', "", 'StimgenChecksum', "", ...
                'EndedWithError', false, 'ErrorMessage', "", 'IsTest', false, ...
                'Problems', strings(1, 0));
        end

        function rec = fromRun(RUNTIME, CONFIG, i, options)
            % rec = epsych.SessionRecord.fromRun(RUNTIME, CONFIG, i)
            % rec = epsych.SessionRecord.fromRun(..., FUNCS=funcs)
            % The record of subject I of the run RUNTIME just finished.
            %
            % Parameters:
            %   RUNTIME - epsych.Runtime of the run.
            %   CONFIG  - epsych.RunExpt.CONFIG of the session (protocol
            %             file and roster link per subject).
            %   i       - subject index.
            % Options:
            %   FUNCS   - epsych.RunExpt.FUNCS, for BehaviorGUI/SavingFcn.
            arguments
                RUNTIME
                CONFIG
                i (1,1) double {mustBeInteger, mustBePositive}
                options.FUNCS = struct()
            end

            rec = epsych.SessionRecord.blank();
            try
                rec = localFill(rec, RUNTIME, CONFIG, i, options.FUNCS);
            catch ME
                vprintf(0, 1, ME)
                rec.Problems(end+1) = "could not describe the session: " + string(ME.message);
            end
        end
    end
end

% -----------------------------------------------------------------------
function rec = localFill(rec, RUNTIME, CONFIG, i, FUNCS)
T = RUNTIME.TRIALS(i);

snap = struct();
if isfield(T, 'SessionInfo') && isstruct(T.SessionInfo) && ~isempty(T.SessionInfo)
    snap = T.SessionInfo;
end

% --- Identity ----------------------------------------------------------
uid = "";
if isfield(snap, 'SessionUID'), uid = localText(snap.SessionUID); end
if uid == "" && numel(RUNTIME.SessionUID) >= i, uid = RUNTIME.SessionUID(i); end
rec.SessionUID = uid;
if uid == "", rec.Problems(end+1) = "the session has no SessionUID"; end

S = T.Subject;
rec.Subject = localText(localProp(S, 'Name'));
rec.Sex     = localText(localProp(S, 'Sex'));
rec.Species = localText(localProp(S, 'Species'));
box = localProp(T, 'BoxID');
if isempty(box), box = localProp(S, 'BoxID'); end
if isnumeric(box) && isscalar(box), rec.BoxID = double(box); end

% --- File --------------------------------------------------------------
expected = localText(localProp(T, 'DataFilename'));
rec.DataFileExpected = expected;
if expected ~= ""
    cand = expected;
    [~, ~, ext] = fileparts(cand);
    if ext == "", cand = cand + ".mat"; end   % ep_SaveDataFcn's rule
    for c = unique([cand, expected], 'stable')
        if isfile(c)
            rec.DataFile = localAbsolute(c);
            break
        end
    end
end
if rec.DataFile == ""
    rec.Problems(end+1) = "the data file was not found at " + expected;
end

% --- Times and trials --------------------------------------------------
D = localProp(T, 'DATA');
rec.NumTrials = localNumTrials(D);
start = localZoned(localProp(snap, 'StartTime'));
if isnat(start), start = localZoned(RUNTIME.StartTime); end
rec.StartTime = start;
if rec.NumTrials > 0 && isstruct(D) && isfield(D, 'computerTimestamp')
    rec.EndTime = localZoned(D(end).computerTimestamp);
end

% --- Protocol ----------------------------------------------------------
c = struct();
if numel(CONFIG) >= i, c = CONFIG(i); end
pfn = localText(localProp(c, 'protocol_fn'));
rec.ProtocolFile = pfn;
if pfn ~= ""
    [~, rec.ProtocolName] = fileparts(pfn);
end
P = localProp(snap, 'Protocol');
if isstruct(P) && ~isempty(P)
    rec.ProtocolVersion = localText(localProp(P, 'protocolVersion'));
    opts = localProp(P, 'Options');
    if isstruct(opts), rec.Paradigm = localText(localProp(opts, 'trialFunc')); end
end
rec.SelectorClass = localText(localProp(snap, 'SelectorClass'));
if isstruct(FUNCS)
    rec.BehaviorGUI = localFuncText(localProp(FUNCS, 'BehaviorGUI'));
    rec.SavingFcn   = localFuncText(localProp(FUNCS, 'SavingFcn'));
end

% --- Roster ------------------------------------------------------------
rec = localRoster(rec, localProp(c, 'ROSTER'));

% --- Notes, provenance, outcome ----------------------------------------
try
    N = epsych.SessionSnapshot.withNotes(struct(), RUNTIME, i);
    rec.NotesText = localText(N.NotesText, newline);
catch ME
    rec.Problems(end+1) = "notes unavailable: " + string(ME.message);
end

rec.Host = localText(getenv('COMPUTERNAME'));
if rec.Host == "", rec.Host = localText(getenv('HOSTNAME')); end
rec.User = localText(getenv('USERNAME'));
if rec.User == "", rec.User = localText(getenv('USER')); end

meta = localProp(snap, 'EPsychMeta');
if isstruct(meta) && ~isempty(fieldnames(meta))
    rec.EPsychVersion   = localText(localProp(meta, 'Version'));
    rec.EPsychChecksum  = localText(localProp(meta, 'Checksum'));
    rec.StimgenChecksum = localText(localProp(meta, 'StimgenChecksum'));
end

err = [];
try err = RUNTIME.ERROR; catch, end
if ~isempty(err)
    rec.EndedWithError = true;
    try rec.ErrorMessage = string(err.message); catch, end
end
rec.IsTest = logical(RUNTIME.isTest);
end

% -----------------------------------------------------------------------
function rec = localRoster(rec, link)
% The roster's view of the animal, read NOW: a subject linked to the registry
% after it was added to the session still counts. Falls back to finding the
% subject by name in the configured roster when the session was not built
% from one (AddSubject), and to nothing when no roster can be read.
R = [];
sid = "";
pid = "";
if isstruct(link) && isscalar(link) && isfield(link, 'File')
    rec.RosterFile = localText(link.File);
    sid = localText(link.SubjectID);
    pid = localText(link.ProjectID);
    if rec.RosterFile ~= ""
        R = epsych.SubjectRoster(char(rec.RosterFile));
    end
elseif epsych.SubjectRoster.isConfigured()
    R = epsych.SubjectRoster();
    rec.RosterFile = localText(R.FilePath);
end
if isempty(R) || isempty(R.Subjects), return, end

s = epsych.SubjectRoster.emptySubject();
if sid ~= "", s = R.findSubject(char(sid)); end
if isempty(s) && rec.Subject ~= "", s = R.findSubject(char(rec.Subject)); end
if isempty(s)
    rec.Problems(end+1) = "the subject is not in the roster " + rec.RosterFile;
    return
end
rec.SubjectID = string(s.SubjectID);
rec.RegistryID = string(s.RegistryID);

if pid ~= ""
    p = R.findProject(char(pid));
    if ~isempty(p)
        rec.ProjectID = string(p.ProjectID);
        rec.Project = string(p.Name);
        rec.ProjectRegistryID = string(p.RegistryID);
    end
end
end

function n = localNumTrials(D)
% An all-empty placeholder record is zero trials, as epsych.SessionFiles reads it.
n = 0;
if ~isstruct(D) || isempty(D), return, end
n = numel(D);
if n == 1 && all(structfun(@isempty, D))
    n = 0;
end
end

function v = localProp(s, name)
v = [];
try
    if isstruct(s) && isfield(s, name)
        v = s.(name);
    elseif isobject(s) && isprop(s, name)
        v = s.(name);
    end
catch
    v = [];
end
end

function t = localText(v, sep)
if nargin < 2, sep = " "; end
t = "";
if (ischar(v) || isstring(v) || iscellstr(v)) && ~isempty(v)
    t = strjoin(reshape(string(v), 1, []), sep);
    if ismissing(t), t = ""; end
end
end

function t = localFuncText(v)
if isa(v, 'function_handle')
    t = string(func2str(v));
else
    t = localText(v);
end
end

function t = localZoned(v)
% A zoned datetime: the stored clock times are this computer's local time.
t = NaT('TimeZone', 'local');
try
    if isdatetime(v) && ~isempty(v) && ~isnat(v(1))
        t = v(1);
        if isempty(t.TimeZone), t.TimeZone = 'local'; end
    elseif isnumeric(v) && isscalar(v) && v > 7e5
        t = datetime(v, 'ConvertFrom', 'datenum', 'TimeZone', 'local');
    end
catch
end
end

function p = localAbsolute(p)
f = dir(p);
if isscalar(f)
    p = string(fullfile(f.folder, f.name));
end
end
