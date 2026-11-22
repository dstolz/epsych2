function smoke_test_eventhub_deferral
% smoke_test_eventhub_deferral
% epsych.EventHub can hold a display's drawing until the next trial has been
% dispatched (defer / beginDeferral / flushDeferred). This is the standing
% proof of the three things that makes safe: nothing is deferred unless the
% session asked, what is deferred runs in the same tick before the NewTrial
% event, and analysis is never deferred.
%
% Verifies:
%   1) a hub nobody opted in runs deferred work at once
%   2) an open boundary queues, coalesces by owner + tag, and flushes in order
%   3) work asked for while the queue is being run is run at once
%   4) a deleted owner's work is dropped; work that throws does not stop the rest
%   5) deferFor finds the hub through a hub, a runtime and an analysis object,
%      and runs at once when there is none
%   6) the real trial loop: deferred work runs after the NewTrial pulse and
%      before the NewTrial event; without the opt-in it runs inside NewData
%   7) a History table over a Staircase in the loop: drawn after the dispatch
%      when deferring, the analysis already up to date during it, and the
%      table the same at the end of the tick either way
%   8) a dispatch that fails still closes the boundary and runs what was queued
%   9) gui.BehaviorGUI turns deferral on for a GUI that asks, and never in a
%      review
%
% No hardware. Opens invisible windows.
%
%   matlab -batch "run('tmp/smoke_test_eventhub_deferral.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

fprintf('\n=== smoke_test_eventhub_deferral ===\n');

PREF_GROUP = 'epsych2_gui_History';
HIST_TAG = 'smokeDeferralHistory';
GUI_TAGS = {'smokeDeferringGUI', 'smokeBehaviorGUITest'};
cleanupPrefs = onCleanup(@() localCleanup(PREF_GROUP, HIST_TAG, GUI_TAGS));
localCleanup(PREF_GROUP, HIST_TAG, GUI_TAGS);

seen = containers.Map('KeyType', 'char', 'ValueType', 'any');
seen('log') = {};

% --- 1. a hub nobody opted in ------------------------------------------------
hub = epsych.EventHub;
owner = hub;   % any handle object will do as an owner
assert(~hub.DeferralEnabled && ~hub.Deferring, 'a new hub defers nothing');
hub.beginDeferral();
assert(~hub.Deferring, 'beginDeferral must be a no-op until the session opts in');
hub.defer(owner, 'a', @() localNote(seen, 'a'));
assert(isequal(seen('log'), {'a'}), 'work handed to a hub that is not deferring runs at once');
hub.flushDeferred();
assert(isequal(seen('log'), {'a'}), 'a flush with nothing queued does nothing');
fprintf('PASS: 1 a hub nobody opted in runs the work at once\n');

% --- 2. queue, coalesce, flush in order --------------------------------------
seen('log') = {};
hub.DeferralEnabled = true;
hub.beginDeferral();
assert(hub.Deferring, 'an opted-in hub opens a boundary');
other = epsych.EventHub;
hub.defer(owner, 'first',  @() localNote(seen, 'first-old'));
hub.defer(owner, 'second', @() localNote(seen, 'second'));
hub.defer(other, 'first',  @() localNote(seen, 'other-first'));
hub.defer(owner, 'first',  @() localNote(seen, 'first-new'));   % replaces the first request
assert(isempty(seen('log')), 'nothing runs while the boundary is open');
hub.flushDeferred();
assert(isequal(seen('log'), {'first-new', 'second', 'other-first'}), ...
    'flush order or coalescing wrong: %s', strjoin(seen('log'), ', '));
assert(~hub.Deferring, 'a flush closes the boundary');
hub.flushDeferred();
assert(numel(seen('log')) == 3, 'a second flush runs nothing again');
fprintf('PASS: 2 queued, coalesced by owner and tag, flushed in order\n');

% --- 3. work asked for during the flush --------------------------------------
seen('log') = {};
hub.beginDeferral();
hub.defer(owner, 'outer', @() localNested(hub, owner, seen));
hub.defer(owner, 'last',  @() localNote(seen, 'last'));
hub.flushDeferred();
assert(isequal(seen('log'), {'outer', 'inner', 'last'}), ...
    'work asked for during a flush should run at once: %s', strjoin(seen('log'), ', '));
