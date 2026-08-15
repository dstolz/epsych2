function smoke_test_pcatch_hazard()
% smoke_test_pcatch_hazard()
% Exercise the catch-trial hazard in cl_AppetitiveStimDetect: the pure
% cl_AppetitiveStimDetect.advanceHazard step rule against hand-built
% outcomes, then the selector end-to-end against a software-only runtime
% (P_Catch_Current creation, run length bounds, the no-DATA session-start
% call, and a mid-session step change). Headless-safe: no figures, no
% hardware.
%
%   matlab -batch "run('tmp/smoke_test_pcatch_hazard.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

TT_STIM  = 0;
TT_CATCH = 1;

% Bind the trial-type codes once. adv() advances by one completed trial;
% replay() folds it over a whole sequence and returns every intermediate
% probability, which is how the accumulating behavior is checked.
adv = @(p,flags,mn,st,mx) cl_AppetitiveStimDetect.advanceHazard( ...
    p, decodeSeq({flags}), TT_STIM, TT_CATCH, mn, st, mx);
replay = @(p0,seq,mn,st,mx) foldHazard(p0, seq, TT_STIM, TT_CATCH, mn, st, mx);


% 1. One step per delivered stimulus trial, saturating at Max -------------
p = replay(0, repmat({{'TrialType_0','Hit'}},1,3), 0, 0.1, 1);
assertNear(p(end), 0.3, 'three stimulus trials should give three steps');
assertNear(p, [0.1 0.2 0.3], 'the hazard should climb one step at a time');

p = replay(0, repmat({{'TrialType_0','Miss'}},1,12), 0, 0.1, 1);
assertNear(p(end), 1, 'the hazard should saturate at Max');
assert(all(p <= 1), 'the hazard should never exceed Max');

% Overshoot from a raised floor still clamps to Max, never past it.
p = replay(0.2, repmat({{'TrialType_0','Hit'}},1,3), 0.2, 0.5, 0.9);
assertNear(p(end), 0.9, 'a step past Max should clamp to Max');
fprintf('PASS: one step per stimulus trial, clamped to [Min Max]\n');


% 2. A completed catch trial resets the hazard ----------------------------
p = replay(0, [repmat({{'TrialType_0','Hit'}},1,3), {{'TrialType_1','CorrectReject'}}], 0, 0.1, 1);
assertNear(p(end), 0, 'a completed catch trial should reset to Min');

% The reset goes to Min, not to zero.
p = replay(0.25, {{'TrialType_1','CorrectReject'}}, 0.25, 0.1, 1);
assertNear(p(end), 0.25, 'the reset should land on Min, not zero');

% ...and climbing restarts from the reset, not from the top of the session.
p = replay(0, [repmat({{'TrialType_0','Hit'}},1,3), {{'TrialType_1','FalseAlarm'}}, ...
    repmat({{'TrialType_0','Hit'}},1,2)], 0, 0.1, 1);
assertNear(p(end), 0.2, 'climbing should restart after the catch trial');
fprintf('PASS: completed catch trial resets the hazard\n');


% 3. Aborts are inert on both sides ---------------------------------------
% An aborted stimulus trial never delivered a stimulus, so it must not
% advance the hazard.
p = replay(0, [repmat({{'TrialType_0','Hit'}},1,3), {{'TrialType_0','Abort'}}], 0, 0.1, 1);
assertNear(p(end), 0.3, 'an aborted stimulus trial should not advance the hazard');

% An aborted catch trial never measured a false-alarm rate, so it must not
% reset the hazard.
assertNear(adv(0.2, {'TrialType_1','Abort'}, 0, 0.1, 1), 0.2, ...
    'an aborted catch trial should leave the hazard untouched');

% ...and the next delivered stimulus trial keeps climbing from there.
p = replay(0, [repmat({{'TrialType_0','Hit'}},1,2), {{'TrialType_1','Abort'}}, ...
    {{'TrialType_0','Hit'}}], 0, 0.1, 1);
