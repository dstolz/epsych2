function report = smoke_test_stimplayer_hw_preview()
% report = smoke_test_stimplayer_hw_preview()
% Rig-only end-to-end test of StimPlayer hardware preview.
%
% Reproduces the failing workflow of 13-Aug-2026: StimPlayer seeded with a
% bare stimbridge.RuntimeHost, protocol StimPlayer_TDT_RPcox.eprot loaded
% via the player's own protocol path, then a preview played through the
% Calibrated HW route. The StimGenCircuit exposes the playback contract
% (BufferData_0/1, BufferSize_0/1, x_Trigger_0/1) but not the calibration
% adapter tags, so this passes only if play_via_hardware_ prefers the
% playback-tag route. Plays a brief 1 kHz tone through the rig output.
%
% Requires the TDT hardware; run on the rig, not a development machine.

report = struct();
report.steps = struct();

pfn = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    'examples', 'stimgen', 'StimPlayer_TDT_RPcox.eprot');

host = stimbridge.RuntimeHost;
sp = stimgen.StimPlayer(host);
cleanupObj = onCleanup(@() localDelete_(sp));

% Step 1: load protocol through the player's own path and connect
stepName = 'loadAndConnect';
try
    assert(isfile(pfn), 'SmokeTest:MissingProtocol', 'Missing protocol: %s', pfn);
    sp.load_protocol_(pfn);
    assert(host.hasProtocol(), 'SmokeTest:NoProtocol', 'Host did not take the protocol.');
    sp.ensure_host_connected_;
    assert(host.connectionState() ~= "None", 'SmokeTest:NotConnected', ...
        'Host did not connect (state: %s).', host.connectionState());
    report.steps.(stepName) = struct('passed', true, 'detail', ...
        sprintf('Connected, state: %s', host.connectionState()));
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: playback tags resolve from the circuit
stepName = 'playbackTagsResolve';
try
    sp.resolve_params_;
    assert(sp.HardwareAvailable, 'SmokeTest:NoPlaybackTags', ...
        'Playback tags (BufferData_0/1 etc.) did not resolve from the circuit.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'All six playback tags resolved.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: hardware preview plays without the calibration adapter
stepName = 'hardwarePreviewPlays';
try
    t = stimgen.Tone;
    hwFs = double(host.sampleRate());
    if isfinite(hwFs) && hwFs > 0
        t.Fs = hwFs;
    end
    t.ApplyCalibration = false;   % plain unit-peak tone, no LUT lookup
    t.update_signal;
    sp.play_via_hardware_(t);
    report.steps.(stepName) = struct('passed', true, 'detail', ...
        sprintf('Played %.0f ms tone at %.2f Hz via playback tags.', ...
        1000 * numel(t.Signal) / t.Fs, t.Fs));
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
fprintf('smoke_test_stimplayer_hw_preview: %s\n', ternary_(report.allPassed, 'ALL PASSED', 'FAILURES'));

end

function localDelete_(sp)
if ~isempty(sp) && isvalid(sp)
    delete(sp);   % disconnect_interfaces_ returns the hardware to Idle
end
end

function out = ternary_(tf, a, b)
if tf, out = a; else, out = b; end
end
