function smoke_test_stimdelay_blocksequence()
% smoke_test_stimdelay_blocksequence()
% Exercise the block-randomized stimulus delay of the appetitive detection
% task end to end: the list StimDelayList describes, the epsych.BlockSequence
% cl_AppetitiveStimDetect drives from it, the repeat-on-abort hold, the
% mid-session edit, the operator's on/off switch, and the interaction with
% stimulus-delay training mode (which must take the parameter over).
%
% The legacy path -- a protocol with no StimDelayList, where StimDelay is
% left to isRandom -- is covered too, since that is what every protocol
% written before the list existed still uses.
%
% Headless-safe: no figures, no hardware.
%
%   matlab -batch "run('tmp/smoke_test_stimdelay_blocksequence.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

tmpDir = tempname; mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir,'s')); %#ok<NASGU>

oldRng = rng(0);
restoreRng = onCleanup(@() rng(oldRng)); %#ok<NASGU>


% 1. The list the two parameters describe -----------------------------------
% StimDelayList's Min and Max are the ends; StimDelayStep is the spacing. The
% step cannot live on StimDelayList.Value: hw.Parameter clamps Value into
% [Min Max], so a 250 ms step in a 1000-4000 ms list would silently become
% 1000. This is that clamp, demonstrated, so the reason the split exists does
% not have to be taken on trust.
pClamped = fakeList(1000,4000);
pClamped.Value = 250;
assertNear(pClamped.Value, 1000, ...
    'hw.Parameter clamps Value into [Min Max] -- the step needs its own parameter');

assertNear(cl_AppetitiveStimDetect.stimDelayValues(fakeList(1000,4000), fakeStep(250)), ...
    1000:250:4000, 'Min : step : Max should be the list');
assert(numel(cl_AppetitiveStimDetect.stimDelayValues(fakeList(1000,4000), fakeStep(250))) == 13, ...
    '1000:250:4000 should be 13 values');

% Colon semantics: a span that is not a whole number of steps stops short of
% Max rather than adding an unevenly spaced final value.
assertNear(cl_AppetitiveStimDetect.stimDelayValues(fakeList(1000,4000), fakeStep(400)), ...
    1000:400:4000, 'a partial final step should be dropped, not shortened');

% Degenerate lists are a fixed delay, not an error -- they are what an
% operator narrowing the list passes through on the way down.
assertNear(cl_AppetitiveStimDetect.stimDelayValues(fakeList(1500,1500), fakeStep(250)), 1500, ...
    'Min == Max is a single fixed delay');
assertNear(cl_AppetitiveStimDetect.stimDelayValues(fakeList(1000,4000), fakeStep(0)), 1000, ...
    'a zero step is a single fixed delay');
assert(isempty(cl_AppetitiveStimDetect.stimDelayValues(fakeList(4000,1000), fakeStep(250))), ...
    'a reversed range describes no list');
assert(isempty(cl_AppetitiveStimDetect.stimDelayValues([])), ...
    'no parameter means no list');

% With no step parameter the list falls back to its own value, which is what
% a protocol that predates StimDelayStep has.
pFallback = fakeList(1000,4000);
pFallback.Value = 1000;
assertNear(cl_AppetitiveStimDetect.stimDelayValues(pFallback), 1000:1000:4000, ...
    'without a step parameter the list should fall back to its own value');

% Value is empty until the dispatcher first writes it, and selectNext runs
% before the first dispatch -- so the compiled level has to stand in.
pUnset = fakeStep(250);
pUnset.Value = [];
assertNear(cl_AppetitiveStimDetect.stimDelayValues(fakeList(1000,4000), pUnset), 1000:250:4000, ...
    'an unwritten step should fall back to its compiled level');

assertNear(cl_AppetitiveStimDetect.stimDelayJitter(fakeJitter(10)), 10, 'jitter reads Value');
assertNear(cl_AppetitiveStimDetect.stimDelayJitter(fakeJitter(-10)), 10, 'jitter is symmetric');
assertNear(cl_AppetitiveStimDetect.stimDelayJitter([]), 0, 'no jitter parameter means no jitter');
fprintf('PASS: StimDelayList ends + StimDelayStep spacing describe the list\n');