assertNear(p, [0.1 0.2 0.2 0.3], 'the hazard should climb across an aborted catch trial');
fprintf('PASS: aborts advance nothing and reset nothing\n');


% 4. Reminder trials do not advance the hazard ----------------------------
assertNear(adv(0.3, {'TrialType_2','Hit'}, 0, 0.1, 1), 0.3, ...
    'a reminder trial should not advance the hazard');
fprintf('PASS: reminder trials are ignored by the hazard\n');


% 5. A step change applies from here, never retroactively -----------------
% Five stimulus trials at 0.1 sit at 0.5; switching the step to 0.2 must
% take the NEXT trial to 0.7, not rescale the history to 1.0.
p = replay(0, repmat({{'TrialType_0','Hit'}},1,5), 0, 0.1, 1);
assertNear(p(end), 0.5, 'five steps of 0.1 should sit at 0.5');
assertNear(adv(p(end), {'TrialType_0','Hit'}, 0, 0.2, 1), 0.7, ...
    'a step change should increment from the current value, not rescale it');

% The same holds downward: dropping the step slows the climb from here.
assertNear(adv(p(end), {'TrialType_0','Hit'}, 0, 0.05, 1), 0.55, ...
    'a smaller step should also apply from the current value');
fprintf('PASS: step changes apply forward only\n');


% 6. Bound changes take effect immediately --------------------------------
% Lowering Max below the accumulated value pulls it down on the next
% advance rather than leaving it stranded above the ceiling.
assertNear(adv(0.8, {'TrialType_0','Hit'}, 0, 0.1, 0.5), 0.5, ...
    'lowering Max should pull the hazard down to the new ceiling');
assertNear(adv(0.1, {'TrialType_2','Hit'}, 0.4, 0.1, 1), 0.4, ...
    'raising Min should lift the hazard to the new floor');
fprintf('PASS: Min/Max edits apply on the next advance\n');


% 7. Degenerate configurations stay sane ----------------------------------
% Step 0 pins the schedule to a flat probability, reproducing the old
% behavior for anyone who wants it.
p = replay(0.3, repmat({{'TrialType_0','Hit'}},1,20), 0.3, 0, 1);
assertNear(p, repmat(0.3,1,20), 'Step = 0 should hold p flat at Min');

% Min == Max pins it regardless of step.
p = replay(0.5, repmat({{'TrialType_0','Hit'}},1,4), 0.5, 0.1, 0.5);
assertNear(p, repmat(0.5,1,4), 'Min == Max should pin the probability');
fprintf('PASS: degenerate Step/Min/Max configurations\n');


% 8. End-to-end: the selector as ep_TimerFcn_Start builds it --------------
% makeRuntime goes through the real Protocol -> compile -> ep_TimerFcn_Start
% path, which constructs the selector from Options.trialFunc and makes the
% session-start selectNext call (TrialIndex 1, no DATA field).
tmpDir = tempname; mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir,'s'));

[rt,TRIALS] = makeRuntime(tmpDir, 0.1);
sel = TRIALS.selector;
assert(isa(sel,'cl_AppetitiveStimDetect'), 'trialFunc should have produced the selector');

ttCol = TRIALS.writeParamIdx.TrialType;
assert(TRIALS.trials{TRIALS.NextTrialID, ttCol} == TT_STIM, ...
    'the first trial should be a stimulus trial');
fprintf('PASS: session-start selectNext with no DATA\n');

pcc = rt.find_parameter('P_Catch_Current',silenceParameterNotFound=true);
assert(~isempty(pcc), 'P_Catch_Current should be created on the software interface');
assertNear(pcc.Value, rt.find_parameter('P_Catch').Min, 'P_Catch_Current should start at the floor');

% It must not have become a trials-table column...
assert(~isfield(TRIALS.writeParamIdx,'P_Catch_Current'), ...
    'P_Catch_Current must not be compiled into the trials table');
