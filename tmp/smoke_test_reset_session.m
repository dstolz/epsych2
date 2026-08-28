function smoke_test_reset_session
% smoke_test_reset_session
% Standing proof for hw.Interface.resetSession (issue #19): the per-run reset
% hook and the shared hw.Interface.resetParametersToDesign_ pass.
%
% Covers, over hw.Software on a real epsych.Runtime:
%   - what is reset: writable parameters the trial dispatcher will NOT write
%     on trial 1 (UpdateEveryTrial and SetOnce both false, or invisible)
%   - what is left alone: dispatched parameters, read-only, triggers, and
%     parameters with no design-time Values
%   - Expression parameters are reset AFTER what they read
%   - isRandom resets to a draw inside [Min Max]
%   - one parameter that throws is logged and does not stop the rest
%   - the base-class hook is a no-op on an offline hw.TDT_RPcox
%   - ExptDispatch calls the hook before prepareRecording and the mode write
%
% The TDT reload itself needs an RZ6 on the bench; see issue #19 for the repro.
%
% Run headless:
%   matlab -batch "run('c:\src\epsych2\tmp\smoke_test_reset_session.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('epsych_startup'))
    addpath(repoRoot);
end
if isempty(which('hw.Software'))
    epsych_startup(repoRoot);
end

% 1. Two software interfaces on a runtime --------------------------------
sw1 = hw.Software;
sw2 = hw.Software;

% Declared BEFORE the parameter it reads, so a reset in declared order would
% evaluate it against the stale value.
pExpr = addp(sw1, 'DerivedNum', 0, UpdateEveryTrial=false);
pExpr.Expression = "SetupNum + 1";

pDispatched = addp(sw1, 'Level', 10);                       % UpdateEveryTrial default: dispatcher's
pSetOnce    = addp(sw1, 'Coefs', 5, UpdateEveryTrial=false, SetOnce=true);
pToggle     = addp(sw1, 'DeliverTrials', false, Type='Boolean', UpdateEveryTrial=false);
pPersist    = addp(sw1, 'CatchEnabled', true, Type='Boolean', UpdateEveryTrial=false, PersistWithPhase=true);
pHidden     = addp(sw1, 'HiddenGain', 3, Visible=false);    % UpdateEveryTrial true but never compiled
pNum        = addp(sw1, 'SetupNum', 100, UpdateEveryTrial=false);
pRand       = addp(sw1, 'Jitter', 3, UpdateEveryTrial=false);
pRand.Min = 1; pRand.Max = 5; pRand.isRandom = true;
pTrig       = addp(sw1, 'x_Fire', 0, isTrigger=true, UpdateEveryTrial=false);
pNoValues   = addp(sw1, 'Orphan', 4, UpdateEveryTrial=false);
pNoValues.Values = {};
pRead       = addp(sw1, 'Counter', 7);
pRead.Access = 'Read';

pOther = addp(sw2, 'OtherKnob', 20, UpdateEveryTrial=false);

R = epsych.Runtime;
R.EVENTS = epsych.EventHub;
R.Interfaces = [sw1, sw2];
assert(sw1.Runtime == R && sw2.Runtime == R, 'Runtime.Interfaces must register itself on each interface');

% Mutate everything a session could have mutated.
pDispatched.Value = 11;
pSetOnce.Value    = 8;
pToggle.Value     = true;
pPersist.Value    = false;
pHidden.Value     = 9;
pNum.Value        = 200;    % pExpr now 201
pRand.Value       = 4;
pTrig.Value       = 1;
pNoValues.Value   = 5;
pOther.Value      = 25;
% An Expression evaluates when ITS value is assigned, not when its reference
% changes; assigning anything here yields SetupNum + 1 against the mutated value.
pExpr.Value       = 0;
assert(isequal(pExpr.Value, 201), 'expression must evaluate against the mutated reference');

sw1.resetSession(R);
sw2.resetSession(R);

assert(isequal(pToggle.Value, false),  'operator toggle must return to its design value');
assert(isequal(pPersist.Value, true),  'PersistWithPhase toggle must return to its design value');
assert(isequal(pHidden.Value, 3),      'invisible parameter must be reset: the dispatcher never sees it');
assert(isequal(pNum.Value, 100),       'non-dispatched numeric setup value must be reset');
assert(isequal(pOther.Value, 20),      'second interface must be reset too');
assert(isequal(pExpr.Value, 101),      'expression must be re-evaluated AFTER its reference was reset (got %g)', pExpr.Value);
assert(pRand.Value >= 1 && pRand.Value <= 5, 'isRandom parameter must reset to a draw inside [Min Max]');
assert(isequal(pDispatched.Value, 11), 'dispatched parameter is the trial table''s to write, not the reset''s');
assert(isequal(pSetOnce.Value, 8),     'SetOnce parameter is written on trial 1 by the dispatcher; leave it');
assert(isequal(pTrig.Value, 1),        'trigger must be left alone');
assert(isequal(pNoValues.Value, 5),    'parameter with no Values has nothing to return to');
assert(isequal(pRead.Value, 7),        'read-only parameter must be untouched');
fprintf('PASS: resetParametersToDesign_ selection, ordering, and randomization\n');

% 2. One failing parameter does not stop the rest -----------------------
sw3 = hw.Software;
pBad  = addp(sw3, 'Bad', 1, UpdateEveryTrial=false);
pBad.PreUpdateFcn = @(varargin) error('smoke:boom', 'deliberate failure');
pGood = addp(sw3, 'Good', 1, UpdateEveryTrial=false);
pBad.PreUpdateFcnEnabled = false;
pBad.Value = 2;
pBad.PreUpdateFcnEnabled = true;
pGood.Value = 2;
sw3.resetSession([]);                   % no runtime: same-interface scope
assert(isequal(pGood.Value, 1), 'a parameter after a failing one must still be reset');
assert(isequal(pBad.Value, 2),  'the failing parameter keeps its value');
fprintf('PASS: a throwing parameter is logged, not fatal\n');

% 3. Base hook is a no-op on an offline TDT interface ---------------------
tdt = hw.TDT_RPcox(Connect=false);
assert(~tdt.IsConnected, 'offline TDT_RPcox must report disconnected');
tdt.resetSession([]);                   % must not throw: no HW to reload
fprintf('PASS: offline hw.TDT_RPcox.resetSession is inert\n');

% 4. ExptDispatch order: reset, then prepareRecording, then mode ----------
src = fileread(fullfile(repoRoot, 'obj', '+epsych', '@RunExpt', 'ExptDispatch.m'));
iReset   = strfind(src, 'p.resetSession(self.RUNTIME)');
iPrepare = strfind(src, 'p.prepareRecording(self.RUNTIME)');
iMode    = strfind(src, "set(self.RUNTIME.Interfaces, 'mode'");
iStart   = strfind(src, 'start(self.RUNTIME.TIMER)');
assert(isscalar(iReset) && isscalar(iPrepare) && isscalar(iMode) && isscalar(iStart), ...
    'ExptDispatch landmarks must each appear exactly once');
assert(iReset < iPrepare && iPrepare < iMode && iMode < iStart, ...
    'ExptDispatch must reset before prepareRecording, the mode write, and the timer start');
fprintf('PASS: ExptDispatch calls resetSession before prepareRecording, mode, and timer\n');

fprintf('\nALL PASS: smoke_test_reset_session\n');
end

function p = addp(sw, name, value, varargin)
% add_parameter stores design-time Values; a live session assigns Value
% during trial dispatch, so set it here too.
p = sw.add_parameter(name, value, varargin{:});
p.Value = value;
end
