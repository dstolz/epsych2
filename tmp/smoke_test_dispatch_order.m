function smoke_test_dispatch_order
% smoke_test_dispatch_order
% Verifies dependency-ordered per-trial dispatch (hw.Parameter.orderByDependencies
% + epsych.Runtime.dispatchNextTrial): expression parameters such as
% RespWinDelay evaluate against the *current* trial's referenced values even
% when declared before the parameters they reference and the referenced
% StimDelay is randomized on every dispatch write.
%
% Run headless: matlab -batch "addpath('c:\src\epsych2'); epsych_startup('c:\src\epsych2'); run('c:\src\epsych2\tmp\smoke_test_dispatch_order.m')"

NTRIALS = 20;

% 1. orderByDependencies permutation -------------------------------------
% Expression parameters declared FIRST so the declared order is the
% worst case: without reordering they would read stale values.
sw = hw.Software;

pRWDelay = addp(sw,'RespWinDelay',0,Unit='ms');
pRWDelay.Expression = "StimDelay + StimDur - RespWinPreStim";

pRWDur = addp(sw,'RespWinDur',0,Unit='ms');
pRWDur.Expression = "RespWinPreStim + RespWinPostStim";

pStimDelay = addp(sw,'StimDelay',500,Unit='ms');
pStimDelay.Min = 200;
pStimDelay.Max = 2000;
pStimDelay.isRandom = true;

pStimDur = addp(sw,'StimDur',1000,Unit='ms');
pPre     = addp(sw,'RespWinPreStim',300,Unit='ms');
pPost    = addp(sw,'RespWinPostStim',500,Unit='ms');

% CORE triggers required by Runtime dispatch
addp(sw,'x_NewTrial_1',0,isTrigger=true);
addp(sw,'x_ResetTrig_1',0,isTrigger=true);
addp(sw,'x_TrialComplete_1',0,isTrigger=true);

params = [pRWDelay, pRWDur, pStimDelay, pStimDur, pPre, pPost];

scope = hw.Parameter.empty(1,0);
for m = 1:numel(sw.Module)
    scope = [scope, sw.Module(m).Parameters];
end

order = hw.Parameter.orderByDependencies(params, scope);
assert(isequal(sort(order), 1:numel(params)), 'order must be a permutation');

pos = @(p) find(params(order) == p, 1);
assert(pos(pStimDelay) < pos(pRWDelay), 'StimDelay must dispatch before RespWinDelay');
assert(pos(pStimDur)   < pos(pRWDelay), 'StimDur must dispatch before RespWinDelay');
assert(pos(pPre)       < pos(pRWDelay), 'RespWinPreStim must dispatch before RespWinDelay');
assert(pos(pPre)       < pos(pRWDur),   'RespWinPreStim must dispatch before RespWinDur');
assert(pos(pPost)      < pos(pRWDur),   'RespWinPostStim must dispatch before RespWinDur');
assert(pos(pStimDelay) < pos(pStimDur) && pos(pStimDur) < pos(pPre) && pos(pPre) < pos(pPost), ...
    'plain parameters must keep their declared relative order');
fprintf('PASS: orderByDependencies permutation\n');

% 2. Reference cycle falls back to declared order ------------------------
pCycA = addp(sw,'CycA',1);
pCycA.Expression = "CycB + 1";
pCycB = addp(sw,'CycB',1);
pCycB.Expression = "CycA + 1";
cycOrder = hw.Parameter.orderByDependencies([params, pCycA, pCycB], scope);
assert(isequal(sort(cycOrder), 1:numel(params)+2), 'cycle must still yield a valid permutation');
pCycA.Expression = "";
pCycB.Expression = "";
fprintf('PASS: reference cycle fallback\n');

% 3. Live Runtime dispatch: expressions see this trial''s values ----------
rt = epsych.Runtime;
rt.isTest = true;
rt.HELPER = epsych.Helper;
rt.Interfaces = sw;

T = struct;
T.Subject.BoxID = 1;
T.BoxID       = 1;
T.parameters  = params;
T.trials      = {0, 0, 500, 1000, 300, 500}; % one row; columns align with T.parameters
T.NextTrialID = 1;
T.TrialIndex  = 1;

stimDelays = nan(1, NTRIALS);
rt.TRIALS = T; % set.TRIALS dispatches trial 1
checkTrial(1);

for trialIdx = 2:NTRIALS
    rt.dispatchNextTrial(1);
    checkTrial(trialIdx);