fprintf('PASS: 3 work asked for while the queue runs is run at once\n');

% --- 4. deleted owners and throwing work -------------------------------------
seen('log') = {};
gone = epsych.EventHub;
hub.beginDeferral();
hub.defer(gone,  'x', @() localNote(seen, 'gone'));
hub.defer(owner, 'boom', @() error('smoke:deferral', 'deliberate test error (expected in the log)'));
hub.defer(owner, 'after', @() localNote(seen, 'after'));
delete(gone);
hub.flushDeferred();
assert(isequal(seen('log'), {'after'}), ...
    'a deleted owner is dropped and a throw does not stop the rest: %s', strjoin(seen('log'), ', '));
assert(~hub.Deferring, 'the boundary closes even when queued work throws');
fprintf('PASS: 4 deleted owner dropped; a throw is logged and the rest run\n');

% --- 5. deferFor resolution --------------------------------------------------
seen('log') = {};
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
rt.EVENTS.DeferralEnabled = true;

epsych.EventHub.deferFor([], owner, 't', @() localNote(seen, 'none'));
epsych.EventHub.deferFor(struct('EVENTS', 1), owner, 't', @() localNote(seen, 'struct'));
assert(isequal(seen('log'), {'none', 'struct'}), 'no hub: the work runs at once');

offline = psychophysics.SessionMetrics(localOfflineData(3));
epsych.EventHub.deferFor(offline, owner, 't', @() localNote(seen, 'offline'));
L = seen('log');
assert(strcmp(L{end}, 'offline'), 'an offline analysis has no hub: at once');

seen('log') = {};
rt.EVENTS.beginDeferral();
epsych.EventHub.deferFor(rt.EVENTS, owner, 'hub', @() localNote(seen, 'hub'));
epsych.EventHub.deferFor(rt, owner, 'rt', @() localNote(seen, 'rt'));
assert(isempty(seen('log')), 'a hub and a runtime lead to the session hub, which is deferring');
rt.EVENTS.flushDeferred();
assert(isequal(seen('log'), {'hub', 'rt'}), 'both were queued on the one hub');
delete(rt);
fprintf('PASS: 5 deferFor finds the hub through a hub and a runtime, else runs at once\n');