% 2. Every list value appears once per block --------------------------------
% This is the whole reason for the change: randi([Min Max]) is memoryless and
% unbalanced over any finite session, and 40 trials is a short session.
LIST = 1000:1000:4000;   % four values, so a block is four trials
[rt,TRIALS] = makeRuntime(tmpDir, min(LIST), max(LIST), 1000, 0);
delayCol = TRIALS.writeParamIdx.StimDelay;

% isRandom would redraw randi([Min Max]) inside set.Value on dispatch and
% throw the balanced value away, so the selector holds it false -- including
% against a phase load that turns it back on mid-session.
pDelay = rt.find_parameter('StimDelay');
pDelay.isRandom = true;

[TRIALS,delays] = runTrials(rt, TRIALS, repmat({'Hit'},1,40), delayCol);
assert(~pDelay.isRandom, ...
    'the selector must hold isRandom false: randi would overwrite the drawn value');

% delays(k) is sequence index k: the session-start selectNext consumes no
% index at all -- ep_TimerFcn_Start has not installed the trials table yet,
% so trial 1 keeps its compiled delay -- and every selection after it
% advances by one.
seq = delays;
assert(all(ismember(seq, LIST)), 'every delivered delay should come from the list');
for b = 1:floor(numel(seq)/numel(LIST))
    blk = seq((b-1)*numel(LIST) + (1:numel(LIST)));
    assert(isequal(sort(blk), LIST), ...
        'block %d should hold each list value exactly once (got %s)', b, mat2str(blk));
end
assert(numel(unique(seq(1:numel(LIST)))) == numel(LIST), 'the first block should not repeat a value');
fprintf('PASS: each block delivers every list value exactly once\n');


% 3. Jitter, and the bounds it is clamped to --------------------------------
[rt,TRIALS] = makeRuntime(tmpDir, 1000, 4000, 1000, 25);
delayCol = TRIALS.writeParamIdx.StimDelay;
[~,delays] = runTrials(rt, TRIALS, repmat({'Hit'},1,24), delayCol);

seq = delays;
off = seq - interp1(LIST, LIST, seq, 'nearest', 'extrap');   % distance from the nearest list value
assert(all(abs(off) <= 25 + 1e-9), 'jitter should stay within +/-25 ms (max %g)', max(abs(off)));
assert(any(off ~= 0), 'jitter of 25 ms should actually move some values');
assertNear(seq, round(seq), 'JitterQuantum should keep delays on whole milliseconds');
fprintf('PASS: jitter is applied, symmetric, and quantized to whole ms\n');


% 4. Repeat-on-abort holds the delay, three aborts release it ---------------
% Under the block sequence a repeat is a held index, so the repeated delay is
% identical down to the jitter -- there is no value to stash and no
% randomization to suspend.
[rt,TRIALS] = makeRuntime(tmpDir, 1000, 4000, 1000, 25);
delayCol = TRIALS.writeParamIdx.StimDelay;
rt.find_parameter('RepeatDelayOnAbort').Value = true;

TRIALS = runTrials(rt, TRIALS, {'Hit'}, delayCol);          % get past trial 1
held = rt.TRIALS(1).trials{TRIALS.NextTrialID, delayCol};

[TRIALS,d] = runTrials(rt, TRIALS, {'Abort'}, delayCol);
assertNear(d(end), held, 'an abort with RepeatDelayOnAbort should repeat the same delay');
[TRIALS,d] = runTrials(rt, TRIALS, {'Abort'}, delayCol);
assertNear(d(end), held, 'a second abort should still hold the same delay');

% The third consecutive abort is the paradigm's give-up point: the delay
% moves on rather than pinning the subject to one value forever. Eight
% advancing trials must span at least one whole block, so a released index
% delivers all four list values and a stuck one delivers a single value --
% a deterministic test that does not depend on the seed.
TRIALS = runTrials(rt, TRIALS, {'Abort'}, delayCol);
[~,d] = runTrials(rt, TRIALS, repmat({'Hit'},1,8), delayCol);
assert(numel(unique(d)) >= 4, ...
    'the index should advance again after the third abort (got %d distinct delays)', ...
    numel(unique(d)));
