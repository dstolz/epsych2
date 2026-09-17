function smoke_test_phaseselector_regenerate()
% smoke_test_phaseselector_regenerate()
% gui.components.PhaseSelector must regenerate the pending trial after a phase
% load that changed something, the way gui.components.RegenerateTrial does:
% one re-dispatch per box, the trial counter untouched, the regeneration in
% the session notes. And it must NOT during an idle session, after a load
% that changed nothing, or with RegenerateOnLoad=false. Also re-runs the
% button's own path through the shared redispatch static.
%
% Software-only runtime; a visible uifigure because uiprogressdlg refuses a
% hidden one.
%
%   matlab -batch "run('tmp/smoke_test_phaseselector_regenerate.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

tmpDir = tempname; mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir, 's'));

% PhaseSelector prefers its remembered directory over the constructor
% argument, so an operator's real phase directory would hijack this.
prefGroup = 'epsych2_gui_PhaseSelector';
prefKey   = 'LastPhasePath';
if ispref(prefGroup, prefKey)
    savedPhasePref = getpref(prefGroup, prefKey);
    cleanupPref = onCleanup(@() setpref(prefGroup, prefKey, savedPhasePref));
    rmpref(prefGroup, prefKey);
else
    cleanupPref = onCleanup(@() rmprefIfSet(prefGroup, prefKey));
end

rt = makeRuntime(tmpDir);
pDelay = rt.find_parameter('StimDelay');

% Two phases: one that changes StimDelay, one identical to the other so a
% second load of it changes nothing. The trial table is synced too, because
% writeParametersProtocol saves the COMMITTED trial-table value over Value.
setDelay(99);
rt.writeParametersProtocol(fullfile(tmpDir, 'delay99.eprot'), "delay 99");
setDelay(250);
rt.writeParametersProtocol(fullfile(tmpDir, 'delay250.eprot'), "delay 250");
setDelay(5);

fig = uifigure('Visible', 'on');
cleanupFig = onCleanup(@() delete(fig));
ps = gui.components.PhaseSelector(rt, tmpDir);
h  = ps.createGUI(uipanel(fig));

nTrialEvents = 0;
lsn = listener(rt.EVENTS, 'NewTrial', @(~,~) bump());
cleanupLsn = onCleanup(@() delete(lsn));


% 1. An idle session is not re-dispatched ---------------------------------
nTrialEvents = 0;
loadPhase('delay99');
assert(isequal(pDelay.Value, 99), 'setup: the load should have applied StimDelay');
assert(nTrialEvents == 0, 'an idle session must not be re-dispatched (got %d)', nTrialEvents);
fprintf('PASS: 1. no regeneration while idle\n');


% 2. During a run a changing load regenerates exactly once ------------------
setMode(rt, hw.DeviceState.Record);
idxBefore  = rt.TRIALS(1).TrialIndex;
rowBefore  = rt.TRIALS(1).NextTrialID;
nNotes     = numel(rt.NOTES.Records);
nTrialEvents = 0;

loadPhase('delay250');

assert(nTrialEvents == 1, 'a changing load should dispatch the pending trial once (got %d)', nTrialEvents);
assert(rt.TRIALS(1).TrialIndex == idxBefore, 'regenerating must not advance the trial counter');
assert(rt.TRIALS(1).NextTrialID == rowBefore, 'regenerating must not re-select the trial');
col = rt.TRIALS(1).writeParamIdx.StimDelay;
assert(isequal(rt.TRIALS(1).trials{rowBefore, col}, 250), ...
    'the dispatched row should carry the phase value');
assert(isequal(pDelay.Value, 250), 'the dispatch should have left StimDelay at the phase value');
newText = strjoin(cellstr(string({rt.NOTES.Records(nNotes+1:end).Text})), ' | ');
assert(contains(newText, 'Regenerated trial') && contains(newText, 'delay250'), ...
    'the regeneration should be in the session notes, got: %s', newText);
