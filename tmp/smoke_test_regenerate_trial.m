function smoke_test_regenerate_trial()
% smoke_test_regenerate_trial()
% Exercise gui.RegenerateTrial against a software-only runtime: the button
% re-dispatches the pending trial (redrawing randomized parameters and
% re-firing the triggers) without advancing the trial counter, is live only
% while a session runs, refuses a review, and records what it did in the
% session notes.
%
% Uses an invisible uifigure; no hardware.
%
%   matlab -batch "run('tmp/smoke_test_regenerate_trial.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

tmpDir = tempname; mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir,'s'));

oldRng = rng(0);
restoreRng = onCleanup(@() rng(oldRng));

fig = uifigure('Visible','off');
cleanupFig = onCleanup(@() delete(fig));

nTrialEvents = 0;
figArming = [];
cleanupFigArming = onCleanup(@() delete(figArming));


% 1. The button starts disabled and follows the run mode -------------------
% gui.BehaviorGUI is built from the PsychTimer StartFcn, BEFORE RunExpt
% broadcasts the run mode, so a button that seated itself at construction
% would seat itself Idle and stay there for the whole session.
rt = makeRuntime(tmpDir);
h  = gui.RegenerateTrial(rt, fig, RequireArming=false);

assert(strcmp(h.ButtonH.Enable,'off'), 'the button should start disabled (Idle)');

setMode(rt, hw.DeviceState.Record);
assert(strcmp(h.ButtonH.Enable,'on'), 'Record should make the button live');

setMode(rt, hw.DeviceState.Preview);
assert(strcmp(h.ButtonH.Enable,'on'), 'Preview dispatches trials too and should be live');

setMode(rt, hw.DeviceState.Stop);
assert(strcmp(h.ButtonH.Enable,'off'), 'a stopped session should disable the button');

setMode(rt, hw.DeviceState.Record);
fprintf('PASS: the button is live only while the session runs\n');


% 2. Regenerating re-dispatches without advancing the trial ----------------
% The regenerated trial is still ONE trial and still one DATA record: the
% counter must not move, or the session would count trials the subject never
% saw.
lsnTrial = listener(rt.EVENTS, 'NewTrial', @(~,~) bumpTrial());
cleanupLsn = onCleanup(@() delete(lsnTrial));

idxBefore   = rt.TRIALS(1).TrialIndex;
rowBefore   = rt.TRIALS(1).NextTrialID;
countBefore = h.Count;
nTrialEvents = 0;

assert(h.regenerate(), 'regenerate should report success on a running session');

assert(rt.TRIALS(1).TrialIndex == idxBefore, ...
    'regenerating must not advance the trial counter (%d -> %d)', ...
    idxBefore, rt.TRIALS(1).TrialIndex);
assert(rt.TRIALS(1).NextTrialID == rowBefore, ...
    'without Reselect the trial row must not change');
assert(nTrialEvents == 1, ...
    'regenerating should broadcast exactly one NewTrial (got %d)', nTrialEvents);
assert(h.Count == countBefore + 1, 'Count should record the regeneration');
fprintf('PASS: regenerate re-dispatches the pending trial, counter untouched\n');


% 3. Randomized parameters draw again -------------------------------------
% This is what the button is for: an ITI or a stimulus delay that came out
% wrong is redrawn without waiting for the next trial.
pITI = rt.find_parameter('ITIDur');
assert(pITI.isRandom, 'the test ITI should be randomized');

seen = zeros(1,25);
for k = 1:numel(seen)
    h.regenerate();
    seen(k) = pITI.Value;
end
assert(numel(unique(seen)) > 1, ...
    'a randomized parameter should redraw on regeneration (every draw was %g)', seen(1));
assert(all(seen >= pITI.Min & seen <= pITI.Max), 'redraws should stay within bounds');
fprintf('PASS: randomized parameters redraw on regeneration (%d distinct of %d)\n', ...
    numel(unique(seen)), numel(seen));


% 4. Each regeneration is recorded in the session notes --------------------
% The regenerated trial writes one ordinary DATA record, so the note is the
% only trace the data file keeps of the interference.
notes = rt.NOTES.forSubject(1);
assert(numel(notes) == h.Count, ...
    'every regeneration should leave one note (%d notes for %d regenerations)', ...
    numel(notes), h.Count);
