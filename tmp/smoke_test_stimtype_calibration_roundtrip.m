function smoke_test_stimtype_calibration_roundtrip()
% smoke_test_stimtype_calibration_roundtrip()
% Headless verification that a StimType protocol parameter carries its
% associated calibration through the full protocol lifecycle:
%   1. StimType with a loaded StimCalibration assigned as a parameter level.
%   2. Protocol save (.eprot) / load round-trip preserves the calibration.
%   3. update_signal on the restored StimType applies the calibration
%      (signal scaled to the LUT voltage rather than unit amplitude).
%
% Run with: matlab -batch "run('tmp/smoke_test_stimtype_calibration_roundtrip.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
epsych_startup();

fprintf('--- StimType calibration round-trip smoke test ---\n');

% Build a minimal .esgc with a tone LUT: 1 kHz -> 2 V for the target SPL.
targetVoltage = 2;
calData = struct();
calData.tone = struct('frequency', [500; 1000; 2000], 'voltage', [1; targetVoltage; 3]);

s = struct();
s.version = 1;
s.CalibrationData = calData;
s.MicSensitivity = 2.24;
s.NormativeValue = 94;
s.ReferenceLevel = 94;
s.ReferenceFrequency = 1000;
s.ExcitationVoltage = 1;
s.CalibrationTimestamp = datetime('now');

esgcFile = fullfile(tempdir, 'smoke_test_stimtype_cal.esgc');
save(esgcFile, '-struct', 's');
cleanupEsgc = onCleanup(@() delete(esgcFile));

% 1. StimType with loaded calibration as a protocol parameter level -------
cal = stimgen.StimCalibration();
cal.load_calibration(esgcFile);
assert(isstruct(cal.CalibrationData) && isfield(cal.CalibrationData, 'tone'), ...
    'StimCalibration did not load the tone LUT');

tone = stimgen.Tone;
tone.Frequency = 1000;
tone.SoundLevel = 94;   % ReferenceLevel -> adjusted voltage equals LUT voltage
tone.Calibration = cal;

protocol = epsych.Protocol(Name = 'StimTypeCalRoundtrip');
module = protocol.Interfaces(1).Module;
module.add_parameter('Stimulus', tone, Type = 'StimType');
fprintf('PASS: StimType parameter created with attached calibration\n');

% 2. Protocol .eprot save/load round-trip ---------------------------------
eprotFile = fullfile(tempdir, 'smoke_test_stimtype_cal.eprot');
protocol.save(eprotFile);
cleanupEprot = onCleanup(@() delete(eprotFile));

loaded = epsych.Protocol.load(eprotFile);
loadedParam = [];
for m = loaded.Interfaces(1).Module
    idx = find(strcmp({m.Parameters.Name}, 'Stimulus'), 1);
    if ~isempty(idx)
        loadedParam = m.Parameters(idx);
        break
    end
end
assert(~isempty(loadedParam), 'Stimulus parameter not found after protocol load');
assert(isequal(loadedParam.Type, 'StimType'), 'Parameter type not preserved');

loadedTone = loadedParam.Values{1};
assert(isa(loadedTone, 'stimgen.Tone'), 'StimType level not restored as stimgen.Tone');

loadedCal = loadedTone.Calibration;
assert(isa(loadedCal, 'stimgen.StimCalibration'), 'Calibration not restored on StimType');
assert(isstruct(loadedCal.CalibrationData) && isfield(loadedCal.CalibrationData, 'tone'), ...
    'CalibrationData lost in protocol round-trip');
assert(isequal(loadedCal.CalibrationData.tone.voltage, calData.tone.voltage), ...
    'Tone LUT voltages changed in round-trip');
fprintf('PASS: .eprot round-trip preserves StimType calibration (LUT intact)\n');

% 3. Restored StimType applies calibration in update_signal ---------------
loadedTone.update_signal();
peakVoltage = max(abs(loadedTone.Signal));
assert(abs(peakVoltage - targetVoltage) < 0.05 * targetVoltage, ...
    'Expected calibrated peak near %.3g V, got %.3g V', targetVoltage, peakVoltage);
fprintf('PASS: update_signal scales restored stimulus to %.3g V (LUT: %.3g V)\n', ...
    peakVoltage, targetVoltage);

fprintf('--- StimType calibration round-trip passed ---\n');
end
