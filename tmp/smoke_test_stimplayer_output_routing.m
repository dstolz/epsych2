function report = smoke_test_stimplayer_output_routing()
% report = smoke_test_stimplayer_output_routing()
% Smoke test for StimPlayer preview-output routing and calibration status.
%
% Verifies:
%   1) New GUI elements exist (Output dropdown, calibration status label)
%      and the default state is speakers / "No calibration".
%   2) Selecting hardware output without a host is refused with the
%      documented error id and leaves the property on "Speakers".
%   3) play_via_hardware_ without a host raises the same error.
%   4) A bank item carrying embedded calibration data flips the status
%      label to the amber "speakers" wording.
%   5) set_control_visibility accepts the new Output flag and collapses
%      the row.
%   6) The new tooltip keys resolve to non-empty text.

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

sp = [];
cleanupObj = [];

% Step 1: construction + default state
stepName = 'defaultState';
try
    sp = stimgen.StimPlayer();
    cleanupObj = onCleanup(@() localDelete_(sp)); %#ok<NASGU> % sp is a handle: valid capture
    h = struct('OutputDD', [], 'OutputLabel', [], 'CalibrationStatusLabel', []);
    props = fieldnames(h);
    for i = 1:numel(props)
        assert(isfield(handles_(sp), props{i}), ...
            'SmokeTest:MissingHandle', 'Missing GUI handle: %s', props{i});
    end
    hs = handles_(sp);
    assert(sp.PlaybackOutput == "Speakers", 'SmokeTest:BadDefault', ...
        'PlaybackOutput default should be Speakers.');
    assert(hs.OutputDD.Value == "Speakers", 'SmokeTest:BadDropdown', ...
        'OutputDD should show Speakers.');
    assert(strcmp(hs.CalibrationStatusLabel.Text, 'No calibration'), ...
        'SmokeTest:BadCalLabel', 'Expected "No calibration", got "%s".', ...
        hs.CalibrationStatusLabel.Text);
    report.steps.(stepName) = struct('passed', true, 'detail', 'Defaults correct.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: hardware output refused without a host
stepName = 'hardwareRefusedWithoutHost';
try
    threw = false;
    try
        sp.PlaybackOutput = "Hardware";
    catch innerME
        threw = true;
        assert(strcmp(innerME.identifier, 'stimgen:StimPlayer:NoHardwareHost'), ...
            'SmokeTest:WrongError', 'Unexpected error id: %s', innerME.identifier);
    end
    assert(threw, 'SmokeTest:NoError', 'Hardware output without host should error.');
    assert(sp.PlaybackOutput == "Speakers", 'SmokeTest:StateChanged', ...
        'PlaybackOutput should remain Speakers after refusal.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Refused with correct id, state unchanged.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: play_via_hardware_ without a host
stepName = 'playViaHardwareRefused';
try
    t = stimgen.Tone('Fs', sp.Fs);
    t.update_signal;
    threw = false;
    try
        sp.play_via_hardware_(t);
    catch innerME
        threw = true;
        assert(strcmp(innerME.identifier, 'stimgen:StimPlayer:NoHardwareHost'), ...
            'SmokeTest:WrongError', 'Unexpected error id: %s', innerME.identifier);
    end
    assert(threw, 'SmokeTest:NoError', 'play_via_hardware_ without host should error.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Refused with correct id.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 4: embedded calibration data drives the status label
stepName = 'embeddedCalibrationStatus';
try
    sp.open_stim(stimgen.Tone(), Name="SmokeTone");
    calObj = stimgen.StimCalibration.loadobj(struct('CalibrationData', struct('note', 'smoke')));
    sp.StimPlayObjs(1).StimObj.Calibration = calObj;
    sp.update_calibration_status_;
    hs = handles_(sp);
    txt = hs.CalibrationStatusLabel.Text;
    assert(contains(txt, 'Cal:') && contains(txt, 'speakers'), ...
        'SmokeTest:BadCalLabel', 'Expected amber speakers wording, got "%s".', txt);
    report.steps.(stepName) = struct('passed', true, 'detail', sprintf('Label: "%s"', txt));
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 5: Output control visibility flag
stepName = 'outputVisibilityFlag';
try
    sp.set_control_visibility(Output=false);
    hs = handles_(sp);
    assert(strcmp(char(hs.OutputDD.Visible), 'off'), 'SmokeTest:StillVisible', ...
        'OutputDD should be hidden.');
    sp.set_control_visibility(Output=true);
    hs = handles_(sp);
    assert(strcmp(char(hs.OutputDD.Visible), 'on'), 'SmokeTest:StillHidden', ...
        'OutputDD should be visible again.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Output row collapses and restores.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 6: tooltip keys
stepName = 'tooltipKeys';
try
    keys = {'OutputDD', 'CalibrationStatusLabel'};
    for i = 1:numel(keys)
        txt = stimgen.util.tooltip('StimPlayer', keys{i});
        assert(strlength(string(txt)) > 0, 'SmokeTest:MissingTooltip', ...
            'Tooltip key %s resolved empty.', keys{i});
    end
    report.steps.(stepName) = struct('passed', true, 'detail', 'Both tooltip keys resolve.');
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
fprintf('smoke_test_stimplayer_output_routing: %s\n', ternary_(report.allPassed, 'ALL PASSED', 'FAILURES'));

end

function localDelete_(sp)
if ~isempty(sp) && isvalid(sp)
    delete(sp);
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
