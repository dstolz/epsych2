function smoke_test_review_session
% smoke_test_review_session
% End-to-end check of offline session review: run a session through the REAL
% timer functions, save it, then reopen it with epsych.ReviewSession and drive
% the scrubber.
%
% Verifies:
%   1) ep_TimerFcn_Start captures a session snapshot onto TRIALS and into the
%      crash-recovery info record
%   2) ep_SaveDataFcn writes Data + Info, and Info round-trips as a snapshot
%   3) hw.Replay rebuilds every protocol parameter, and reads report the
%      positioned trial
%   4) a review reaches the same trial count the session ended with
%   5) seek(k) leaves exactly k trials visible and every parameter reading
%      Data(k) -- backward and forward alike
%   6) a review opens with a behavior GUI, its controls disabled, and tears
%      down cleanly
%   7) the crash-recovery .mat (info + data_NNNN) reviews the same way
%   8) a legacy file with no Info still opens, degraded but usable
%
% Run headless: matlab -batch "run('c:\src\epsych2\tmp\smoke_test_review_session.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);
addpath(fullfile(here, '..', 'examples', 'detection_task'));

scratch = fullfile(tempdir, sprintf('review_session_smoke_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);
cleanupScratch = onCleanup(@() localRmdir(scratch));

fprintf('\n=== smoke_test_review_session ===\n');

N = 12;
[sessionFile, recoveryFile, RUNTIME] = localRunSession(scratch, N);

% --- 1. snapshot captured at Start ---------------------------------------
snap = RUNTIME.TRIALS(1).SessionInfo;
assert(epsych.SessionSnapshot.isSnapshot(snap), 'Start must capture a snapshot onto TRIALS');
assert(~isempty(fieldnames(snap.Protocol)), 'the snapshot must carry the serialized protocol');
assert(~isempty(snap.WriteParams), 'the snapshot must carry the trial-column map');

R = load(recoveryFile, 'info');
assert(epsych.SessionSnapshot.isSnapshot(R.info), ...
    'the crash-recovery info record must be a snapshot');
fprintf('PASS: 1 snapshot captured onto TRIALS and into the recovery file\n');

% --- 2. the saved file carries it ----------------------------------------
S = load(sessionFile);
assert(isfield(S, 'Data') && isfield(S, 'Info'), 'ep_SaveDataFcn must write Data and Info');
assert(numel(S.Data) == N, 'expected %d saved trials', N);
back = epsych.SessionSnapshot.fromInfo(S.Info);
assert(isequal(back.WriteParams, snap.WriteParams), 'the snapshot must round-trip through save/load');
fprintf('PASS: 2 saved file carries Data + a round-tripping Info snapshot\n');

% --- 3+4+5. headless review ----------------------------------------------
V = epsych.ReviewSession(sessionFile, Show = false);
cleanupReview = onCleanup(@() localDelete(V));

assert(V.NumTrials == N, 'the review must find all %d trials', N);
assert(~V.IsDegraded, 'a file with a protocol must not review degraded');

params = localAllParameters(V);
assert(~isempty(params), 'hw.Replay must rebuild the protocol parameters');
fprintf('PASS: 3 %d parameter(s) rebuilt from the saved protocol\n', numel(params));

assert(V.Position == N, 'a review must open at the last trial');
fprintf('PASS: 4 review opened at trial %d of %d\n', V.Position, V.NumTrials);

% Forward, then backward to the same place: the state must match, because
% every consumer recomputes from the whole DATA array rather than accumulating.
localAssertAt(V, 7, S.Data);
localAssertAt(V, 11, S.Data);
localAssertAt(V, 3, S.Data);   % backward
localAssertAt(V, 1, S.Data);
localAssertAt(V, N, S.Data);

V.seek(0);
assert(V.Position == 0, 'seek(0) must sit before the first trial');
V.seek(9999);
assert(V.Position == N, 'seek past the end must clamp to the last trial');
V.seek(-5);
assert(V.Position == 0, 'seek before the start must clamp to 0');
fprintf('PASS: 5 seek is exact forward and backward, and clamps at both ends\n');

clear cleanupReview
delete(V);

% --- 6. with a GUI --------------------------------------------------------
localTestWithGUI(sessionFile, N);

% --- 7. the crash-recovery layout ----------------------------------------
V3 = epsych.ReviewSession(recoveryFile, Show = false);
assert(V3.NumTrials == N, 'the recovery .mat must review all %d trials', N);
assert(~V3.IsDegraded, 'the recovery file carries a snapshot, so it must not be degraded');
V3.seek(5);
assert(numel(V3.RUNTIME.TRIALS(1).DATA) == 5, 'recovery-file seek must work like any other');
delete(V3);
fprintf('PASS: 7 crash-recovery .mat (info + data_NNNN) reviews identically\n');

% --- 8. a legacy file with no Info ---------------------------------------
legacyFile = fullfile(scratch, 'legacy_no_info.mat');
Data = S.Data;
save(legacyFile, 'Data');

V4 = epsych.ReviewSession(legacyFile, Show = false);
assert(V4.NumTrials == N, 'a legacy file must still load its trials');
assert(V4.IsDegraded, 'a file with no protocol must report itself degraded');
V4.seek(4);
assert(numel(V4.RUNTIME.TRIALS(1).DATA) == 4, 'a degraded review must still seek');
delete(V4);

% ...and comes back to life when pointed at the protocol
V5 = epsych.ReviewSession(legacyFile, Show = false, ...
    Protocol = fullfile(scratch, 'proto.eprot'));
assert(~V5.IsDegraded, 'Protocol= must restore the parameter tree for a legacy file');
assert(~isempty(localAllParameters(V5)), 'Protocol= must produce parameters');
delete(V5);
fprintf('PASS: 8 legacy file opens degraded, and recovers with Protocol=\n');

% --- 9. the transport scrubber -------------------------------------------
localTestTransport(sessionFile, N);

% --- 10. a rig-driving GUI stands down -----------------------------------
localTestStandDown(scratch);

% --- 11. the review survives being called with no output -----------------
localTestLifetime(sessionFile);

fprintf('=== smoke_test_review_session: ALL PASS ===\n');
end




function localTestLifetime(sessionFile)
% A review called the ordinary way -- epsych.ReviewSession(file), no output --
% must not be garbage-collected the instant its constructor returns, which
% would take its own windows with it. Its windows anchor it (appdata), so the
% review lives exactly as long as they do.
%
% This regressed once and was invisible from the outside: with the transport
% open, the transport figure's UserData happened to hold a chain back to the
% review, so it survived by accident. Both cases are checked.

delete(findall(groot, 'Type', 'figure'))

% (a) no output, no transport -- nothing but the GUI window to hold it
epsych.ReviewSession(sessionFile, BehaviorGUI = 'ep_GenericGUI', Transport = false);
drawnow
g = findall(groot, 'Type', 'figure', 'Tag', 'ep_GenericGUI');
assert(~isempty(g), 'a review with no output and no transport closed its own window');
assert(isa(getappdata(g(1), 'epsych_ReviewSession'), 'epsych.ReviewSession'), ...
    'the behavior GUI window must anchor the review');
delete(findall(groot, 'Type', 'figure'))

% (b) closing the transport must leave the behavior GUI up
epsych.ReviewSession(sessionFile, BehaviorGUI = 'ep_GenericGUI');
drawnow
t = findall(groot, 'Type', 'figure', 'Tag', gui.ReviewTransport.PREFERENCE_TAG);
assert(~isempty(t), 'the review should have opened a transport');
close(t(1));
drawnow

g = findall(groot, 'Type', 'figure', 'Tag', 'ep_GenericGUI');
assert(~isempty(g), 'closing the transport must not close the behavior GUI');
assert(isvalid(g(1).UserData), 'the behavior GUI object must survive its transport');

delete(findall(groot, 'Type', 'figure'))
fprintf('PASS: 11 a review with no output argument outlives its constructor\n');

end




function localTestTransport(sessionFile, N)
% The scrubber drives the review, and follows it when it is driven from code.

V = epsych.ReviewSession(sessionFile, BehaviorGUI = 'ep_GenericGUI');

try
    T = V.Transport;
    assert(isobject(T) && isvalid(T), 'a review must open a transport by default');
    assert(isgraphics(T.h_figure), 'the transport must have a window');

    % Driven from code: the scrubber must follow rather than hold a stale trial.
    V.seek(6);
    drawnow
    assert(contains(localTransportLabel(T), sprintf('Trial 6  of %d', N)), ...
        'the transport must follow a seek made from code, showed "%s"', localTransportLabel(T));

    V.jumpToStart();
    drawnow
    assert(contains(localTransportLabel(T), 'Before trial 1'), ...
        'the transport must say when the review sits before the first trial');
    fprintf('PASS: 9 transport opened and follows seeks made from code\n');

    % Closing the transport leaves the review alive, and showTransport brings
    % it back -- that is the documented behaviour, not an accident.
    delete(T);
    assert(isvalid(V), 'closing the transport must not end the review');
    V.seek(3);
    assert(V.Position == 3, 'the review must still seek with no transport');
    T2 = V.showTransport();
    assert(isobject(T2) && isvalid(T2), 'showTransport must reopen the scrubber');
    fprintf('PASS: 9b transport closes independently and reopens\n');

catch ME
    delete(V);
    rethrow(ME)
end

delete(V);
end




function s = localTransportLabel(T)
w = warning('off', 'MATLAB:structOnObject');
restoreWarning = onCleanup(@() warning(w));
s = char(struct(T).TrialLabel_.Text);
end




function localTestStandDown(scratch)
% A GUI that drives the rig must not drive it in a review: no rig timer, and
% rigReady_ false so no trial cycle starts and no parameter is written.

addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'examples', 'two_afc'));