assert(contains(notes(end).Text,'regenerated'), ...
    'the note should say what happened (got "%s")', notes(end).Text);
assert(notes(end).Subject == 1, 'the note should be tagged with the box it happened to');

nBefore = numel(rt.NOTES.Records);
h.Note = false;
h.regenerate();
assert(numel(rt.NOTES.Records) == nBefore, 'Note=false should write no note');
h.Note = true;
fprintf('PASS: regenerations are recorded in the session notes\n');


% 5. Reselect re-runs the selector ----------------------------------------
% Selecting is where a paradigm's state moves -- a staircase steps, a hazard
% climbs, a one-shot is consumed -- so the plain button must leave it alone.
% epsych.DefaultTrialSelector counts every row it hands out, so the total is
% how many times selectNext has run.
rt2 = makeRuntime(tmpDir);
h2  = gui.RegenerateTrial(rt2, fig, Reselect=true, EnableWhenIdle=true, RequireArming=false);

selBefore = sum(rt2.TRIALS(1).selector.TrialCount);
assert(h2.regenerate(), 'Reselect regeneration should succeed');
assert(sum(rt2.TRIALS(1).selector.TrialCount) == selBefore + 1, ...
    'Reselect should have run the selector exactly once more');

h3 = gui.RegenerateTrial(rt2, fig, EnableWhenIdle=true, RequireArming=false);   % Reselect defaults off
selBefore = sum(rt2.TRIALS(1).selector.TrialCount);
assert(h3.regenerate(), 'plain regeneration should succeed');
assert(sum(rt2.TRIALS(1).selector.TrialCount) == selBefore, ...
    'without Reselect the trial selector must not run again');
fprintf('PASS: Reselect controls whether the trial selector runs again\n');


% 6. A review refuses ------------------------------------------------------
% epsych.ReviewSession replays a finished session; writing parameters would
% run randomization and expressions over the very numbers being reviewed.
rtR = makeRuntime(tmpDir);
rtR.ReviewMode = true;
hR = gui.RegenerateTrial(rtR, fig, EnableWhenIdle=true, RequireArming=false);
assert(strcmp(hR.ButtonH.Enable,'off'), 'a review must leave the button dead');
setMode(rtR, hw.DeviceState.Record);
assert(strcmp(hR.ButtonH.Enable,'off'), 'not even a run mode should arm it in a review');
assert(~hR.regenerate(), 'regenerate must refuse in a review');
assert(hR.Count == 0, 'a refused regeneration should not count');
fprintf('PASS: a review refuses to regenerate\n');


% 7. Nothing to regenerate degrades quietly -------------------------------
% This runs from a button callback beside a live experiment: it logs and
% returns false rather than throwing an error dialog over the session.
hNone = gui.RegenerateTrial([], fig, EnableWhenIdle=true, RequireArming=false);
assert(~hNone.regenerate(), 'no session should return false');

rtBare = epsych.Runtime;
rtBare.EVENTS = epsych.EventHub;
hBare = gui.RegenerateTrial(rtBare, fig, EnableWhenIdle=true, RequireArming=false);
assert(~hBare.regenerate(), 'a runtime with no compiled trials should return false');

hBox9 = gui.RegenerateTrial(rt, fig, SubjectIndex=9, EnableWhenIdle=true, RequireArming=false);
assert(~hBox9.regenerate(), 'a box that does not exist should return false');
fprintf('PASS: nothing to regenerate returns false instead of throwing\n');


% 8. The Ctrl+Alt+Shift arming gate ---------------------------------------
% The button is dead until all three are held, and dies again as soon as one
% is let go. Driven through the figure's own key callbacks, so this exercises
% the hooks the component installed rather than a private method.
rtA = makeRuntime(tmpDir);
hA  = gui.RegenerateTrial(rtA, figA(), EnableWhenIdle=true);

assert(hA.RequireArming, 'arming should be required by default');
assert(~hA.Armed, 'it should start unarmed');
assert(strcmp(hA.ButtonH.Enable,'off'), 'an unarmed button must be dead');
assert(~hA.regenerate(), 'an unarmed regenerate must refuse');
assert(hA.Count == 0, 'a refused regeneration should not count');

keyPress(figA(), {'control'});
assert(~hA.Armed, 'ctrl alone must not arm');
keyPress(figA(), {'control','alt'});
assert(~hA.Armed, 'two of the three must not arm');