% ...and UpdateEveryTrial = false is what keeps a mid-run recompile from
% giving it one that dispatch would then clobber.
assert(~pcc.UpdateEveryTrial, ...
    'P_Catch_Current must be excluded from per-trial dispatch');
% It must still be visible to the per-trial DATA record and to the GUI's
% parameter cache, both of which read all_parameters(Access='Read').
assert(isfield(rt.all_parameters(asStruct=true), 'P_Catch_Current'), ...
    'P_Catch_Current should appear in the per-trial DATA record');
fprintf('PASS: P_Catch_Current auto-created, writable, outside per-trial dispatch\n');


% 9. End-to-end: run lengths are bounded by the hazard --------------------
% Min = 0, Step = 0.1, Max = 1 reaches certainty on the tenth stimulus
% trial, so no run of stimulus trials may exceed ten.
oldRng = rng(0);
restoreRng = onCleanup(@() rng(oldRng));

TRIALS = runSession(rt, TRIALS, 400);
tt = arrayfun(@(d) d.TrialType, TRIALS.DATA);
nCatch = sum(tt == TT_CATCH);
assert(nCatch > 0, 'the hazard should have produced catch trials');

runs = stimRunLengths(tt, TT_CATCH);
assert(max(runs) <= 10, ...
    'no run of stimulus trials should exceed 10 with Step = 0.1 (got %d)', max(runs));

% The readout must equal the number of stimulus trials since the last catch
% trial, times the step -- i.e. the accumulator really did accumulate.
nSinceCatch = numel(tt) - find(tt == TT_CATCH, 1, 'last');
assertNear(pcc.Value, 0.1*nSinceCatch, 'P_Catch_Current should track the live hazard');
fprintf('PASS: %d trials, %d catch trials, longest stimulus run %d\n', ...
    numel(TRIALS.DATA), nCatch, max(runs));

% A smaller step must stretch the runs out, not leave them unchanged.
[rt2,T2] = makeRuntime(tmpDir, 0.05);
T2 = runSession(rt2, T2, 400);
runs2 = stimRunLengths(arrayfun(@(d) d.TrialType, T2.DATA), TT_CATCH);
assert(mean(runs2) > mean(runs), ...
    'halving the step should lengthen stimulus runs (%g -> %g)', mean(runs), mean(runs2));
assert(max(runs2) <= 20, 'Step = 0.05 should still bound runs at 20 (got %d)', max(runs2));
fprintf('PASS: step size scales the run length (mean %.1f -> %.1f)\n', mean(runs), mean(runs2));


% 10. End-to-end: an operator step change is not retroactive --------------
% Drive one trial at a time, raising the step partway through the way the
% GUI's autoCommit edit does. Track both readings of the schedule: the
% incremental one (carry the accumulator forward) and the retroactive one
% (step * trials since the last catch). The selector must follow the
% incremental one, and the two must actually disagree somewhere -- without
% that the test would pass for the wrong reason.
[rt3,T3] = makeRuntime(tmpDir, 0.1);
pcc3   = rt3.find_parameter('P_Catch_Current');
pStep3 = rt3.find_parameter('P_Catch');

step = 0.1;
incremental = 0;
nSinceCatch = 0;
diverged = false;

for k = 1:60
    if k == 21
        step = 0.2;
        pStep3.Value = step;   % operator raises the step mid-session
    end

    T3 = runSession(rt3, T3, 1);

    if T3.DATA(end).TrialType == TT_CATCH
        incremental = 0;
        nSinceCatch = 0;
    else
        incremental = min(incremental + step, 1);
        nSinceCatch = nSinceCatch + 1;
    end
    retroactive = min(step*nSinceCatch, 1);

    assertNear(pcc3.Value, incremental, sprintf('trial %d: hazard should accumulate', k));
    diverged = diverged || abs(incremental - retroactive) > 1e-12;