P = create_2afc_protocol(fullfile(scratch, 'twoafc.eprot'));
P.compile();

CONFIG = struct('PROTOCOL', P, 'SUBJECT', struct('Name','StandDown','BoxID',1));

sessionFile = fullfile(scratch, 'twoafc_session.mat');

RUNTIME = epsych.Runtime;
RUNTIME.TempDataDir = scratch;
RUNTIME.DefaultDataPath = scratch;
RUNTIME.SessionDataFilename = string(sessionFile);
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces;
RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);
for k = 1:6
    RUNTIME.TRIALS(1).FORCE_TRIAL = true;
    RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
end
RUNTIME = ep_TimerFcn_Stop(RUNTIME);
ep_SaveDataFcn(RUNTIME);

timersBefore = localRigTimers();

V = epsych.ReviewSession(sessionFile, ...
    BehaviorGUI = 'TwoAFCBehaviorGUI', Transport = false);

try
    assert(V.GUI.ReviewMode, 'the GUI must report itself in review mode');

    timersAfter = localRigTimers();
    assert(numel(timersAfter) == numel(timersBefore), ...
        'a review must not start a rig timer (%d before, %d after)', ...
        numel(timersBefore), numel(timersAfter));

    % Every NewTrial event this seek fires reaches onNewTrial -> beginTrial_,
    % which is gated on rigReady_. beginTrial_ is the only writer of
    % TrialLabel, so a label still reading its build-time text proves the trial
    % cycle never started -- and therefore that no parameter was written and no
    % x_TrialComplete_1 raised.
    before = char(V.GUI.TrialLabel.Text);
    for k = 1:V.NumTrials
        V.seek(k);
    end
    drawnow

    assert(strcmp(char(V.GUI.TrialLabel.Text), before), ...
        'the trial cycle ran during a review: label went from "%s" to "%s"', ...
        before, char(V.GUI.TrialLabel.Text));