keyPress(figA(), {'control','alt','shift'});
assert(hA.Armed, 'all three held should arm');
assert(strcmp(hA.ButtonH.Enable,'on'), 'an armed button should be live');
assert(hA.regenerate(), 'an armed regenerate should go out');

keyRelease(figA(), {'control','alt'});      % shift let go
assert(~hA.Armed, 'releasing one of the three should disarm');
assert(strcmp(hA.ButtonH.Enable,'off'), 'a disarmed button should be dead again');
assert(~hA.regenerate(), 'regenerate must refuse once disarmed');
fprintf('PASS: Ctrl+Alt+Shift arms the button, releasing any one disarms it\n');


% 9. Arming shares the figure's keyboard with its neighbours ---------------
% A standalone component (no KeySource) joins the figure's shared
% gui.KeyBindings instead of claiming the one WindowKeyPressFcn slot for
% itself: two components that each claimed and chained the slot could chain
% each other and recurse on every keystroke.
rtB = makeRuntime(tmpDir);
figB = uifigure('Visible','off');
cleanupFigB = onCleanup(@() delete(figB));
gB = uigridlayout(figB,[2 1]);

% (a) A handler already on the figure keeps receiving events -- chained by
% the shared dispatcher, modifier presses included.
probeSeen = 0;
figB.WindowKeyPressFcn = @(~,~) bumpProbe();
hB0 = gui.RegenerateTrial(rtB, gB, EnableWhenIdle=true);
keyPress(figB, {'control','alt','shift'});
assert(hB0.Armed, 'the component should arm from the shared dispatcher');
assert(probeSeen == 1, ...
    'the handler that was already installed must still be called (got %d)', probeSeen);
delete(hB0);
assert(probeSeen == 1, 'sanity: no extra calls during teardown');
keyPress(figB, {'control','alt','shift'});
assert(probeSeen == 2, ...
    'the dispatcher outlives the button and keeps chaining the original handler');
keyRelease(figB, {});   % let go of the held set before the next subsection
fprintf('PASS: an existing key handler is chained, not clobbered\n');

% (b) A neighbour that assigns the figure's key callbacks outright AFTER
% this component is built (the pre-KeyBindings gui.Parameter_Update pattern)
% displaces the shared dispatcher. The component re-claims it through its
% KeyBindings on the first ModeChange (which RunExpt broadcasts only once
% the GUI is fully built), and the neighbour is chained, so both keep
% working. A modern neighbour just joins the same dispatcher.
figB.WindowKeyPressFcn = '';
figB.WindowKeyReleaseFcn = '';
hB = gui.RegenerateTrial(rtB, gB, EnableWhenIdle=true);   % built first...
pu = gui.Parameter_Update(rtB, gB);        % joins the same shared dispatcher
pu.watchedHandles = gui.Parameter_Control.empty;
lateSeen = 0;
figB.WindowKeyPressFcn = @(~,~) bumpLate();               % ...then clobbered

keyPress(figB, {'control','alt','shift'});
assert(~hB.Armed, ...
    'sanity: the neighbour really does take the slot, leaving this button unarmable');
assert(lateSeen == 1, 'sanity: the clobbering neighbour sees its own events');

setMode(rtB, hw.DeviceState.Record);          % the re-claim moment
keyPress(figB, {'control','alt','shift'});
assert(hB.Armed, 'arming must be restored once the GUI is fully built');
assert(lateSeen == 2, 'the clobbering neighbour must be chained, not thrown away');

% Teardown leaves the shared dispatcher (and the chained neighbour) alone.
delete(hB);
assert(~isempty(figB.WindowKeyPressFcn), ...
    'deleting the button must leave the figure''s key dispatch in place');
assert(isvalid(pu), 'the neighbour should be untouched');
keyPress(figB, {'control','alt','shift'});    % must not error
assert(lateSeen == 3, 'the chained neighbour keeps working after teardown');
fprintf('PASS: arming coexists with a slot-claiming neighbour on the same key\n');


% (c) A chained handler that THROWS must not take the arming down with it.
keyRelease(figB, {});   % let go of the held set before displacing the slot
figB.WindowKeyPressFcn   = @(~,~) error('smoke:neighbour','deliberate');
figB.WindowKeyReleaseFcn = @(~,~) error('smoke:neighbour','deliberate');
hC = gui.RegenerateTrial(rtB, gB, EnableWhenIdle=true);
setMode(rtB, hw.DeviceState.Record);          % re-claim chains the throwers