fprintf('PASS: repeat-on-abort holds the sequence index, three aborts release it\n');


% 5. The operator's switch --------------------------------------------------
% StimDelayBlockEnabled is created by the selector, marked PersistWithPhase
% so a phase carries whether the subject trains on a varying delay, and
% switching it off leaves StimDelay to the plain Stimulus Delay field.
[rt,TRIALS] = makeRuntime(tmpDir, 1000, 4000, 1000, 0);
delayCol = TRIALS.writeParamIdx.StimDelay;
pBlock = rt.find_parameter('StimDelayBlockEnabled');
assert(isscalar(pBlock), 'the selector should create StimDelayBlockEnabled');
assert(pBlock.Value, 'a list of more than one value should default the switch on');
assert(pBlock.PersistWithPhase, 'the switch is a stage setting, so a phase must carry it');
assert(~pBlock.UpdateEveryTrial, 'the dispatcher must not overwrite an operator switch');

TRIALS = runTrials(rt, TRIALS, {'Hit'}, delayCol);
pBlock.Value = false;
fixed = 1234;
rt.TRIALS(1).trials(:,delayCol) = {fixed};
TRIALS.trials = rt.TRIALS(1).trials;
[~,d] = runTrials(rt, TRIALS, repmat({'Hit'},1,4), delayCol);
assertNear(d, repmat(fixed,size(d)), ...
    'with the switch off the sequence must not touch the delay');
fprintf('PASS: StimDelayBlockEnabled gates the sequence and is phase-persistent\n');


% 6. A single-value list defaults the switch off ----------------------------
[rt,~] = makeRuntime(tmpDir, 1500, 1500, 250, 0);
assert(~rt.find_parameter('StimDelayBlockEnabled').Value, ...
    'a one-value list is a fixed delay; the switch should default off');
fprintf('PASS: a single-value list defaults the switch off\n');


% 6b. A step finer than the list's Min --------------------------------------
% The case the whole StimDelayStep split exists for: 1000:250:4000 could not
% be expressed at all while the step lived on StimDelayList.Value.
[rt,TRIALS] = makeRuntime(tmpDir, 1000, 4000, 250, 0);
delayCol = TRIALS.writeParamIdx.StimDelay;
assertNear(rt.find_parameter('StimDelayStep').Value, 250, ...
    'a 250 ms step must survive on a list whose Min is 1000');
[~,d] = runTrials(rt, TRIALS, repmat({'Hit'},1,26), delayCol);
assert(all(ismember(d, 1000:250:4000)), 'delays should come from the 13-value list');
assert(numel(unique(d)) == 13, ...
    'two whole blocks should deliver all 13 values (got %d)', numel(unique(d)));
fprintf('PASS: a step finer than the list Min survives and drives 13 values\n');


% 7. Training mode takes the parameter over ---------------------------------
% gui.StaircaseTraining steps StimDelay itself and writes it into the trials
% table. Both driving it would overwrite each other every trial, so the
% sequence stands down -- without clearing the operator's checkbox, so
% switching training off resumes where the sequence stood.
[rt,TRIALS] = makeRuntime(tmpDir, 1000, 4000, 1000, 0);
delayCol = TRIALS.writeParamIdx.StimDelay;
sw = rt.Interfaces(1);
pTrain = sw.add_parameter('StimDelayTrainingEnabled', false, Type='Boolean');
pTrain.UpdateEveryTrial = false;
pTrain.PersistWithPhase = true;
pTrain.Value = false;

TRIALS = runTrials(rt, TRIALS, {'Hit'}, delayCol);
pTrain.Value = true;
trained = 777;
rt.TRIALS(1).trials(:,delayCol) = {trained};
TRIALS.trials = rt.TRIALS(1).trials;
[TRIALS,d] = runTrials(rt, TRIALS, repmat({'Hit'},1,3), delayCol);
assertNear(d, repmat(trained,size(d)), ...
    'the sequence must stand down while training mode owns StimDelay');
assert(rt.find_parameter('StimDelayBlockEnabled').Value, ...
    'training must not clear the operator''s randomization checkbox');