catch ME
    delete(V);
    rethrow(ME)
end

delete(V);
fprintf('PASS: 10 a rig-driving GUI stands down in review (no timer, no trial cycle)\n');
end




function t = localRigTimers()
t = timerfindall();
if isempty(t), t = []; return; end
keep = arrayfun(@(x) contains(char(x.Name), '_rig'), t);
t = t(keep);
end




function [sessionFile, recoveryFile, RUNTIME] = localRunSession(scratch, N)
% Run N trials through the real Start -> RunTime -> Stop -> save path.

P = create_detection_protocol(fullfile(scratch, 'proto.eprot'));
P.compile();

CONFIG = struct();
CONFIG.PROTOCOL = P;
CONFIG.SUBJECT = struct('Name', 'ReviewSubj', 'BoxID', 1);

sessionFile = fullfile(scratch, 'review_session.mat');

RUNTIME = epsych.Runtime;
RUNTIME.TempDataDir = scratch;
RUNTIME.DefaultDataPath = scratch;
RUNTIME.SessionDataFilename = string(sessionFile);
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces;

RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);

for k = 1:N
    RUNTIME.TRIALS(1).FORCE_TRIAL = true;
    RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
end

recoveryFile = char(RUNTIME.DataFile(1));

RUNTIME = ep_TimerFcn_Stop(RUNTIME);
ep_SaveDataFcn(RUNTIME);