end

assert(numel(unique(stimDelays)) > 1, ...
    'StimDelay should randomize across trials (isRandom with Min~=Max)');
fprintf('PASS: %d live dispatches, RespWinDelay/RespWinDur always current-trial\n', NTRIALS);

% 4. Phase JSON round trip must not erase live Expressions ---------------
% Reproduces the field regression: phase snapshots saved before the
% protocol defined its expressions store Expression = "", and loading one
% wiped the live expression, so dispatch passed the compiled trial value
% through unchanged (e.g. RespWinDelay stuck at its compile-time value).
phaseFile = fullfile(tempdir, 'smoke_test_dispatch_order_phase.json');
rt.writeParametersJSON(phaseFile);

txt = fileread(phaseFile);
assert(contains(txt, 'StimDelay + StimDur - RespWinPreStim'), ...
    'snapshot should carry the live expression');
txt = strrep(txt, 'StimDelay + StimDur - RespWinPreStim', '');
txt = strrep(txt, 'RespWinPreStim + RespWinPostStim', '');
fid = fopen(phaseFile, 'w'); fwrite(fid, txt); fclose(fid);

rt.readParametersJSON(phaseFile);
assert(pRWDelay.Expression == "StimDelay + StimDur - RespWinPreStim", ...
    'empty Expression in a phase file must not erase the live expression');
assert(pRWDur.Expression == "RespWinPreStim + RespWinPostStim", ...
    'empty Expression in a phase file must not erase the live expression');

rt.dispatchNextTrial(1);
checkTrial(NTRIALS);
fprintf('PASS: stale phase snapshot (blank Expression) leaves expressions intact\n');

% 5. A non-empty expression in a phase file applies deliberately ---------
rt.writeParametersJSON(phaseFile);
txt = fileread(phaseFile);
txt = strrep(txt, 'RespWinPreStim + RespWinPostStim', 'RespWinPreStim + RespWinPostStim + 7');
fid = fopen(phaseFile, 'w'); fwrite(fid, txt); fclose(fid);

rt.readParametersJSON(phaseFile);
assert(pRWDur.Expression == "RespWinPreStim + RespWinPostStim + 7", ...
    'non-empty Expression in a phase file should be applied');
rt.dispatchNextTrial(1);
assert(pRWDur.Value == pPre.Value + pPost.Value + 7, ...
    'overridden expression should drive the dispatched value');

pRWDur.Expression = "RespWinPreStim + RespWinPostStim";
delete(phaseFile);
fprintf('PASS: non-empty phase expression override applies\n');

% 6. analyzeExpressions reflects the runtime order -----------------------
candidates = fullfile(EPsychInfo.root, 'tmp', ...
    {'TEST_NEW_PROTOCOL2.eprot', 'TEST_NEW_PROTOCOL.eprot'});
protFile = candidates(cellfun(@isfile, candidates));
if ~isempty(protFile)
    protFile = protFile{1};
    prot = epsych.Protocol.load(protFile);
    A = prot.analyzeExpressions;
    for i = 1:numel(A)
        if ~contains(A(i).fullName, 'RespWin')
            continue
        end
        assert(~any([A(i).refs.dispatchedAfter]), ...
            '%s still references a later-dispatched parameter', A(i).fullName);
    end
    fprintf('PASS: analyzeExpressions shows no dispatchedAfter refs for RespWin parameters\n');
else
    fprintf('SKIP: %s not found\n', protFile);
end

fprintf('smoke_test_dispatch_order: ALL PASS\n');


    function checkTrial(trialIdx)
        stimDelays(trialIdx) = pStimDelay.Value;
        assert(pRWDelay.Value == pStimDelay.Value + pStimDur.Value - pPre.Value, ...
            'trial %d: RespWinDelay %g must equal current StimDelay %g + StimDur %g - RespWinPreStim %g', ...
            trialIdx, pRWDelay.Value, pStimDelay.Value, pStimDur.Value, pPre.Value);
        assert(pRWDur.Value == pPre.Value + pPost.Value, ...
            'trial %d: RespWinDur %g must equal RespWinPreStim %g + RespWinPostStim %g', ...
            trialIdx, pRWDur.Value, pPre.Value, pPost.Value);
    end
end


function p = addp(sw,name,value,varargin)
% add_parameter stores design-time Values; a live session assigns Value
% during trial dispatch, so set it here too.
p = sw.add_parameter(name,value,varargin{:});
p.Value = value;
end
