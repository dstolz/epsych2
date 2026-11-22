function smoke_test_skip_unchanged_writes
% smoke_test_skip_unchanged_writes
% hw.Interface.SkipUnchangedWrites leaves out, in the trial loop's own
% dispatch, the write of a parameter the device was just read back holding.
% It is off by default and has to be exactly a no-op for the device when on:
% after every dispatch the device must hold what a full dispatch would have
% left, and the session data must be identical. This is the standing proof,
% on a counting device that keeps values in single precision as a TDT tag
% does.
%
% Verifies:
%   1) off (the default): every dispatched parameter is written every trial
%   2) on: a parameter is written only when the device does not already hold
%      its value -- and the device ends every dispatch holding exactly what
%      a full dispatch leaves
%   3) the saved trial data is identical with it off and on
%   4) the first dispatch of a run, and a dispatch made by anything but the
%      trial loop (a regenerated trial), write everything
%   5) a parameter written between the trial-end read and the dispatch --
%      through hw.Parameter or straight through the backend -- is written
%   6) a read-back from before the trial ended excuses nothing; neither does
%      one taken before the interface was invalidated
%   7) outside a dispatch an identical write is always sent
%   8) write-only parameters, NaN, and a refused write are never skipped over
%   9) an interface that left the setting off is untouched by another's
%
% No hardware, no windows.
%
%   matlab -batch "run('tmp/smoke_test_skip_unchanged_writes.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

fprintf('\n=== smoke_test_skip_unchanged_writes ===\n');

