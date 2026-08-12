function smoke_test_reminder_trial()
% smoke_test_reminder_trial()
% Exercise the Reminder button path of the appetitive detection task end to
% end against a software-only runtime: cl_AppetitiveDetection_BoxGUI's
% PostUpdateFcn brings the next trial forward, and cl_AppetitiveStimDetect
% presents it as a signal-present trial at 0 dB depth without disturbing the
% staircase, the catch hazard, or the stimulus rows.
%
% Headless-safe: no figures, no hardware.
%
%   matlab -batch "run('tmp/smoke_test_reminder_trial.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

TT_STIM   = 0;
TT_CATCH  = 1;
TT_REMIND = 2;

tmpDir = tempname; mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir,'s'));

oldRng = rng(0);
restoreRng = onCleanup(@() rng(oldRng));


% 1. The button's PostUpdateFcn only sets FORCE_TRIAL ---------------------
% The old implementation resolved '~TrialDelivery' through find_parameter,
% which never matches a parameter named TrialDelivery, so the handler threw
% before it ever reached FORCE_TRIAL. Guard against that regression by
% calling the handler exactly as hw.Parameter does.
[rt,TRIALS] = makeRuntime(tmpDir, 0);
pReminder = rt.find_parameter('ReminderTrials');

assert(~rt.TRIALS(1).FORCE_TRIAL, 'FORCE_TRIAL should start clear');
cl_AppetitiveDetection_BoxGUI.trigger_ReminderTrial(pReminder, 0, rt);
assert(~rt.TRIALS(1).FORCE_TRIAL, 'clearing the toggle must not force a trial');

cl_AppetitiveDetection_BoxGUI.trigger_ReminderTrial(pReminder, 1, rt);
assert(rt.TRIALS(1).FORCE_TRIAL, 'pressing Reminder should set FORCE_TRIAL');
rt.TRIALS(1).FORCE_TRIAL = false;
fprintf('PASS: Reminder button sets FORCE_TRIAL without erroring\n');


% 2. The reminder is a signal-present trial at 0 dB ------------------------
% Walk the staircase down first, so a reminder at 0 dB is unmistakably an
% override rather than the value the staircase happens to be sitting on.
ttCol    = TRIALS.writeParamIdx.TrialType;
depthCol = TRIALS.writeParamIdx.Depth;

[rt,TRIALS] = makeRuntime(tmpDir, 0);
TRIALS = runTrials(rt, TRIALS, repmat({'Hit'},1,4));   % -2 dB per hit

stimRow  = find(cellfun(@(v) v == TT_STIM,   TRIALS.trials(:,ttCol)), 1);
remRow   = find(cellfun(@(v) v == TT_REMIND, TRIALS.trials(:,ttCol)), 1);
walked   = TRIALS.trials{stimRow, depthCol};
assert(walked < 0, 'four hits should have walked the staircase below 0 dB (got %g)', walked);

pReminder = rt.find_parameter('ReminderTrials');
pReminder.Value = 1;
TRIALS = selectOnly(rt, TRIALS);

assert(TRIALS.NextTrialID == remRow, ...
    'the reminder should select the reminder row (got row %d, expected %d)', ...
    TRIALS.NextTrialID, remRow);
assertNear(TRIALS.trials{TRIALS.NextTrialID, depthCol}, 0, ...
    'the reminder trial should be presented at 0 dB depth');
assertNear(TRIALS.trials{stimRow, depthCol}, walked, ...
    'the reminder must not disturb the depth held on the stimulus rows');
fprintf('PASS: reminder selects the reminder row at 0 dB, staircase row untouched\n');


% 3. The staircase resumes from the pre-reminder depth ---------------------
% Score the reminder as a hit and clear the toggle, the way onNewData does.
% The staircase measures from the last completed STIM trial, so the reminder
% must leave the pending depth exactly where it was. Had the reminder been
% presented on a stimulus row instead, its 0 dB would have become lastStim
% and the next trial would have jumped to stepOnHit -- the whole session's
% threshold estimate thrown away.
stepOnHit = rt.find_parameter('Depth_StepOnHit').Value;

