function smoke_test_nexttrial_firsttrial()
% smoke_test_nexttrial_firsttrial()
% Trial 1 is dispatched by ep_TimerFcn_Start (through
% epsych.Runtime.set.TRIALS) BEFORE RunExpt fevals FUNCS.BehaviorGUI, so a
% gui.components.NextTrial built by that GUI attaches its listener one trial too late.
% This checks the constructor seeds itself from RUNTIME.TRIALS instead of
% showing an empty table until trial 2, that a source with no trials yet
% is still harmless, and that a pop-out opens populated.
% Headless-safe: every figure is closed and every preference this test
% writes is restored on exit.
%
%   matlab -batch "run('tmp/smoke_test_nexttrial_firsttrial.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % NextTrialFakeRuntime lives beside this test

PREF_GROUP = 'epsych2_gui_NextTrial';
PREF_TAG   = 'smoke_test_nexttrial_firsttrial';
POP_TAG    = matlab.lang.makeValidName([PREF_TAG '_NextTrial_PopOut']);
saved = [];
if ispref(PREF_GROUP, PREF_TAG), saved = getpref(PREF_GROUP, PREF_TAG); end
cleanupObj = onCleanup(@() cleanupAll(PREF_GROUP, PREF_TAG, POP_TAG, saved));

fig = uifigure('Visible','off','Tag',PREF_TAG,'Position',[100 100 380 300]);

% 1. The first trial is on screen at construction -------------------------
rt = makeRuntime(2);   % first trial already selected: row 2
NT = gui.components.NextTrial(rt, fig, PreferenceTag=PREF_TAG);

D = NT.TableH.Data;
assert(size(D,1) == 2, 'both declared fields should show before any event (got %d rows)', size(D,1));
assert(isequal(D(:,1), {'Frequency (Hz)';'Level (dB)'}), ...
    'labels should come from the parameter names and units');
assert(isequal(D(:,2), {'2000';'70'}), ...
    'values should be the pending trial (row NextTrialID), not row 1');
assert(isequal(NT.AvailableFields, ["Freq_Hz","Level_dB"]), ...
    'the declared field set should be known before the first event');
fprintf('PASS: the session''s first trial is displayed at construction\n');

% 2. A real NewTrial event still updates it -------------------------------
rt.TRIALS.NextTrialID = 1;
rt.EVENTS.notify('NewTrial', epsych.TrialsData(rt.TRIALS));
assert(isequal(NT.TableH.Data(:,2), {'1000';'60'}), ...
    'the listener should still refresh the table on a NewTrial event');
fprintf('PASS: NewTrial events still drive the display\n');

% 3. A pop-out opens populated too ----------------------------------------
PO = NT.popOut();
assert(NT.hasPopOut, 'popOut should have opened a second display');
assert(isequal(PO.TableH.Data(:,2), {'1000';'60'}), ...
    'the pop-out should open showing the pending trial');
NT.closePopOut();
fprintf('PASS: the pop-out opens populated\n');
delete(NT);

% 4. No trials compiled yet is harmless -----------------------------------
rt2 = NextTrialFakeRuntime();          % TRIALS still struct([])
NT2 = gui.components.NextTrial(rt2, fig, PreferenceTag=PREF_TAG);
assert(isempty(NT2.TableH.Data), 'with no compiled trials the table should stay blank');
rt2.TRIALS = makeTrials(1);
rt2.EVENTS.notify('NewTrial', epsych.TrialsData(rt2.TRIALS));
assert(isequal(NT2.TableH.Data(:,2), {'1000';'60'}), ...
    'the first event should populate a display built before the run');
delete(NT2);

hub = epsych.EventHub();               % a bare event hub has no TRIALS at all
NT3 = gui.components.NextTrial(hub, fig, PreferenceTag=PREF_TAG);
assert(isempty(NT3.TableH.Data), 'an EventHub source should construct without error');
delete(NT3);
fprintf('PASS: a source with no trials yet is harmless\n');

close(fig);
fprintf('\nALL PASS: gui.components.NextTrial shows the first trial\n');
end


function rt = makeRuntime(nextTrialID)
rt = NextTrialFakeRuntime();
rt.TRIALS = makeTrials(nextTrialID);
end


function T = makeTrials(nextTrialID)
T = struct();
T.parameters    = struct('Name',{'Frequency','Level'},'Unit',{'Hz','dB'});
T.writeparams   = {'Freq_Hz','Level_dB'};
T.writeParamIdx = struct('Freq_Hz',1,'Level_dB',2);
T.trials        = {1000, 60; 2000, 70};
T.NextTrialID   = nextTrialID;
T.TrialIndex    = 1;
T.Subject       = struct('Name','SMOKE','BoxID',1);
T.BoxID         = 1;
end


function cleanupAll(prefGroup, prefTag, popTag, saved)
if isempty(saved)
    if ispref(prefGroup, prefTag), rmpref(prefGroup, prefTag); end
else
    setpref(prefGroup, prefTag, saved);
end
if ispref(prefGroup, popTag), rmpref(prefGroup, popTag); end
if ispref(popTag), rmpref(popTag); end
delete(findall(groot,'Type','figure','-and','Tag',prefTag));
delete(findall(groot,'Type','figure','-and','Tag',popTag));
end
