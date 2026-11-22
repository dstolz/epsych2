function S = bench_rig_preview(options)
% S = bench_rig_preview(Subject="SUBJ-ID-1171")
% S = bench_rig_preview(Subject=..., NumTrials=250, ProfileTrials=20)
% What a real session costs on this rig: a Preview of one roster subject run
% through epsych.RunExpt on the rig's own hardware, with a simulated animal
% completing the trials, timed trial by trial.
%
% tmp/bench_trial_boundary.m counts device calls against a stand-in and needs
% no hardware. This is the other half: the subject's own roster membership,
% protocol, circuit and behavior GUI, started with the session window's
% Preview button, so the numbers include everything that benchmark leaves out
% -- the real device, every on-screen control, and the displays as they
% render in a visible window.
%
% THE HARDWARE RUNS. The circuit is loaded, sound plays, and the simulated
% subject (tmp/RigPreviewSubject.m) earns rewards: on the appetitive platform
% task about two trials in three fire the pellet dispenser. A trial takes
% about 5.5 s, so 250 trials is some 25 minutes.
%
% What is and is not the subject's real session:
%   * The lab's roster is only READ. The commit that puts the subject in the
%     session writes protocol memory back, so it is made on a copy.
%   * The saving function is replaced with ep_SaveDataFcn, which writes
%     nothing for a Preview. A lab's own saving function may have no such
%     guard (cl_SaveDataFcn opens a modal reminder and writes a file into the
%     animal's data folder).
%   * The RunTime timer function is wrapped by tmp/bench_rig_tick.m, which
%     calls the real one.
%   * Trial-loop timing is switched on for this run alone, on the runtime; the
%     EPsych/TickStats preference is not touched.
%   * The run's crash-recovery files are deleted when it ends.
%
% Timings are read by tmp/bench_rig_report.m, which this calls. Two things to
% know before reading them: the first five or so boundaries are warm-up
% (0.2-2 s) and are left out of every summary, and a share of boundaries --
% one in five on this rig in November 2026 -- run several times slower than
% the rest in every phase at once, so medians and "fast"/"slow" are reported
% separately. See documentation/overviews/Runtime_Performance.md.
%
% Close RunExpt first: this opens a session window of its own and refuses to
% start beside another.
%
% Name=Value options:
%   Subject        - (required) roster subject, by Name or SubjectID
%   Project        - project, by Name or ProjectID. Needed only when the
%                    subject is an active member of more than one
%   Roster         - .esub file. Default: the rig's configured roster
%   NumTrials      - trials to time. Default 250
%   ProfileTrials  - further trials run under the MATLAB profiler, reported
%                    per function and, for the toolbox's own files, per line.
%                    They are not in the timings. Default 0
%   Threshold, Slope, FalseAlarmRate, LapseRate, AbortRate, Seed
%                  - the simulated subject; see RigPreviewSubject
%   OutFile        - .mat to save the results to. Default: a dated file in
%                    tempdir, named in the report
%   Screenshot     - .png to write of the behavior GUI as the session left it
%   Quiet          - no printed report. Default false
%
% Returns the results struct bench_rig_report reads; S.Outcome is 'complete'
% when every trial ran.
%
%   matlab -batch "addpath('C:\src\epsych2\tmp'); bench_rig_preview(Subject='SUBJ-ID-1171', NumTrials=40)"
%
% See also: RigPreviewSubject, bench_rig_tick, bench_rig_report,
%           bench_trial_boundary, epsych.TickStats, hw.benchmarkIO

arguments
    options.Subject (1,1) string
    options.Project (1,1) string = ""
    options.Roster (1,1) string = ""
    options.NumTrials (1,1) double {mustBePositive, mustBeInteger} = 250
    options.ProfileTrials (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    options.Threshold (1,1) double = -12
    options.Slope (1,1) double {mustBePositive} = 3
    options.FalseAlarmRate (1,1) double = 0.10
    options.LapseRate (1,1) double = 0.03
    options.AbortRate (1,1) double = 0.07
    options.Seed (1,1) double = 1
    options.OutFile (1,1) string = ""
    options.Screenshot (1,1) string = ""
    options.Quiet (1,1) logical = false
end
assert(isfield(options, 'Subject'), 'bench_rig_preview:NoSubject', ...
    'Name the roster subject to run: bench_rig_preview(Subject="...")');

% Start the toolbox from THIS checkout unless it already is: an operator's
% session keeps its path, and a second run in one MATLAB stays as warm as a
% second session of the day would be (re-running startup rebuilds the path,
% which makes MATLAB re-resolve every function).
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
if ~startsWith(which('epsych.RunExpt'), root, 'IgnoreCase', true)
    run(fullfile(root, 'epsych_startup.m'));
end
addpath(here);

open = findall(groot, 'Type', 'figure', 'Tag', 'RunExpt');
assert(isempty(open), 'bench_rig_preview:SessionWindowOpen', ...
    'A RunExpt window is open. Close it first: this benchmark runs a session of its own on the same hardware.');

scratch = fullfile(tempdir, sprintf('bench_rig_preview_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);
cleanupScratch = onCleanup(@() localRmdir(scratch));

% --- the subject, from a copy of the roster ---------------------------------
rosterFile = char(options.Roster);
if isempty(rosterFile)
    rosterFile = epsych.SubjectRoster.configuredFile();
end
assert(~isempty(rosterFile) && isfile(rosterFile), 'bench_rig_preview:NoRoster', ...
    'No roster file to read ("%s"). Pass Roster=, or choose one in the Subjects window.', rosterFile);
rosterCopy = fullfile(scratch, 'roster_copy.esub');
copyfile(rosterFile, rosterCopy, 'f');
R = epsych.SubjectRoster(rosterCopy);

subject = R.findSubject(char(options.Subject));
assert(~isempty(subject), 'bench_rig_preview:UnknownSubject', ...
    'The roster "%s" has no subject "%s".', rosterFile, options.Subject);
project = localProject(R, subject, options.Project);

% --- the session, as the operator assembles it ------------------------------
% Windows save their position and state under a preference group as they
% close. The ones this run opens are not the operator's, so each group is
% remembered as it stands and put back afterwards (the map is filled again
% once the behavior GUI exists).
kept = containers.Map('KeyType', 'char', 'ValueType', 'any');
kept('RunExpt') = localPrefs('RunExpt');

figuresBefore = findall(groot, 'Type', 'figure');
rx = epsych.RunExpt(ReuseExisting = false);
cleanupSession = onCleanup(@() localEndSession(rx, figuresBefore, kept));

report = R.assignToSession(rx, {subject.SubjectID}, ProjectID = project.ProjectID, ReplaceExisting = true);
assert(report.ok, 'bench_rig_preview:CommitRefused', 'The subject could not be added to the session: %s', report.message);
assert(rx.STATE >= PRGMSTATE.READY, 'bench_rig_preview:NotReady', ...
    'The session is %s, not ready to run.', char(string(rx.STATE)));

info = struct();
info.Subject = subject.Name;
info.Project = project.Name;
info.Protocol = string(char(rx.CONFIG(1).protocol_fn));
info.ProtocolVersion = string(rx.CONFIG(1).PROTOCOL.meta.protocolVersion);
info.BehaviorGUI = string(rx.FUNCS.BehaviorGUI);
info.SavingFcn = string(rx.FUNCS.SavingFcn);
info.RunTimeFcn = string(rx.FUNCS.TIMERfcn.RunTime);

rx.FUNCS.SavingFcn = 'ep_SaveDataFcn';
bench_rig_tick('init', rx.FUNCS.TIMERfcn.RunTime);
rx.FUNCS.TIMERfcn.RunTime = 'bench_rig_tick';

sim = RigPreviewSubject(rx, NumTrials = options.NumTrials, ProfileTrials = options.ProfileTrials, ...
    Threshold = options.Threshold, Slope = options.Slope, FalseAlarmRate = options.FalseAlarmRate, ...
    LapseRate = options.LapseRate, AbortRate = options.AbortRate, Seed = options.Seed, ...
    MaxSeconds = max(600, 15 * (options.NumTrials + options.ProfileTrials)));
cleanupSim = onCleanup(@() delete(sim));

% --- Preview, with the window's own button ----------------------------------
rx.H.ctrl_preview.ButtonPushedFcn(rx.H.ctrl_preview, []);
t0 = tic;
while rx.STATE ~= PRGMSTATE.RUNNING && rx.STATE ~= PRGMSTATE.ERROR && toc(t0) < 120
    pause(0.25);
end
assert(rx.STATE == PRGMSTATE.RUNNING, 'bench_rig_preview:NotRunning', ...
    'The Preview did not start (the session is %s). The log says why: Help > Diagnostics > Open Current Error Log.', ...
    char(string(rx.STATE)));
pause(2);                               % the behavior GUI finishes drawing itself
for f = localOpened(rx, figuresBefore)'
    tag = char(f.Tag);                  % a behavior GUI's Tag is its preference group
    if ~isempty(tag) && ~isKey(kept, tag)
        kept(tag) = localPrefs(tag);
    end
end

% This function only waits from here. Everything that reads the runtime is
% in the simulated subject's timer callback; a pause loop and a MATLAB left
% idle at its prompt measured the same.
sim.start();
limit = tic;
while ~sim.Finished && toc(limit) < sim.MaxSeconds + 240
    pause(0.5);
end
assert(sim.Finished, 'bench_rig_preview:Unfinished', 'The simulated subject never finished; the session is being stopped.');

% --- what was recorded -------------------------------------------------------
S = sim.Results;
E = EPsychInfo;
S.Info = info;
S.Info.Commit = string(E.chksum);
S.Info.Release = string(version('-release'));
S.Info.Desktop = usejava('desktop');
S.Info.Batch = batchStartupOptionUsed;
S.Info.When = datetime('now');
gui = localOpened(rx, figuresBefore);
if ~isempty(gui)
    ax = findall(gui(1), 'Type', 'axes');
    if ~isempty(ax)
        ri = rendererinfo(ax(1));
        S.Info.Renderer = string(ri.GraphicsRenderer) + " | " + string(ri.RendererDevice);
    end
    if strlength(options.Screenshot) > 0
        drawnow
        exportapp(gui(1), char(options.Screenshot));
    end
end
if ispc
    S.Info.Priority = string(System.Diagnostics.Process.GetCurrentProcess().PriorityClass);
end

% The run's crash-recovery seed and journal are this benchmark's own.
seed = rx.RUNTIME.DataFile;
for f = [seed(:)', regexprep(seed(:)', '\.mat$', '.epj')]
    if isfile(f), delete(f); end
end

outFile = options.OutFile;
if strlength(outFile) == 0
    stamp = char(datetime('now', Format = 'yyMMdd''T''HHmmss'));
    outFile = string(fullfile(tempdir, ['bench_rig_preview_' stamp '.mat']));
end
save(outFile, '-struct', 'S');
S.Info.OutFile = outFile;

if ~options.Quiet
    bench_rig_report(S);
end
end


function project = localProject(R, subject, wanted)
% The project whose membership carries this subject's session settings.
if strlength(wanted) > 0
    project = R.findProject(char(wanted));
    assert(~isempty(project), 'bench_rig_preview:UnknownProject', 'The roster has no project "%s".', wanted);
    return
end
all = R.projectsForSubject(subject.SubjectID);
active = false(1, numel(all));
for k = 1:numel(all)
    m = R.findMembership(subject.SubjectID, all(k).ProjectID);
    active(k) = ~isempty(m) && m.Active && ~all(k).Archived;
end
all = all(active);
assert(isscalar(all), 'bench_rig_preview:WhichProject', ...
    '"%s" is an active member of %d projects (%s). Say which with Project=.', ...
    subject.Name, numel(all), strjoin({all.Name}, ', '));
project = all;
end


function localEndSession(rx, figuresBefore, kept)
% Leave the rig as it was found: session stopped, hardware idle, the windows
% this run opened closed and their saved layouts as they were. Runs on every
% way out, an error included.
putBack = onCleanup(@() localPutBack(kept));
if ~isvalid(rx), return; end
% The simulated subject first, if an error left it stepping on and off.
t = timerfindall('Name', 'RigPreviewSubject');
if ~isempty(t)
    stop(t);
    delete(t);
end
if rx.STATE == PRGMSTATE.RUNNING
    rx.halt();
end
I = rx.RUNTIME.Interfaces;
for k = 1:numel(I)
    if isvalid(I(k)) && I(k).IsConnected
        I(k).mode = hw.DeviceState.Idle;
    end
end
% The behavior GUI before the session window: its components stop their own
% timers as they go.
opened = localOpened(rx, figuresBefore);
for k = 1:numel(opened)
    if isvalid(opened(k)), close(opened(k)); end
end
drawnow
delete(opened(isvalid(opened)));
% Deleting the session object runs its close sequence: the hardware is
% released and the window removed. The session was halted above, so there is
% nothing left for it to stop.
if isvalid(rx), delete(rx); end
end


function f = localOpened(rx, figuresBefore)
% Figures this run opened, the session window aside.
f = findall(groot, 'Type', 'figure');
f = f(~ismember(f, [figuresBefore; rx.H.figure1]));
end


function was = localPrefs(group)
% A preference group as it is now; [] when it does not exist.
if ispref(group)
    was = getpref(group);
else
    was = [];
end
end


function localPutBack(kept)
% Put every remembered preference group back as it was found. Field by
% field: a group is never removed whole and rebuilt, so an interruption
% cannot lose one.
groups = keys(kept);
for k = 1:numel(groups)
    g = groups{k};
    was = kept(g);
    if ~isstruct(was)
        if ispref(g), rmpref(g); end
        continue
    end
    names = fieldnames(was);
    for j = 1:numel(names)
        setpref(g, names{j}, was.(names{j}));
    end
    added = setdiff(fieldnames(getpref(g)), names);
    if ~isempty(added), rmpref(g, added); end
end
end


function localRmdir(d)
if isfolder(d), rmdir(d, 's'); end
end