TRIALS = scoreTrial(TRIALS, TT_REMIND, 'Hit');
pReminder.Value = 0;
TRIALS = selectOnly(rt, TRIALS);

assertNear(TRIALS.trials{stimRow, depthCol}, walked, ...
    'the pending staircase depth should survive the reminder');
assert(abs(TRIALS.trials{stimRow, depthCol} - stepOnHit) > 1e-12, ...
    'the staircase should not have restarted from the reminder''s 0 dB');

% ...and it is still live: the next completed stimulus trial steps again.
TRIALS = runTrials(rt, TRIALS, {'Hit'});
assertNear(TRIALS.trials{stimRow, depthCol}, walked + stepOnHit, ...
    'the staircase should keep stepping after the reminder');
fprintf('PASS: staircase resumes from the last stimulus trial, not the reminder\n');


% 4. Repeated reminders are idempotent ------------------------------------
% FORCE_TRIAL can bring selectNext round twice at the same TrialIndex, so
% the override has to survive being applied twice.
pReminder.Value = 1;
TRIALS = selectOnly(rt, TRIALS);
TRIALS = selectOnly(rt, TRIALS);
assert(TRIALS.NextTrialID == remRow, 'a repeated reminder should still select the reminder row');
assertNear(TRIALS.trials{TRIALS.NextTrialID, depthCol}, 0, ...
    'a repeated reminder should still be at 0 dB');
pReminder.Value = 0;
fprintf('PASS: repeated reminder selections are idempotent\n');


% 5. The reminder does not advance the catch hazard ------------------------
[rt2,T2] = makeRuntime(tmpDir, 0.1);
pcc2 = rt2.find_parameter('P_Catch_Current');
T2 = runTrials(rt2, T2, repmat({'Hit'},1,3));
before = pcc2.Value;
assertNear(before, 0.3, 'three stimulus hits should have climbed the hazard to 0.3');

pRem2 = rt2.find_parameter('ReminderTrials');
pRem2.Value = 1;
T2 = selectOnly(rt2, T2);
T2 = scoreTrial(T2, TT_REMIND, 'Hit');
pRem2.Value = 0;
T2 = selectOnly(rt2, T2);
assertNear(pcc2.Value, before, 'a reminder trial should leave the catch hazard where it was');
assert(T2.trials{T2.NextTrialID, ttCol} ~= TT_REMIND, ...
    'the schedule should return to normal once the toggle is cleared');
fprintf('PASS: reminder trials are inert to the catch hazard\n');


% 6. A protocol with no reminder row degrades safely -----------------------
% Borrowing a stimulus row would overwrite the staircase depth, so the
% selector presents an ordinary stimulus trial and says so rather than
% corrupting the table.
[rt3,T3] = makeRuntime(tmpDir, 0, [TT_STIM TT_CATCH]);
T3 = runTrials(rt3, T3, repmat({'Hit'},1,3));
stimRow3 = find(cellfun(@(v) v == TT_STIM, T3.trials(:,ttCol)), 1);
held3 = T3.trials{stimRow3, depthCol};

rt3.find_parameter('ReminderTrials').Value = 1;
T3 = selectOnly(rt3, T3);
assert(T3.trials{T3.NextTrialID, ttCol} == TT_STIM, ...
    'without a reminder row the selector should fall back to a stimulus trial');
assertNear(T3.trials{stimRow3, depthCol}, held3, ...
    'the fallback must not overwrite the depth the staircase is holding');
fprintf('PASS: protocol without a reminder row falls back without corrupting the staircase\n');

fprintf('smoke_test_reminder_trial: ALL PASS\n');
end


% ------------------------------------------------------------------------
% helpers

function assertNear(actual, expected, varargin)
msg = sprintf(varargin{:});
assert(numel(actual) == numel(expected) && all(abs(actual(:)-expected(:)) < 1e-12), ...
    '%s (expected %s, got %s)', msg, mat2str(expected,4), mat2str(actual,4));
end


function m = bits(flags)
% m = bits(flags)
% Pack epsych.BitMask flag names into the RespCode the selector decodes.
m = uint32(0);
for j = 1:numel(flags)
    m = bitset(m, uint32(epsych.BitMask.(flags{j})));