end




function localAssertAt(V, k, Data)
% Seek to k and check both halves of the contract: the trials the components
% were handed, and what the parameters report.

V.seek(k);

assert(V.Position == k, 'seek(%d) left Position at %d', k, V.Position);

D = V.RUNTIME.TRIALS(1).DATA;
assert(numel(D) == k, 'seek(%d) must leave exactly %d trials visible, not %d', k, k, numel(D));
assert(isequaln(D, Data(1:k)), 'seek(%d) must hand over Data(1:%d) unaltered', k, k);

params = localAllParameters(V);
for p = params
    vn = p.validName;
    if ~isfield(Data, vn), continue; end
    expected = Data(k).(vn);
    actual = p.Value;
    if isnumeric(expected), expected = double(expected); end
    assert(isequaln(actual, expected), ...
        'at trial %d, parameter "%s" reads %s but the record says %s', ...
        k, p.Name, mat2str(actual), mat2str(expected));
end

end




function localTestWithGUI(sessionFile, N)
% Open a review with a real behavior GUI and check it is inert.

V = epsych.ReviewSession(sessionFile, ...
    BehaviorGUI = 'DetectionBehaviorGUI', Transport = false);

try
    assert(isobject(V.GUI) && isvalid(V.GUI), 'the review must hold the behavior GUI object');
    assert(isgraphics(V.GUI.h_figure), 'the behavior GUI must have opened a window');
    assert(contains(V.GUI.h_figure.Name, 'REVIEW'), ...
        'the window must say it is a review, not a live session');

    assert(V.Position == N, 'a review with a GUI must still open at the last trial');

    % Every parameter control disabled: gui.Parameter_Control does this itself
    % off the interface mode PostSet, which is why the review moves the
    % interfaces Standby -> Idle only after the window is built.
    nControls = 0;
    for c = localComponents(V.GUI)
        if ~isa(c{1}, 'gui.Parameter_Control'), continue; end
        nControls = nControls + 1;
        w = c{1}.widgets();
        for h = w(isgraphics(w))
            assert(strcmp(char(h.Enable), 'off'), ...
                'control "%s" is still enabled in a review', c{1}.Text);
        end
    end
    assert(nControls > 0, 'this paradigm should have produced parameter controls');
    fprintf('PASS: 6 GUI opened, titled as a review, %d control(s) all disabled\n', nControls);

    % A seek must reach the GUI's psych object, not just the runtime.
    V.seek(5);
    drawnow
    if ~isempty(V.GUI.Psych) && isvalid(V.GUI.Psych)
        assert(numel(V.GUI.Psych.DATA) == 5, ...
            'the psych object must see 5 trials after seek(5), not %d', numel(V.GUI.Psych.DATA));
        fprintf('PASS: 6b seek reached the GUI psychophysics object\n');
    end

catch ME
    delete(V);
    rethrow(ME)
end

delete(V);
assert(isempty(findall(groot, 'Type', 'figure', 'Tag', 'DetectionBehaviorGUI')), ...
    'deleting the review must close the behavior GUI window');
fprintf('PASS: 6c review teardown closed the GUI window\n');

end




function c = localComponents(guiObj)
% The behavior GUI's registered components. Reached by struct surgery because
% gui.BehaviorGUI keeps the registry private -- acceptable in a test, which is
% checking exactly that private bookkeeping did its job.

c = {};
try
    w = warning('off', 'MATLAB:structOnObject');
    restoreWarning = onCleanup(@() warning(w));
    s = struct(guiObj);
    c = s.Components_;
catch ME
    vprintf(2, 'smoke_test_review_session: could not read the component registry (%s)', ME.message)
end

end




function P = localAllParameters(V)
P = hw.Parameter.empty(1,0);
for iface = V.Interfaces(:).'
    P = [P, iface.all_parameters(Access='All', includeInvisible=true, includeTriggers=true)];
end
end




function localDelete(o)
try
    if ~isempty(o) && isobject(o) && isvalid(o), delete(o); end
catch
end
end




function localRmdir(d)
try
    if isfolder(d), rmdir(d, 's'); end
catch
end
end