pTrain.Value = false;
[~,d] = runTrials(rt, TRIALS, {'Hit'}, delayCol);
assert(d(end) ~= trained, 'switching training off should resume the sequence');
fprintf('PASS: training mode takes StimDelay over and hands it back\n');


% 8. A mid-session list edit ------------------------------------------------
% epsych.BlockSequence freezes what has already been delivered and
% regenerates only from the next whole block, so an operator retuning the
% list does not rewrite the subject's history.
[rt,TRIALS] = makeRuntime(tmpDir, 1000, 4000, 1000, 0);
delayCol = TRIALS.writeParamIdx.StimDelay;
[TRIALS,before] = runTrials(rt, TRIALS, repmat({'Hit'},1,6), delayCol);

pList = rt.find_parameter('StimDelayList');
pList.Min = 2000;
pList.Max = 5000;
[~,after] = runTrials(rt, TRIALS, repmat({'Hit'},1,12), delayCol);
assert(all(ismember(after(end-3:end), 2000:1000:5000)), ...
    'after the edit the delays should come from the new list (got %s)', mat2str(after(end-3:end)));
assert(all(ismember(before, 1000:1000:4000)), ...
    'the delays already delivered must not be rewritten');
fprintf('PASS: a mid-session list edit takes effect without rewriting history\n');


% 9. A protocol with no StimDelayList is untouched --------------------------
% Every protocol written before the list existed still relies on isRandom and
% the abort/CORRECTVAL machinery, so the selector must leave both alone.
[rt,TRIALS] = makeRuntime(tmpDir, [], [], [], []);
assert(isempty(rt.find_parameter('StimDelayList', silenceParameterNotFound=true)), ...
    'this fixture should have no list');
assert(isempty(rt.find_parameter('StimDelayBlockEnabled', silenceParameterNotFound=true)), ...
    'no list means no block-randomization switch');

pDelay = rt.find_parameter('StimDelay');
pDelay.isRandom = true;
delayCol = TRIALS.writeParamIdx.StimDelay;
TRIALS = runTrials(rt, TRIALS, repmat({'Hit'},1,4), delayCol);
assert(pDelay.isRandom, 'the selector must not clear isRandom for a protocol with no list');
fprintf('PASS: a protocol without StimDelayList keeps the original isRandom path\n');

fprintf('smoke_test_stimdelay_blocksequence: ALL PASS\n');
end


% ------------------------------------------------------------------------
% helpers

function assertNear(actual, expected, varargin)
msg = sprintf(varargin{:});
assert(numel(actual) == numel(expected) && all(abs(actual(:)-expected(:)) < 1e-9), ...
    '%s (expected %s, got %s)', msg, mat2str(expected,6), mat2str(actual,6));
end


function p = fakeList(mn, mx)
% p = fakeList(mn, mx)
% A bare StimDelayList, whose Min and Max are the ends of the delay list.
sw = hw.Software;
p = sw.add_parameter('StimDelayList', mn, Type='Float');
p.Min = mn;
p.Max = mx;
end


function p = fakeStep(value)
% p = fakeStep(value)
% A bare StimDelayStep. Min 0 / Max Inf, because these ARE bounds on the
% value -- unlike StimDelayList's, which are the ends of the list.
sw = hw.Software;
p = sw.add_parameter('StimDelayStep', value, Type='Float');
p.Min = 0;
p.Max = Inf;
p.Value = value;
end


function m = bits(flags)
m = uint32(0);
for j = 1:numel(flags)
    m = bitset(m, uint32(epsych.BitMask.(flags{j})));
end
end


function [TRIALS,delays] = runTrials(rt, TRIALS, outcomes, delayCol)
% [TRIALS,delays] = runTrials(rt, TRIALS, outcomes, delayCol)
% Drive whole trials the way ep_TimerFcn_RunTime does -- score the pending
% trial, then select the next row -- and collect the delay each selection
% left on the row it chose. The trials table is re-read from the runtime
% handle after every selection: that is the only copy the dispatcher sees.
ttCol    = TRIALS.writeParamIdx.TrialType;
depthCol = TRIALS.writeParamIdx.Depth;
delays   = zeros(1, numel(outcomes));

