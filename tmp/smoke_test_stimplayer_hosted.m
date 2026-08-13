function report = smoke_test_stimplayer_hosted()
% report = smoke_test_stimplayer_hosted()
% Smoke test for the RunExpt Utilities-menu StimPlayer launch path.
%
% RunExpt.LaunchUtility seeds StimPlayer with a bare stimbridge.RuntimeHost
% (no protocol, nothing connected), the same pattern epsych.calibrate uses
% for the calibration GUI. Verifies that a bare host is enough to unlock
% the host-gated surfaces while hardware itself stays unavailable until a
% protocol is loaded and connected:
%
%   1) stimgen.StimPlayer(stimbridge.RuntimeHost) constructs cleanly.
%   2) PlaybackOutput = "Hardware" is accepted (no NoHardwareHost error)
%      and the value sticks.
%   3) HardwareAvailable stays false: no connection, no buffer params.
%   4) The protocol status label shows the no-protocol wording, not a
%      hardware state.
%   5) A hostless player still refuses hardware output with the documented
%      error id (the guard is intact, not bypassed).

report = struct();
report.steps = struct();

sp = [];
spNoHost = [];
cleanupObj = onCleanup(@() localDelete_({sp, spNoHost}));

% Step 1: hosted construction
stepName = 'hostedConstruction';
try
    sp = stimgen.StimPlayer(stimbridge.RuntimeHost);
    cleanupObj = onCleanup(@() localDelete_({sp, spNoHost}));
    assert(isvalid(sp), 'SmokeTest:InvalidPlayer', 'StimPlayer handle is invalid.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Constructed with bare RuntimeHost.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: hardware output accepted with a bare (unconnected) host
stepName = 'hardwareOutputAccepted';
try
    sp.PlaybackOutput = "Hardware";
    assert(sp.PlaybackOutput == "Hardware", 'SmokeTest:DidNotStick', ...
        'PlaybackOutput should be Hardware after assignment.');
    sp.PlaybackOutput = "Speakers";
    report.steps.(stepName) = struct('passed', true, 'detail', 'Hardware route selectable with host attached.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: hardware Run stays unavailable until connect
stepName = 'hardwareStillUnavailable';
try
    assert(~sp.HardwareAvailable, 'SmokeTest:PhantomHardware', ...
        'HardwareAvailable must be false with nothing connected.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'No phantom hardware before connect.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 4: status label reports missing protocol, not a hardware state
stepName = 'protocolStatusLabel';
try
    hs = handles_(sp);
    assert(isfield(hs, 'ProtocolStatusLabel') && isvalid(hs.ProtocolStatusLabel), ...
        'SmokeTest:MissingHandle', 'Missing GUI handle: ProtocolStatusLabel.');
    txt = string(hs.ProtocolStatusLabel.Text);
    assert(contains(txt, 'protocol', 'IgnoreCase', true), ...
        'SmokeTest:BadStatus', 'Expected no-protocol wording, got "%s".', txt);
    report.steps.(stepName) = struct('passed', true, 'detail', sprintf('Label: "%s"', txt));
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 5: hostless guard is intact
stepName = 'hostlessGuardIntact';
try
    spNoHost = stimgen.StimPlayer();
    cleanupObj = onCleanup(@() localDelete_({sp, spNoHost}));
    threw = false;
    try
        spNoHost.PlaybackOutput = "Hardware";
    catch innerME
        threw = true;
        assert(strcmp(innerME.identifier, 'stimgen:StimPlayer:NoHardwareHost'), ...
            'SmokeTest:WrongError', 'Unexpected error id: %s', innerME.identifier);
    end
    assert(threw, 'SmokeTest:NoError', 'Hardware output without host should still error.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Hostless refusal unchanged.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

clear cleanupObj

stepNames = fieldnames(report.steps);
stepPassed = false(size(stepNames));
for i = 1:numel(stepNames)
    stepPassed(i) = report.steps.(stepNames{i}).passed;
    fprintf('%-28s %s\n', stepNames{i}, ternary_(stepPassed(i), 'PASS', 'FAIL'));
    if ~stepPassed(i)
        fprintf('    %s\n', report.steps.(stepNames{i}).detail);
    end
end
report.allPassed = all(stepPassed);
fprintf('smoke_test_stimplayer_hosted: %s\n', ternary_(report.allPassed, 'ALL PASSED', 'FAILURES'));

end

function localDelete_(players)
for i = 1:numel(players)
    sp = players{i};
    if ~isempty(sp) && isvalid(sp)
        delete(sp);
    end
end
end

function out = ternary_(tf, a, b)
if tf, out = a; else, out = b; end
end

function hs = handles_(sp)
% Read StimPlayer's private handles struct for assertions (test-only).
ws = warning('off', 'MATLAB:structOnObject');
restoreWarn = onCleanup(@() warning(ws));
s  = struct(sp);
hs = s.handles;
end