scratch = fullfile(tempdir, sprintf('smoke_skipwrites_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);
cleanupScratch = onCleanup(@() localRmdir(scratch));

NTRIALS = 12;

% --- 1. off: everything is written -------------------------------------------
[RUNTIME, dev, P] = localSession(scratch, 'off', false);
nDispatched = localNumDispatched(RUNTIME);
assert(nDispatched == 5, 'expected 5 dispatched parameters, got %d', nDispatched);
for k = 1:NTRIALS
    dev.resetCounts();
    RUNTIME = localTrial(RUNTIME);
    assert(dev.Counts.Write == nDispatched && dev.Counts.Skipped == 0, ...
        'off: every dispatched parameter is written (trial %d: %d written, %d skipped)', ...
        k, dev.Counts.Write, dev.Counts.Skipped);
end
assert(dev.WritesSkipped == 0, 'off: nothing is ever counted as skipped');
dataOff = localData(RUNTIME);
localEnd(RUNTIME);
fprintf('PASS: 1 off by default: %d writes per trial, none skipped\n', nDispatched);

% --- 2. on: only what the device does not hold is written --------------------
[RUNTIME, dev, P] = localSession(scratch, 'on', true);
totalSkipped = 0;
for k = 1:NTRIALS
    dev.resetCounts();
    RUNTIME = localTrial(RUNTIME);
    c = dev.Counts;
    assert(c.Write + c.Skipped == nDispatched, ...
        'trial %d: %d written + %d skipped should be the %d dispatched', ...
        k, c.Write, c.Skipped, nDispatched);
    % The write-only parameter can never be read back, so it is always sent;
    % the randomized one changes every trial.
    assert(c.Write >= 2, 'trial %d: the write-only and random parameters must be written', k);
    totalSkipped = totalSkipped + c.Skipped;

    % What the device holds is what a full dispatch would have left: the
    % host's value for each dispatched parameter, in single precision.
    names = fieldnames(P);
    for j = 1:numel(names)
        p = P.(names{j});
        [hv, known] = p.hostValue();
        assert(known, 'no host value for %s', p.Name);
        assert(isequal(dev.held(p), double(single(hv))), ...
            'trial %d: the device holds %g for %s where a full dispatch leaves %g', ...
            k, dev.held(p), p.Name, double(single(hv)));
    end
end
assert(totalSkipped >= 2 * NTRIALS, ...
    'the fixed parameter and the expression should be skipped every trial (%d skips in %d trials)', ...
    totalSkipped, NTRIALS);
assert(dev.WritesSkipped == totalSkipped, 'the interface counts what the parameters skipped');
dataOn = localData(RUNTIME);
fprintf('PASS: 2 on: %d of %d writes left out, device state identical to a full dispatch\n', ...
    totalSkipped, nDispatched * NTRIALS);

% --- 3. the saved data is the same -------------------------------------------
assert(isequal(fieldnames(dataOff), fieldnames(dataOn)), 'trial record fields differ');
assert(numel(dataOff) == numel(dataOn), 'trial counts differ');
fn = setdiff(fieldnames(dataOff), {'computerTimestamp'});
for k = 1:numel(dataOff)
    for j = 1:numel(fn)
        a = dataOff(k).(fn{j});
        b = dataOn(k).(fn{j});
        assert(isequaln(a, b) && strcmp(class(a), class(b)), ...
            'trial %d field %s differs with the setting on', k, fn{j});
    end
end
fprintf('PASS: 3 the trial data is identical off and on (%d trials, %d fields)\n', numel(dataOn), numel(fn));

% --- 4. the first dispatch, and any dispatch but the trial loop's ------------
dev.resetCounts();
RUNTIME.dispatchNextTrial(1);                 % as gui.components.RegenerateTrial does
assert(dev.Counts.Write == nDispatched && dev.Counts.Skipped == 0, ...
    'a dispatch not made by the trial loop writes everything (%d written, %d skipped)', ...
    dev.Counts.Write, dev.Counts.Skipped);
assert(~dev.DispatchMaySkip && ~dev.InDispatch, 'the dispatcher clears its flags');
localEnd(RUNTIME);

rng(7);
[RUNTIME, dev, P, firstWrites] = localSession(scratch, 'first', true);
assert(firstWrites.Write == nDispatched && firstWrites.Skipped == 0, ...
    'the first dispatch of a run writes everything (%d written, %d skipped)', ...
    firstWrites.Write, firstWrites.Skipped);
fprintf('PASS: 4 the first dispatch and a regenerated trial write everything\n');

% --- 5. written between the trial-end read and the dispatch ------------------
% The dangerous case: the read-back says the device holds the trial's value,
% something then changes it, and the dispatch must put it back.
events = RUNTIME.EVENTS;
fixedValue = P.Fixed.hostValue();
h = addlistener(events, 'NewData', @(~,~) localAssign(P.Fixed, 0.5));
RUNTIME = localTrial(RUNTIME);
delete(h);
assert(isequal(dev.held(P.Fixed), double(single(fixedValue))), ...
    'a write through hw.Parameter inside the boundary must be undone by the dispatch (device holds %g)', ...
    dev.held(P.Fixed));

h = addlistener(events, 'NewData', @(~,~) dev.set_parameter(P.Fixed, 0.75));
RUNTIME = localTrial(RUNTIME);
delete(h);
assert(isequal(dev.held(P.Fixed), double(single(fixedValue))), ...
    'a write straight through the backend inside the boundary must be undone too (device holds %g)', ...
    dev.held(P.Fixed));

h = addlistener(events, 'NewData', @(~,~) dev.invalidateDeviceValues());
dev.resetCounts();
RUNTIME = localTrial(RUNTIME);
delete(h);
assert(dev.Counts.Skipped == 0 && dev.Counts.Write == nDispatched, ...
    'an interface invalidated after the trial-end read writes everything');
fprintf('PASS: 5 a write or an invalidation inside the boundary forces the dispatch write\n');

% --- 6, 7. the evidence rules, on one parameter ------------------------------
p = P.Fixed;
v = p.hostValue();
dev.resetCounts();
p.Value = v;
assert(dev.Counts.Write == 1 && dev.Counts.Skipped == 0, 'outside a dispatch an identical write is sent');
[~] = p.Value;                                 % read back: evidence
p.Value = v;
assert(dev.Counts.Write == 2, 'evidence does not excuse a write outside a dispatch');

[~] = p.Value;
dev.invalidateDeviceValues();                  % what the trial loop does before its read
localAllowSkip(dev, true);
p.Value = v;
localAllowSkip(dev, false);
assert(dev.Counts.Write == 3 && dev.Counts.Skipped == 0, ...
    'a read-back from before the invalidation excuses nothing');

[~] = p.Value;
localAllowSkip(dev, true);
p.Value = v;
p.Value = v;                                   % still unchanged, still read back holding it
localAllowSkip(dev, false);
assert(dev.Counts.Write == 3 && dev.Counts.Skipped == 2, ...
    'with a current read-back the unchanged write is left out (%d written, %d skipped)', ...
    dev.Counts.Write, dev.Counts.Skipped);

[~] = p.Value;
localAllowSkip(dev, true);
p.Value = v + 1;                               % changed: written, and the evidence is spent
p.Value = v + 1;                               % no read-back since that write: written again
localAllowSkip(dev, false);
assert(dev.Counts.Write == 5, 'a changed value is written, and so is the next one without a read-back');
p.Value = v;
fprintf('PASS: 6 7 only a current read-back excuses a write, and only inside a dispatch\n');

% --- 8. never skipped: write-only, NaN, after a refused write ----------------
dev.resetCounts();
localAllowSkip(dev, true);
P.WriteOnly.Value = P.WriteOnly.hostValue();
localAllowSkip(dev, false);
assert(dev.Counts.Write == 1 && dev.Counts.Skipped == 0, 'a write-only parameter is always written');

pn = P.Roved;
dev.put(pn, NaN);
[~] = pn.Value;
dev.resetCounts();
localAllowSkip(dev, true);
pn.Value = NaN;
localAllowSkip(dev, false);
assert(dev.Counts.Write == 1, 'NaN never counts as already held');

dev.RefuseWrites = {'Roved'};
[~] = p.Value;                                 % current evidence for Fixed
localAllowSkip(dev, true);
pn.Value = 2;                                  % refused: the device is not as the host thought
dev.resetCounts();
p.Value = v;
localAllowSkip(dev, false);
dev.RefuseWrites = {};
assert(dev.Counts.Write == 1 && dev.Counts.Skipped == 0, ...
    'after a refused write nothing read earlier excuses a write');
fprintf('PASS: 8 write-only, NaN and the writes after a refusal are always sent\n');

% --- 9. another interface is untouched ---------------------------------------
sw = RUNTIME.Interfaces(arrayfun(@(h) isa(h, 'hw.Software'), RUNTIME.Interfaces));
assert(isscalar(sw) && ~sw.SkipUnchangedWrites && sw.WritesSkipped == 0, ...
    'the software interface never asked and never skipped');
localEnd(RUNTIME);
fprintf('PASS: 9 an interface that did not opt in is untouched\n');

fprintf('smoke_test_skip_unchanged_writes: ALL PASS\n');
end


% -----------------------------------------------------------------------------
function [RUNTIME, dev, P, firstWrites] = localSession(scratch, tag, skip)
% A started session over a counting device that keeps single precision.
% Five dispatched parameters: one fixed, one roved, one randomized, one whose
% value is an expression of the fixed one, one write-only.
rng(7);   % the same draws for every session built here

prot = epsych.Protocol(Info = 'skip_unchanged_writes');
dev = CountingProbeInterface(CoerceSingle = true);
dev.SkipUnchangedWrites = skip;
prot.addInterface(dev);

P = struct();
P.Fixed = dev.add_parameter('Fixed', 0.1);
P.Roved = dev.add_parameter('Roved', [1 2 3]);
P.Rand  = dev.add_parameter('Rand', 5, Min = 1, Max = 9);
P.Rand.isRandom = true;
P.Expr  = dev.add_parameter('Expr', 0);
P.Expr.Expression = "Fixed + 250";
P.WriteOnly = dev.add_parameter('WriteOnly', 3.3, Access = 'Write');

q = dev.add_parameter('RespCode', 0, Type = 'Integer', Access = 'Read');
dev.put(q, epsych.BitMask.Bits2Mask(uint32([epsych.BitMask.Hit epsych.BitMask.TrialType_0])));
for nm = ["x_NewTrial_1" "x_ResetTrig_1" "x_TrialComplete_1"]
    q = dev.add_parameter(char(nm), 0, isTrigger = true);
    dev.put(q, 0);
end

prot.compile();
assert(prot.COMPILED.ntrials > 0, 'test protocol did not compile');

CONFIG = struct();
CONFIG.PROTOCOL = prot;
CONFIG.SUBJECT = struct('Name', 'SkipSubj', 'BoxID', 1);

RUNTIME = epsych.Runtime;
RUNTIME.isTest = true;
RUNTIME.TempDataDir = scratch;
RUNTIME.DefaultDataPath = scratch;
RUNTIME.SessionDataFilename = string(fullfile(scratch, sprintf('skip_%s.mat', tag)));
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = prot.Interfaces;
set(RUNTIME.Interfaces, 'mode', hw.DeviceState.Preview);

dev.resetCounts();
RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);   % dispatches trial 1
firstWrites = dev.Counts;
end

function n = localNumDispatched(RUNTIME)
T = RUNTIME.TRIALS(1);
n = nnz(~strcmp({T.parameters.Access}, 'Read') & [T.parameters.UpdateEveryTrial]);
end

function RUNTIME = localTrial(RUNTIME)
RUNTIME.TRIALS(1).FORCE_TRIAL = true;
RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
end

function D = localData(RUNTIME)
D = RUNTIME.TRIALS(1).DATA;
end

function localEnd(RUNTIME)
try
    RUNTIME = ep_TimerFcn_Stop(RUNTIME);
    delete(RUNTIME);
catch ME
    vprintf(0, 1, ME);
end
end

function localAssign(p, v)
p.Value = v;
end

function localAllowSkip(dev, tf)
% Stand in for the dispatcher: what dispatchNextTrial(i, AllowSkip=true) sets.
dev.InDispatch = tf;
dev.DispatchMaySkip = tf && dev.SkipUnchangedWrites;
end

function localRmdir(d)
try
    if isfolder(d), rmdir(d, 's'); end
catch
end
end