fprintf('PASS: 2. a changing load during a run regenerates once, noted\n');


% 3. A load that changes nothing does not regenerate ------------------------
nTrialEvents = 0;
loadPhase('delay250');
assert(nTrialEvents == 0, 'a load with no changes must not regenerate (got %d)', nTrialEvents);
fprintf('PASS: 3. an unchanged load does not regenerate\n');


% 4. Preview counts as a run; RegenerateOnLoad=false turns it off -----------
setMode(rt, hw.DeviceState.Preview);
nTrialEvents = 0;
loadPhase('delay99');
assert(nTrialEvents == 1, 'Preview should regenerate too (got %d)', nTrialEvents);

ps.RegenerateOnLoad = false;
nTrialEvents = 0;
loadPhase('delay250');
assert(nTrialEvents == 0, 'RegenerateOnLoad=false must not regenerate (got %d)', nTrialEvents);
ps.RegenerateOnLoad = true;
fprintf('PASS: 4. Preview regenerates; RegenerateOnLoad=false does not\n');


% 5. Stop ends it ----------------------------------------------------------
setMode(rt, hw.DeviceState.Stop);
nTrialEvents = 0;
loadPhase('delay99');
assert(nTrialEvents == 0, 'a stopped session must not be re-dispatched (got %d)', nTrialEvents);
fprintf('PASS: 5. no regeneration after Stop\n');


% 6. The button still regenerates through the shared static ----------------
setMode(rt, hw.DeviceState.Record);
btn = gui.components.RegenerateTrial(rt, fig, RequireArming=false);
setMode(rt, hw.DeviceState.Record);
nTrialEvents = 0;
nNotes = numel(rt.NOTES.Records);
assert(btn.regenerate(), 'the button should still regenerate');
assert(nTrialEvents == 1 && btn.Count == 1, 'the button should dispatch once and count it');
assert(startsWith(rt.NOTES.Records(end).Text, 'Operator regenerated'), ...
    'the button note should keep its wording, got: %s', rt.NOTES.Records(end).Text);
assert(numel(rt.NOTES.Records) == nNotes + 1, 'the button should add exactly one note');
fprintf('PASS: 6. RegenerateTrial.regenerate unchanged through redispatch\n');

fprintf('ALL PASS: smoke_test_phaseselector_regenerate\n');


    function bump()
        nTrialEvents = nTrialEvents + 1;
    end

    function setDelay(v)
        pDelay.Value = v;
        rt.updateTrialsFromParameters(pDelay);
    end

    function loadPhase(name)
        h.PhaseSelect.Value = name;
        evalc('ps.onPhaseSelectionChanged(h.PhaseSelect);');
        evalc('ps.loadPhaseParameters([]);');
    end
end


function setMode(rt, mode)
% Broadcast a ModeChange the way epsych.RunExpt.PsychTimerStart does.
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(mode));
end


function rmprefIfSet(group, key)
if ispref(group, key), rmpref(group, key); end
end


function rt = makeRuntime(tmpDir)
% Software-only session built the way a real run is (see
% smoke_test_regenerate_trial).
P = epsych.Protocol(Name='PhaseRegenerate', Info='phase-load regenerate smoke test');

P.addParameter('Software','TrialType',[0 1],Type='Integer');
P.addParameter('Software','StimDelay',5,Type='Float');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

p = sw.find_parameter('StimDelay');
p.Min = 0;
p.Max = 1000;

P.compile();

rt = epsych.Runtime;
rt.isTest          = true;
rt.EVENTS          = epsych.EventHub;
rt.Interfaces      = P.Interfaces;
rt.Protocol        = P;
rt.DefaultDataPath = tmpDir;
rt.TempDataDir     = tmpDir;

subject = epsych.DefaultSubject(struct('Name','PhaseRegenSubject', ...
    'Species','Mouse', 'Sex','Unknown', 'BoxID',1));

rt = ep_TimerFcn_Start(rt, struct('PROTOCOL',P,'SUBJECT',subject));
end