end

assert(diverged, ...
    'the incremental and retroactive schedules never diverged; the test proves nothing');
fprintf('PASS: mid-session step change increments forward, never rescales\n');


% 11. The catch-trial switch suppresses the schedule -----------------------
% The selector creates CatchTrialsEnabled when the protocol does not declare
% it, which is what gives cl_AppetitiveDetection_BehaviorGUI's checkbox something
% to bind to. Clearing it must stop catch trials outright and hold the hazard
% at its floor, so re-enabling cannot fire a catch trial on the next draw.
[rt4,T4] = makeRuntime(tmpDir, 0.1);
pEnable = rt4.find_parameter('CatchTrialsEnabled');
assert(~isempty(pEnable), 'CatchTrialsEnabled should be created on the software interface');
assert(pEnable.Value, 'catch trials should default to enabled');
assert(~pEnable.UpdateEveryTrial, ...
    'CatchTrialsEnabled must be excluded from per-trial dispatch');
assert(~isfield(T4.writeParamIdx,'CatchTrialsEnabled'), ...
    'CatchTrialsEnabled must not be compiled into the trials table');

pEnable.Value = false;
T4 = runSession(rt4, T4, 200);
tt4 = arrayfun(@(d) d.TrialType, T4.DATA);
assert(~any(tt4 == TT_CATCH), 'no catch trial should occur while the switch is off');
assertNear(rt4.find_parameter('P_Catch_Current').Value, 0, ...
    'the hazard should be held at its floor while catch trials are off');

% Re-enabling resumes the schedule from the floor: the first catch trial must
% land a few trials in, not on the very next one.
pEnable.Value = true;
T4 = runSession(rt4, T4, 200);
tt4 = arrayfun(@(d) d.TrialType, T4.DATA);
assert(any(tt4 == TT_CATCH), 'catch trials should resume once the switch is back on');
assert(find(tt4 == TT_CATCH, 1) > 201, ...
    'the hazard should climb from the floor rather than fire immediately');
fprintf('PASS: catch-trial switch suppresses and restores the schedule\n');

fprintf('smoke_test_pcatch_hazard: ALL PASS\n');
end


% ------------------------------------------------------------------------
% helpers

function RC = decodeSeq(seq)
% RC = decodeSeq(seq)
% Decode a cell array of flag-name cellstrs into the struct selectNext sees.
% Built through the real epsych.BitMask.decode so the field naming stays
% honest rather than hand-rolled.
codes = zeros(1,numel(seq),'uint32');
for i = 1:numel(seq)
    m = uint32(0);
    for j = 1:numel(seq{i})
        m = bitset(m, uint32(epsych.BitMask.(seq{i}{j})));
    end
    codes(i) = m;
end
RC = epsych.BitMask.decode(codes);
end


function assertNear(actual, expected, msg)
assert(numel(actual) == numel(expected) && all(abs(actual(:)-expected(:)) < 1e-12), ...
    '%s (expected %s, got %s)', msg, mat2str(expected,4), mat2str(actual,4));
end


function p = foldHazard(p0, seq, ttStim, ttCatch, pMin, pStep, pMax)
% p = foldHazard(p0, seq, ...)
% Advance the hazard across a whole sequence of completed trials, returning
% the probability after each one. The accumulator is carried forward, which
% is what distinguishes this from recomputing p from the history.
p = nan(1,numel(seq));
cur = p0;
for i = 1:numel(seq)
    cur = cl_AppetitiveStimDetect.advanceHazard(cur, decodeSeq(seq(i)), ...
        ttStim, ttCatch, pMin, pStep, pMax);
    p(i) = cur;
end
end