% --- the real loop -----------------------------------------------------------
scratch = fullfile(tempdir, sprintf('smoke_deferral_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);
cleanupScratch = onCleanup(@() localRmdir(scratch));

[RUNTIME, dev, W] = localSession(scratch);
cleanupRuntime = onCleanup(@() localDelete(RUNTIME));
events = RUNTIME.EVENTS;

% --- 6. ordering in the loop -------------------------------------------------
probe = epsych.EventHub;   % owner of the probe work
hData = addlistener(events, 'NewData', @(~,~) localOnData(RUNTIME, probe, seen, dev));
hTrial = addlistener(events, 'NewTrial', @(~,~) localNote(seen, 'NewTrial'));
hWrite = addlistener(W, 'Value', 'PostSet', @(~,~) localNote(seen, 'write'));

seen('log') = {};
RUNTIME = localTrial(RUNTIME);
L = seen('log');
assert(isequal(L, {'NewData', 'deferred@0', 'write', 'NewTrial'}), ...
    'without the opt-in the work runs inside NewData: %s', strjoin(L, ', '));

events.DeferralEnabled = true;
seen('log') = {};
RUNTIME = localTrial(RUNTIME);
L = seen('log');
assert(isequal(L, {'NewData', 'write', 'deferred@2', 'NewTrial'}), ...
    ['with it, the work runs after both trigger pulses (ResetTrig, NewTrial) ' ...
     'and before the NewTrial event: %s'], strjoin(L, ', '));
assert(~events.Deferring, 'the boundary is closed when the tick returns');
fprintf('PASS: 6 in the loop: after the NewTrial pulse, before the NewTrial event\n');
delete([hData hTrial hWrite]);

% --- 7. a display over an analysis, in the loop ------------------------------
S = psychophysics.Staircase(RUNTIME, W);
fig = uifigure('Visible', 'off', 'Tag', 'SmokeDeferralHistory');
cleanupFig = onCleanup(@() localDelete(fig));
H = gui.components.History(S, fig, PreferenceTag = HIST_TAG);

state = containers.Map('KeyType', 'char', 'ValueType', 'any');
hWrite = addlistener(W, 'Value', 'PostSet', @(~,~) localSnapshot(state, 'write', H, S));
hTrial = addlistener(events, 'NewTrial', @(~,~) localSnapshot(state, 'trial', H, S));

for deferring = [false true false true]
    events.DeferralEnabled = deferring;
    before = localTop(H);
    nBefore = numel(RUNTIME.TRIALS(1).DATA);
    if isempty(RUNTIME.TRIALS(1).DATA(1).TrialID), nBefore = 0; end
    RUNTIME = localTrial(RUNTIME);
    k = RUNTIME.TRIALS(1).TrialIndex - 1;      % the trial that just completed
    assert(k == nBefore + 1, 'expected trial %d to have completed (got %d)', nBefore + 1, k);

    w = state('write');
    t = state('trial');
    assert(w.NumTrials == k, ...
        'the analysis must be up to date during the dispatch (deferring=%d): %d of %d', ...
        deferring, w.NumTrials, k);
    if deferring
        assert(strcmp(w.Top, before), ...
            'deferring: the table must not have been redrawn before the dispatch (%s -> %s)', ...
            before, w.Top);
    else
        assert(strcmp(w.Top, num2str(k)), ...
            'not deferring: the table is drawn inside NewData (top row %s, trial %d)', w.Top, k);
    end
    assert(strcmp(t.Top, num2str(k)), ...
        'by the NewTrial event the table shows trial %d either way (got %s, deferring=%d)', ...
        k, t.Top, deferring);
    assert(strcmp(localTop(H), num2str(k)), 'the table shows the newest trial after the tick');
end
fprintf('PASS: 7 History draws after the dispatch when deferring; the analysis never waits\n');
delete([hWrite hTrial]);

% --- 8. a failed dispatch still closes the boundary --------------------------
events.DeferralEnabled = true;
seen('log') = {};
hData = addlistener(events, 'NewData', ...
    @(~,~) epsych.EventHub.deferFor(RUNTIME, probe, 'guard', @() localNote(seen, 'ran')));
keep = RUNTIME.TRIGGERS(1).NewTrial;
RUNTIME.TRIGGERS(1).NewTrial = [];      % the NewTrial pulse will throw
threw = false;
try
    RUNTIME = localTrial(RUNTIME);
catch
    threw = true;
end
RUNTIME.TRIGGERS(1).NewTrial = keep;
assert(threw, 'the broken trigger should have failed the dispatch');
assert(~events.Deferring, 'a failed dispatch must not leave the boundary open');
assert(isequal(seen('log'), {'ran'}), 'what was queued is still run when the dispatch fails');
ifaces = RUNTIME.Interfaces;
assert(~any(arrayfun(@(h) h.InDispatch, ifaces)), 'InDispatch is cleared on a failed dispatch too');
delete(hData);
RUNTIME = localTrial(RUNTIME);          % and the loop carries on
fprintf('PASS: 8 a failed dispatch closes the boundary and runs what was queued\n');

delete(H); delete(S);
clear cleanupFig
RUNTIME = ep_TimerFcn_Stop(RUNTIME);
clear cleanupRuntime

% --- 9. the behavior GUI opt-in ----------------------------------------------
rt = localGuiRuntime();
g = SmokeBehaviorGUI(rt);
assert(~rt.EVENTS.DeferralEnabled, 'a GUI that does not ask leaves the hub alone');
delete(g);
delete(rt);

rt = localGuiRuntime();
g = DeferringSmokeGUI(rt);
assert(rt.EVENTS.DeferralEnabled, 'a GUI whose deferDisplayWork is true turns deferral on');
delete(g);
delete(rt);

rt = localGuiRuntime();
rt.ReviewMode = true;
g = DeferringSmokeGUI(rt);
assert(~rt.EVENTS.DeferralEnabled, 'never in a review');
delete(g);
delete(rt);
fprintf('PASS: 9 gui.BehaviorGUI opts in for a GUI that asks, never in a review\n');

fprintf('smoke_test_eventhub_deferral: ALL PASS\n');
end


% -----------------------------------------------------------------------------
function [RUNTIME, dev, W] = localSession(scratch)
% A started session over a counting device: one roved writable parameter, a
% response code, the three triggers.
P = epsych.Protocol(Info = 'eventhub_deferral');
dev = CountingProbeInterface();
P.addInterface(dev);

W = dev.add_parameter('Level', [10 20 30]);
p = dev.add_parameter('RespCode', 0, Type = 'Integer', Access = 'Read');
code = epsych.BitMask.Bits2Mask(uint32([epsych.BitMask.Hit epsych.BitMask.TrialType_0]));
dev.put(p, code);
for nm = ["x_NewTrial_1" "x_ResetTrig_1" "x_TrialComplete_1"]
    q = dev.add_parameter(char(nm), 0, isTrigger = true);
    dev.put(q, 0);
end

P.compile();
assert(P.COMPILED.ntrials > 0, 'test protocol did not compile');

CONFIG = struct();
CONFIG.PROTOCOL = P;
CONFIG.SUBJECT = struct('Name', 'DeferSubj', 'BoxID', 1);

RUNTIME = epsych.Runtime;
RUNTIME.isTest = true;
RUNTIME.TempDataDir = scratch;
RUNTIME.DefaultDataPath = scratch;
RUNTIME.SessionDataFilename = string(fullfile(scratch, 'deferral_session.mat'));
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces;
set(RUNTIME.Interfaces, 'mode', hw.DeviceState.Preview);

RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);   % dispatches trial 1
end

function RUNTIME = localTrial(RUNTIME)
% One completed trial through the real loop.
RUNTIME.TRIALS(1).FORCE_TRIAL = true;
RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
end

function localOnData(RUNTIME, probe, seen, dev)
% A NewData listener that hands a piece of work to the hub. The work records
% how many trigger pulses went out between the request and its running.
localNote(seen, 'NewData');
n0 = dev.Counts.Trigger;
epsych.EventHub.deferFor(RUNTIME, probe, 'probe', ...
    @() localNote(seen, sprintf('deferred@%d', dev.Counts.Trigger - n0)));
end

function localSnapshot(state, key, H, S)
state(key) = struct('Top', localTop(H), 'NumTrials', numel(S.DATA));
end

function s = localTop(H)
% The Trial cell of the table's first row ('' when the table is empty).
s = '';
try
    D = H.TableH.Data;
    if ~isempty(D)
        s = char(string(D{1, 1}));
    end
catch
end
end

function localNote(seen, s)
L = seen('log');
L{end+1} = s;
seen('log') = L;
end

function localNested(hub, owner, seen)
localNote(seen, 'outer');
hub.defer(owner, 'inner', @() localNote(seen, 'inner'));
end

function D = localOfflineData(n)
code = epsych.BitMask.Bits2Mask(uint32([epsych.BitMask.Hit epsych.BitMask.TrialType_0]));
for k = n:-1:1
    D(k).TrialID = k;
    D(k).RespCode = code;
    D(k).computerTimestamp = datetime('2026-11-01 09:00:00') + seconds(10 * k);
end
end

function rt = localGuiRuntime()
% The software runtime tmp/SmokeBehaviorGUI.m is written against.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
sw = hw.Software;
p = sw.add_parameter('SmokePellet', 0, isTrigger = true); p.Value = 0;
p = sw.add_parameter('~SmokeToggle', false, Type = 'Boolean'); p.Value = false;
p = sw.add_parameter('SmokeFreq', 1000, Unit = 'Hz'); p.Value = 1000;
p = sw.add_parameter('SmokeLevel', 60); p.Value = 60;
p = sw.add_parameter('SmokeState', 0); p.Value = 0;
p.Access = 'Read';
rt.Interfaces = sw;
end

function localDelete(h)
try
    if ~isempty(h) && isvalid(h), delete(h); end
catch
end
end

function localRmdir(d)
try
    if isfolder(d), rmdir(d, 's'); end
catch
end
end

function localCleanup(histGroup, histTag, guiTags)
% Remove only what this test created.
try
    tag = matlab.lang.makeValidName(histTag);
    if ispref(histGroup, tag), rmpref(histGroup, tag); end
    for k = 1:numel(guiTags)
        if ispref(guiTags{k}), rmpref(guiTags{k}); end
        delete(findall(groot, 'Type', 'figure', '-and', 'Tag', guiTags{k}));
    end
    delete(findall(groot, 'Type', 'figure', '-and', 'Tag', 'SmokeDeferralHistory'));
catch
end
end