for k = 1:numel(outcomes)
    tt = TRIALS.trials{TRIALS.NextTrialID, ttCol};
    data = struct( ...
        'RespCode',   bits({sprintf('TrialType_%d',tt), outcomes{k}}), ...
        'TrialType',  tt, ...
        'Depth',      TRIALS.trials{TRIALS.NextTrialID, depthCol}, ...
        'StimDelay',  TRIALS.trials{TRIALS.NextTrialID, delayCol}, ...
        'TrialIndex', TRIALS.TrialIndex);
    TRIALS.DATA(TRIALS.TrialIndex) = data;
    TRIALS.selector.onComplete(TRIALS.NextTrialID, data);
    TRIALS.TrialIndex = TRIALS.TrialIndex + 1;

    TRIALS.NextTrialID = TRIALS.selector.selectNext(TRIALS);
    TRIALS.trials = rt.TRIALS(1).trials;
    delays(k) = TRIALS.trials{TRIALS.NextTrialID, delayCol};
end
end


function [rt,TRIALS] = makeRuntime(tmpDir, listMin, listMax, listStep, jitter)
% [rt,TRIALS] = makeRuntime(tmpDir, listMin, listMax, listStep, jitter)
% Software-only session built the way a real run is: a compiled
% epsych.Protocol with trialFunc set, handed to ep_TimerFcn_Start (which
% constructs the selector and makes the session-start selectNext call).
% Pass [] for listMin to leave StimDelayList out entirely, which is the
% pre-existing protocol shape.
P = epsych.Protocol(Name='StimDelayBlock', Info='block-randomized delay smoke test');
P.setOption('trialFunc','cl_AppetitiveStimDetect');

P.addParameter('Software','TrialType',[0 1 2],Type='Integer');
P.addParameter('Software','Depth',-30,Type='Float');
P.addParameter('Software','ReminderTrials',false,Type='Boolean');
P.addParameter('Software','Depth_StepOnHit',-2,Type='Float');
P.addParameter('Software','Depth_StepOnMiss',6,Type='Float');
P.addParameter('Software','P_Catch',0,Type='Float');
P.addParameter('Software','RepeatDelayOnAbort',false,Type='Boolean');
P.addParameter('Software','StimDelay',1000,Type='Float');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

setBounds(sw,'Depth',     -40, 0);
setBounds(sw,'P_Catch',   0,   1);
% Wide enough that the list is never clipped, so a clamp cannot be mistaken
% for the sequence delivering the wrong value.
setBounds(sw,'StimDelay', 0, 10000);

if ~isempty(listMin)
    P.addParameter('Software','StimDelayList',listMin,Type='Float');
    P.addParameter('Software','StimDelayStep',listStep,Type='Float');
    P.addParameter('Software','StimDelayJitter',jitter,Type='Float');
    % StimDelayList's bounds are the ends of the list, not limits on its
    % value; StimDelayStep's really are limits on the step.
    setBounds(sw,'StimDelayList',   listMin, listMax);
    setBounds(sw,'StimDelayStep',   0, Inf);
    setBounds(sw,'StimDelayJitter', 0, 1000);
end

P.compile();

rt = epsych.Runtime;
rt.isTest          = true;
rt.EVENTS          = epsych.EventHub;
rt.Interfaces      = P.Interfaces;
rt.Protocol        = P;
rt.DefaultDataPath = tmpDir;
rt.TempDataDir     = tmpDir;

subject = epsych.DefaultSubject(struct('Name','DelaySubject', ...
    'Species','Mouse', 'Sex','Unknown', 'BoxID',1));

rt = ep_TimerFcn_Start(rt, struct('PROTOCOL',P,'SUBJECT',subject));
TRIALS = rt.TRIALS(1);
end


function setBounds(sw,name,mn,mx)
p = sw.find_parameter(name);
p.Min = mn;
p.Max = mx;
end


function p = fakeJitter(value)
% p = fakeJitter(value)
% A bare StimDelayJitter, left unbounded so the sign-handling in
% stimDelayJitter is exercised rather than clamped away.
sw = hw.Software;
p = sw.add_parameter('StimDelayJitter', value, Type='Float');
p.Value = value;
end