keyPress(figB, {'control','alt','shift'});
assert(hC.Armed, 'a throwing neighbour must not prevent arming');
keyRelease(figB, {'control'});
assert(~hC.Armed, 'a throwing neighbour must not prevent disarming either');
fprintf('PASS: a throwing chained handler does not break the arming gate\n');


% (d) Two standalone buttons on one figure share one dispatcher: no chain,
% no recursion, both arm. This exact arrangement (one button per box on a
% multi-box rig) used to recurse to MATLAB's recursion limit per keystroke.
figD = uifigure('Visible','off');
cleanupFigD = onCleanup(@() delete(figD));
gD = uigridlayout(figD,[2 1]);
hD1 = gui.RegenerateTrial(rtB, gD, EnableWhenIdle=true);
hD2 = gui.RegenerateTrial(rtB, gD, EnableWhenIdle=true, SubjectIndex=1);
setMode(rtB, hw.DeviceState.Record);
keyPress(figD, {'control','alt','shift'});
assert(hD1.Armed && hD2.Armed, 'both buttons should arm from one dispatcher');
keyRelease(figD, {'control'});
assert(~hD1.Armed && ~hD2.Armed, 'both buttons should disarm together');
fprintf('PASS: two standalone buttons share one dispatcher without recursion\n');


fprintf('smoke_test_regenerate_trial: ALL PASS\n');

    function f = figA()
        % One figure for the arming group, made on first use.
        if isempty(figArming) || ~isvalid(figArming)
            figArming = uifigure('Visible','off');
        end
        f = figArming;
    end

    function bumpTrial()
        nTrialEvents = nTrialEvents + 1;
    end

    function bumpProbe()
        probeSeen = probeSeen + 1;
    end

    function bumpLate()
        lateSeen = lateSeen + 1;
    end
end


% ------------------------------------------------------------------------
% helpers

function setMode(rt, mode)
% setMode(rt, mode)
% Broadcast a ModeChange the way epsych.RunExpt.PsychTimerStart does.
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(mode));
end


function keyPress(fig, mods)
% keyPress(fig, mods)
% Invoke the figure's installed WindowKeyPressFcn with the modifier set a
% real key event would carry. Going through the figure's own callback is the
% point: it tests the hook the component actually installed, including any
% chaining, rather than reaching into a private method.
feval(fig.WindowKeyPressFcn, fig, keyEvent(mods));
end


function keyRelease(fig, mods)
% keyRelease(fig, mods)
% As keyPress, for the release callback. mods is what is STILL held after
% the release, which is what MATLAB reports.
feval(fig.WindowKeyReleaseFcn, fig, keyEvent(mods));
end


function ev = keyEvent(mods)
% ev = keyEvent(mods)
% The two fields the modifier handlers read off a key event.
if isempty(mods)
    key = '';
else
    key = mods{end};
end
ev = struct('Key', key, 'Modifier', {mods});
end


function rt = makeRuntime(tmpDir)
% rt = makeRuntime(tmpDir)
% Software-only session built the way a real run is: a compiled
% epsych.Protocol handed to ep_TimerFcn_Start, which constructs the selector
% (epsych.DefaultTrialSelector, since no trialFunc is set) and makes the
% session-start selectNext call.
P = epsych.Protocol(Name='RegenerateTrial', Info='regenerate-trial smoke test');

P.addParameter('Software','TrialType',[0 1],Type='Integer');
P.addParameter('Software','ITIDur',1000,Type='Float');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

p = sw.find_parameter('ITIDur');
p.Min = 1000;
p.Max = 9000;
p.isRandom = true;

P.compile();

rt = epsych.Runtime;
rt.isTest       = true;
rt.EVENTS       = epsych.EventHub;
rt.Interfaces   = P.Interfaces;
rt.Protocol     = P;
rt.DefaultDataPath = tmpDir;
rt.TempDataDir  = tmpDir;

subject = epsych.DefaultSubject(struct('Name','RegenSubject', ...
    'Species','Mouse', 'Sex','Unknown', 'BoxID',1));

rt = ep_TimerFcn_Start(rt, struct('PROTOCOL',P,'SUBJECT',subject));
end
