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


% 9. Arming survives a neighbour claiming the key callbacks ----------------
% gui.Parameter_Update takes the figure's WindowKeyPressFcn outright, and in
% a typical build method it is created AFTER this button -- so the hooks from
% the constructor are already gone. The component re-installs on the first
% ModeChange (which RunExpt broadcasts only once the GUI is fully built) and
% chains, so both features work off the same key.
rtB = makeRuntime(tmpDir);
figB = uifigure('Visible','off');
cleanupFigB = onCleanup(@() delete(figB));
gB = uigridlayout(figB,[2 1]);

% (a) A handler already on the figure keeps receiving events.
probeSeen = 0;
figB.WindowKeyPressFcn = @(~,~) bumpProbe();
hB0 = gui.RegenerateTrial(rtB, gB, EnableWhenIdle=true);
keyPress(figB, {'control','alt','shift'});
assert(hB0.Armed, 'the component should arm from its own hook');
assert(probeSeen == 1, ...
    'the handler that was already installed must still be called (got %d)', probeSeen);
delete(hB0);
assert(probeSeen == 1, 'sanity: no extra calls during teardown');
keyPress(figB, {'control','alt','shift'});
assert(probeSeen == 2, 'teardown should hand the slot back to the original handler');
fprintf('PASS: an existing key handler is chained, not clobbered\n');

% (b) The real neighbour, built AFTER this component the way a build method
% orders them, so the constructor's hooks are gone by the time it is done.
figB.WindowKeyPressFcn = '';
figB.WindowKeyReleaseFcn = '';
hB = gui.RegenerateTrial(rtB, gB, EnableWhenIdle=true);   % built first...
pu = gui.Parameter_Update(rtB, gB);                       % ...and clobbered here
% gui.BehaviorGUI.wireUpdateButtons_ does this after build; without it the
% neighbour's own key handler throws on the first key event.
pu.watchedHandles = gui.Parameter_Control.empty;

keyPress(figB, {'control','alt','shift'});
assert(~hB.Armed, ...
    'sanity: the neighbour really does take the slot, leaving this button unarmable');

setMode(rtB, hw.DeviceState.Record);          % the re-install moment
keyPress(figB, {'control','alt','shift'});
assert(hB.Armed, 'arming must be restored once the GUI is fully built');

% Teardown hands the slot back to the neighbour rather than nulling it.
delete(hB);
assert(~isempty(figB.WindowKeyPressFcn), ...
    'deleting the button must leave the neighbour''s key handler in place');
assert(isvalid(pu), 'the neighbour should be untouched');
keyPress(figB, {'control','alt','shift'});    % must not error
fprintf('PASS: arming coexists with gui.Parameter_Update on the same key\n');


% (c) A chained handler that THROWS must not take the arming down with it.
% This is not hypothetical: gui.Parameter_Update's own key handler throws
% whenever its watchedHandles have not been wired yet, which is every key
% event between its construction and the end of build.
figB.WindowKeyPressFcn   = @(~,~) error('smoke:neighbour','deliberate');
figB.WindowKeyReleaseFcn = @(~,~) error('smoke:neighbour','deliberate');
hC = gui.RegenerateTrial(rtB, gB, EnableWhenIdle=true);

keyPress(figB, {'control','alt','shift'});
assert(hC.Armed, 'a throwing neighbour must not prevent arming');
keyRelease(figB, {'control'});
assert(~hC.Armed, 'a throwing neighbour must not prevent disarming either');
fprintf('PASS: a throwing chained handler does not break the arming gate\n');


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