end
end


function TRIALS = scoreTrial(TRIALS, tt, outcome)
% TRIALS = scoreTrial(TRIALS, tt, outcome)
% Append the DATA record ep_TimerFcn_RunTime would have written for the
% pending trial and advance TrialIndex, without selecting the next row.
depthCol = TRIALS.writeParamIdx.Depth;
TRIALS.DATA(TRIALS.TrialIndex) = struct( ...
    'RespCode',   bits({sprintf('TrialType_%d',tt), outcome}), ...
    'TrialType',  tt, ...
    'Depth',      TRIALS.trials{TRIALS.NextTrialID, depthCol}, ...
    'TrialIndex', TRIALS.TrialIndex);
TRIALS.TrialIndex = TRIALS.TrialIndex + 1;
end


function TRIALS = selectOnly(rt, TRIALS)
% TRIALS = selectOnly(rt, TRIALS)
% Run the selector alone, then refresh the local trials copy from the
% runtime -- the selector writes depths through the runtime handle, which is
% the only copy dispatchNextTrial reads.
TRIALS.NextTrialID = TRIALS.selector.selectNext(TRIALS);
TRIALS.trials = rt.TRIALS(1).trials;
end


function TRIALS = runTrials(rt, TRIALS, outcomes)
% TRIALS = runTrials(rt, TRIALS, outcomes)
% Drive whole trials the way ep_TimerFcn_RunTime does: score the pending
% trial with the given outcome, then select the next row.
ttCol = TRIALS.writeParamIdx.TrialType;
for k = 1:numel(outcomes)
    TRIALS = scoreTrial(TRIALS, TRIALS.trials{TRIALS.NextTrialID, ttCol}, outcomes{k});
    TRIALS = selectOnly(rt, TRIALS);
end
end


function [rt,TRIALS] = makeRuntime(tmpDir, pStep, trialTypes)
% [rt,TRIALS] = makeRuntime(tmpDir, pStep, trialTypes)
% Software-only session built the way a real run is: a compiled
% epsych.Protocol with trialFunc set, handed to ep_TimerFcn_Start (which
% constructs the selector and makes the session-start selectNext call).
% TrialType is the only multi-valued parameter, so compile yields one row
% per code. Depth is in dB re 100% modulation, matching the real protocol:
% 0 dB is full depth and the staircase walks down into negative values.
arguments
    tmpDir (1,:) char
    pStep (1,1) double
    trialTypes (1,:) double = [0 1 2]
end

P = epsych.Protocol(Name='ReminderTrial', Info='reminder-trial smoke test');
P.setOption('trialFunc','cl_AppetitiveStimDetect');

P.addParameter('Software','TrialType',trialTypes,Type='Integer');
P.addParameter('Software','Depth',-30,Type='Float');
P.addParameter('Software','ReminderTrials',false,Type='Boolean');
P.addParameter('Software','Depth_StepOnHit',-2,Type='Float');
P.addParameter('Software','Depth_StepOnMiss',6,Type='Float');
P.addParameter('Software','P_Catch',pStep,Type='Float');
P.addParameter('Software','RepeatDelayOnAbort',false,Type='Boolean');
P.addParameter('Software','StimDelay',1000,Type='Float');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

setBounds(sw,'Depth',     -40, 0);
setBounds(sw,'P_Catch',   0,   1);
setBounds(sw,'StimDelay', 500, 2000);

P.compile();

rt = epsych.Runtime;
rt.isTest       = true;
rt.HELPER       = epsych.Helper;
rt.Interfaces   = P.Interfaces;
rt.Protocol     = P;
rt.dfltDataPath = tmpDir;
rt.TempDataDir  = tmpDir;

subject = epsych.DefaultSubject(struct('Name','ReminderSubject', ...
    'Species','Mouse', 'Sex','Unknown', 'BoxID',1));

rt = ep_TimerFcn_Start(rt, struct('PROTOCOL',P,'SUBJECT',subject));
TRIALS = rt.TRIALS(1);
end


function setBounds(sw,name,mn,mx)
p = sw.find_parameter(name);
p.Min = mn;
p.Max = mx;
end