function runs = stimRunLengths(tt, ttCatch)
% runs = stimRunLengths(tt, ttCatch)
% Lengths of the non-catch runs delimited by catch trials, including the
% unterminated tail.
idx = find(tt == ttCatch);
runs = [diff([0 idx(:)']) - 1, numel(tt) - idx(end)];
end


function TRIALS = runSession(rt, TRIALS, nTrials)
% TRIALS = runSession(rt, TRIALS, nTrials)
% Drive the selector the way ep_TimerFcn_RunTime does: synthesize the
% completed trial's DATA record, bump TrialIndex, then select the next row.
sel      = TRIALS.selector;
ttCol    = TRIALS.writeParamIdx.TrialType;
depthCol = TRIALS.writeParamIdx.Depth;

for k = 1:nTrials
    row = TRIALS.NextTrialID;
    tt  = TRIALS.trials{row, ttCol};

    % Outcome mirrors what the task would score: catch trials are correct
    % rejections, stimulus trials are hits. Nothing is aborted, so the
    % hazard sees a clean history and the run bounds below are exact.
    if tt == 1
        flags = {'TrialType_1','CorrectReject'};
    else
        flags = {'TrialType_0','Hit'};
    end
    m = uint32(0);
    for j = 1:numel(flags)
        m = bitset(m, uint32(epsych.BitMask.(flags{j})));
    end

    TRIALS.DATA(TRIALS.TrialIndex) = struct('RespCode',m, 'TrialType',tt, ...
        'Depth',TRIALS.trials{row, depthCol}, 'TrialIndex',TRIALS.TrialIndex);
    TRIALS.TrialIndex = TRIALS.TrialIndex + 1;

    TRIALS.NextTrialID = sel.selectNext(TRIALS);

    % The selector writes stepped Depth values through the runtime handle,
    % so refresh the local copy the way the runtime's own struct would be.
    TRIALS.trials = rt.TRIALS(1).trials;
end
end


function [rt,TRIALS] = makeRuntime(tmpDir, pStep)
% [rt,TRIALS] = makeRuntime(tmpDir, pStep)
% Software-only session built the way a real run is: a compiled
% epsych.Protocol with trialFunc set, handed to ep_TimerFcn_Start (which
% constructs the selector and makes the session-start selectNext call).
% TrialType is the only multi-valued parameter, so compile yields exactly
% three rows -- STIM, CATCH, REMIND -- for the selector to choose among.
P = epsych.Protocol(Name='PCatchHazard', Info='catch-trial hazard smoke test');
P.setOption('trialFunc','cl_AppetitiveStimDetect');

P.addParameter('Software','TrialType',[0 1 2],Type='Integer');
P.addParameter('Software','Depth',0.5,Type='Float');
P.addParameter('Software','ReminderTrials',false,Type='Boolean');
P.addParameter('Software','Depth_StepOnHit',-0.05,Type='Float');
P.addParameter('Software','Depth_StepOnMiss',0.05,Type='Float');
P.addParameter('Software','P_Catch',pStep,Type='Float');
P.addParameter('Software','RepeatDelayOnAbort',false,Type='Boolean');
P.addParameter('Software','StimDelay',1000,Type='Float');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

setBounds(sw,'Depth',     0,   1);
setBounds(sw,'P_Catch',   0,   1);
setBounds(sw,'StimDelay', 500, 2000);

P.compile();

rt = epsych.Runtime;
rt.isTest       = true;
rt.EVENTS       = epsych.EventHub;
rt.Interfaces   = P.Interfaces;
rt.Protocol     = P;
rt.DefaultDataPath = tmpDir;
rt.TempDataDir  = tmpDir;

subject = epsych.DefaultSubject(struct('Name','HazardSubject', ...
    'Species','Mouse', 'Sex','Unknown', 'BoxID',1));

rt = ep_TimerFcn_Start(rt, struct('PROTOCOL',P,'SUBJECT',subject));
TRIALS = rt.TRIALS(1);
end


function setBounds(sw,name,mn,mx)
p = sw.find_parameter(name);
p.Min = mn;
p.Max = mx;
end
