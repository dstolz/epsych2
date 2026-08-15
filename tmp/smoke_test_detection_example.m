function smoke_test_detection_example
% smoke_test_detection_example
% Exercises the examples/detection_task worked example end to end with no
% hardware. Headless-safe (uifigure works under -batch).
%
% Verifies:
%   1) create_detection_protocol builds, compiles (6 paired conditions),
%      saves, and reloads with the custom selector wired in
%   2) ExampleDetectionSelector policy: catch probability, run cap,
%      balanced go levels, onComplete tally, onRecompile count preservation
%   3) run_detection_session drives a full simulated session with
%      DetectionBoxGUI attached and writes a Data+Info session file whose
%      records show the ITI randomization and RespWinDelay expression
%   4) explore_saved_data decodes the file and returns sane performance
%
% Run headless: matlab -batch "run('tmp/smoke_test_detection_example.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);
addpath(fullfile(here, '..', 'examples', 'detection_task'));

tmpdir = fullfile(tempdir, 'smoke_test_detection_example');
if isfolder(tmpdir), rmdir(tmpdir, 's'); end
mkdir(tmpdir);
cleanup = onCleanup(@() cleanupAll(tmpdir));

% 1. Protocol builds, compiles, saves, reloads ---------------------------
protFile = fullfile(tmpdir, 'DetectionExample.eprot');
P = create_detection_protocol(protFile);
assert(isfile(protFile), 'protocol file was not written');
assert(P.COMPILED.ntrials == 6, ...
    'expected 6 paired conditions, got %d', P.COMPILED.ntrials);
assert(all(ismember({'TrialType', 'ToneLevel', 'ITI', 'RespWinDelay'}, ...
    P.COMPILED.writeparams)), 'expected writeparams missing');

P2 = epsych.Protocol.load(protFile);
if P2.needsCompile, P2.compile(); end
assert(P2.COMPILED.ntrials == 6, 'reloaded protocol compiled %d trials', ...
    P2.COMPILED.ntrials);
assert(strcmp(P2.Options.trialFunc, 'ExampleDetectionSelector'), ...
    'trialFunc lost on save/load round trip');
fprintf('PASS: protocol create/compile/save/load\n');

% 2. Selector policy ------------------------------------------------------
rng(0);
T = struct;
T.parameters  = P.COMPILED.parameters;
T.trials      = P.COMPILED.trials;
T.writeparams = P.COMPILED.writeparams;
idx = struct;
for k = 1:numel(T.writeparams)
    idx.(T.writeparams{k}) = k;
end
T.writeParamIdx = idx;

sel = ExampleDetectionSelector;
sel.initialize(T);
types = cell2mat(T.trials(:, idx.TrialType));

NSEL = 400;
seq = zeros(1, NSEL);
for k = 1:NSEL
    seq(k) = types(sel.selectNext(T));
end
frac = mean(seq == 1);
assert(frac > 0.10 && frac < 0.45, ...
    'catch fraction %.2f outside expected band', frac);
runLengths = diff([0, find(diff(seq) ~= 0), NSEL]);
assert(max(runLengths) <= sel.MaxConsecutive, ...
    'run of %d same-type trials exceeds cap %d', max(runLengths), sel.MaxConsecutive);
goCounts = sel.TrialCount(types == 0);
assert(max(goCounts) - min(goCounts) <= 1, ...
    'go levels not balanced: %s', mat2str(goCounts'));

rcHit = bitset(bitset(uint32(0), uint32(epsych.BitMask.Hit)), ...
    uint32(epsych.BitMask.TrialType_0));
sel.onComplete(1, struct('RespCode', double(rcHit)));
assert(sel.nHits == 1, 'onComplete did not tally the hit');

c0 = sel.TrialCount;
sel.onRecompile(T);
assert(isequal(sel.TrialCount, c0), ...
    'onRecompile must preserve counts when the trial list size is unchanged');
fprintf('PASS: selector policy (catch %.0f%%, max run %d, balanced levels)\n', ...
    100 * frac, max(runLengths));

% 3. Simulated session with the behavior GUI, headless ------------------------
dataPath = fullfile(tmpdir, 'data');
NTRIALS = 60;
rt = run_detection_session(NumTrials = NTRIALS, ShowGUI = true, ...
    ProtocolFile = protFile, DataPath = dataPath, Seed = 1);
assert(numel(rt.TRIALS(1).DATA) == NTRIALS, ...
    'DATA has %d records, expected %d', numel(rt.TRIALS(1).DATA), NTRIALS);

d = dir(fullfile(dataPath, '*.mat'));
assert(isscalar(d), 'expected exactly one session file, found %d', numel(d));
datafile = fullfile(d(1).folder, d(1).name);
S = load(datafile);
assert(isfield(S, 'Data') && isfield(S, 'Info'), ...
    'session file must carry Data and Info variables');
assert(numel(S.Data) == NTRIALS, 'saved Data has %d records', numel(S.Data));

req = {'RespCode', 'ToneLevel', 'TrialType', 'ToneDur', 'ITI', 'RespWinDelay', ...
    'InTrial', 'TrialIndex', 'TrialID', 'computerTimestamp', 'isTest'};
have = isfield(S.Data, req);
assert(all(have), 'missing DATA fields: %s', strjoin(req(~have), ', '));

itis = [S.Data.ITI];
assert(numel(unique(itis)) > 1 && all(itis >= 2000 & itis <= 4000), ...
    'ITI should randomize within [2000 4000] every trial');
assert(all([S.Data.RespWinDelay] == [S.Data.ToneDur] + 250), ...
    'RespWinDelay expression did not evaluate on dispatch');

fig = findall(groot, 'Type', 'figure', 'Tag', 'DetectionBoxGUI');
assert(isscalar(fig), 'DetectionBoxGUI figure not found');
box = fig.UserData;
assert(isa(box, 'DetectionBoxGUI'), 'figure UserData should be the GUI object');
assert(~isempty(box.SummaryTable.Data), 'performance table never populated');
assert(contains(box.TrialLabel.Text, 'Trial'), ...
    'trial label never updated: "%s"', box.TrialLabel.Text);
assert(strcmp(box.ModeLabel.Text, 'Mode: Stop'), ...
    'mode label should end at Stop, got "%s"', box.ModeLabel.Text);
close(fig) % exercises closeGUI/teardown
fprintf('PASS: simulated session + DetectionBoxGUI (%d trials)\n', NTRIALS);

% 4. Offline analysis -----------------------------------------------------
R = explore_saved_data(datafile);
assert(R.nTrials == NTRIALS, 'analysis saw %d trials', R.nTrials);
assert(isequal(R.levels(:)', [20 30 40 50 60]), ...
    'unexpected go levels: %s', mat2str(R.levels));
assert(all(isfinite(R.dprime)), 'd'' must be finite with corrections applied');
assert(R.dprime(end) > R.dprime(1), ...
    'd'' at 60 dB should exceed d'' at 20 dB for the seeded observer');
fprintf('PASS: offline analysis (FA %.2f, d''(60 dB) = %.2f)\n', ...
    R.faRate, R.dprime(end));

fprintf('smoke_test_detection_example: ALL PASS\n');
end


function cleanupAll(tmpdir)
close(findall(groot, 'Type', 'figure'));
if isfolder(tmpdir)
    try
        rmdir(tmpdir, 's');
    catch
    end
end
end
