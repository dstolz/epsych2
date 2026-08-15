function smoke_test_runtime_journal
% smoke_test_runtime_journal
% End-to-end check of the trial journal inside the REAL timer functions:
% ep_TimerFcn_Start -> N x ep_TimerFcn_RunTime (FORCE_TRIAL) -> ep_TimerFcn_Stop,
% over hw.Software and the detection-example protocol. No hardware, no GUI.
%
% Verifies:
%   1) Start creates the seed .mat AND the .epj journal with the info record
%   2) each completed trial lands in the journal, matching RUNTIME.TRIALS.DATA
%   3) Stop merges the journal into the seed .mat with the legacy layout
%      (info + data_0001..data_NNNN), so downstream consumers are unchanged
%
% Run headless: matlab -batch "run('c:\src\epsych2\tmp\smoke_test_runtime_journal.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);
addpath(fullfile(here, '..', 'examples', 'detection_task'));

scratch = fullfile(tempdir, sprintf('runtime_journal_smoke_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);
cleanupScratch = onCleanup(@() localRmdir(scratch));

fprintf('\n=== smoke_test_runtime_journal ===\n');

% --- Build a compiled protocol + CONFIG, as RunExpt.ExptDispatch would ----
P = create_detection_protocol(fullfile(scratch, 'proto.eprot'));
P.compile();

CONFIG = struct();
CONFIG.PROTOCOL = P;
CONFIG.SUBJECT = struct('Name', 'SmokeSubj', 'BoxID', 1);

RUNTIME = epsych.Runtime;
RUNTIME.isTest = true;
RUNTIME.TempDataDir = scratch;
RUNTIME.DefaultDataPath = scratch;
RUNTIME.SessionDataFilename = string(fullfile(scratch, 'smoke_session.mat'));
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces; % connects hw.Software

% --- Start: seeds .mat, creates journal, dispatches trial 1 ---------------
RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);

jfn = regexprep(RUNTIME.DataFile(1), '\.mat$', '.epj');
assert(isfile(RUNTIME.DataFile(1)), 'Start must still create the seed .mat');
assert(isfile(jfn), 'Start must create the journal beside the seed .mat');
[S0, torn0] = epsych.TrialJournal.read(jfn);
assert(~torn0 && isfield(S0, 'info'), 'journal must open with the info record');
fprintf('PASS: 1 Start created seed .mat + journal with info record\n');

% --- Run N forced trials through the real tick ----------------------------
N = 12;
for k = 1:N
    RUNTIME.TRIALS(1).FORCE_TRIAL = true;
    RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
end
assert(RUNTIME.TRIALS(1).TrialIndex == N + 1, 'expected %d completed trials', N);

[S1, torn1] = epsych.TrialJournal.read(jfn);
assert(~torn1, 'journal must be clean after %d trials', N);
for k = 1:N
    rec = S1.(sprintf('data_%04d', k));
    assert(isequaln(rec, RUNTIME.TRIALS(1).DATA(k)), ...
        'journal record %d must equal the in-memory DATA record', k);
end
fprintf('PASS: 2 %d trial records journaled, byte-equal to RUNTIME DATA\n', N);

% --- Stop: merge journal into the seed .mat --------------------------------
RUNTIME = ep_TimerFcn_Stop(RUNTIME);
M = load(RUNTIME.DataFile(1));
names = fieldnames(M);
assert(isfield(M, 'info'), 'merged .mat must keep the info header');
assert(nnz(startsWith(names, 'data_')) == N, 'merged .mat must hold all %d trials', N);
for k = 1:N
    assert(isequaln(M.(sprintf('data_%04d', k)), RUNTIME.TRIALS(1).DATA(k)), ...
        'merged record %d diverges from DATA', k);
end
fprintf('PASS: 3 Stop merged journal into the legacy .mat layout\n');

fprintf('=== smoke_test_runtime_journal: ALL PASS ===\n');
end

function localRmdir(d)
try
    if isfolder(d), rmdir(d, 's'); end
catch
end
end
