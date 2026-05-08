% run_soundcard_calibration.m
% Full Windows sound card calibration workflow.
%
% Generates (or reuses) a Software-only .eprot, opens the CalibrationGui,
% and attaches a WindowsSoundCardAdapter. Edit the CONFIG section below
% to match your device before running.
%
% Usage:
%   run('run_soundcard_calibration.m')
%   run_soundcard_calibration   % if on the MATLAB path

%% ---- CONFIG ---- (edit these values for your rig) ----------------------

SAMPLE_RATE    = 48000;  % Hz — must match your device's native rate
DEVICE_NAME    = "";     % "" uses the system default; or e.g. "Focusrite USB"
INPUT_CHANNEL  = 1;      % microphone channel index on the input device
SAMPLES_PER_FRAME = 1024;% streaming frame size; increase if you hear glitches

% Engine calibration parameters
REF_LEVEL     = 94;      % dB SPL produced by your calibrator
REF_FREQ      = 1000;    % Hz produced by your calibrator
NORMATIVE     = 80;      % target SPL for the experiment
EXCITATION_V  = 1;       % output voltage during sweeps (reduce if clipping)
SHOW_PLOTS    = true;    % display live waveform and spectrum during sweeps

% Output path for the .eprot (used only as a protocol container for the GUI)
EPROT_FILE = fullfile(fileparts(mfilename('fullpath')), 'soundcard_calibration.eprot');

%% ---- Generate .eprot if it does not already exist ----------------------
if ~isfile(EPROT_FILE)
    fprintf('Creating protocol file: %s\n', EPROT_FILE);
    create_soundcard_calibration_protocol(EPROT_FILE);
end

%% ---- Build adapter and engine ------------------------------------------
try
    adapter = stimgen.calibration.WindowsSoundCardAdapter( ...
        SampleRate=SAMPLE_RATE, ...
        Device=DEVICE_NAME, ...
        SamplesPerFrame=SAMPLES_PER_FRAME, ...
        InputChannel=INPUT_CHANNEL);
catch ME
    fprintf(2, '\nWindowsSoundCardAdapter initialization failed:\n  %s\n\n', ME.message);
    fprintf(2, ['No full-duplex device was available for the current settings.\n', ...
        'Set DEVICE_NAME to a specific full-duplex endpoint (not "").\n', ...
        'You can test device names with the list below.\n\n']);

    deviceNames = list_audio_devices_();
    if isempty(deviceNames)
        fprintf(2, 'No device names were returned by Audio Toolbox device queries.\n');
    else
        fprintf('Audio device candidates:\n');
        for k = 1:numel(deviceNames)
            fprintf('  %2d) %s\n', k, deviceNames{k});
        end
    end

    fprintf(['\nExample:\n', ...
        '  DEVICE_NAME = "<exact device name from list>";\n', ...
        'Then run run_soundcard_calibration again.\n']);
    return
end

eng = stimgen.calibration.Engine(adapter);

eng.set_configuration( ...
    ReferenceLevel=REF_LEVEL, ...
    ReferenceFrequency=REF_FREQ, ...
    NormativeValue=NORMATIVE, ...
    ExcitationVoltage=EXCITATION_V, ...
    ShowLivePlots=SHOW_PLOTS);

%% ---- Open GUI and attach adapter ---------------------------------------
gui = stimgen.calibration.CalibrationGui(eng);
gui.show();

fprintf(['\n', ...
    'CalibrationGui is open.\n', ...
    'The WindowsSoundCardAdapter is already attached — buttons should be active.\n', ...
    '\n', ...
    'Next steps:\n', ...
    '  1) Place your calibrator on the microphone and click "Measure Reference".\n', ...
    '  2) Remove calibrator, position mic at measurement point.\n', ...
    '  3) Click "Calibrate Tones".\n', ...
    '  4) Optionally: Calibrate Clicks, Calibrate Swept Sine, Design Filter.\n', ...
    '  5) File > Save .esgc to save the calibration.\n']);

function deviceNames = list_audio_devices_()
% deviceNames = list_audio_devices_()
% Return a de-duplicated list of candidate audio device names.
deviceNames = {};

% Query #1: static-style call supported in some MATLAB releases.
try
    names = getAudioDevices('audioPlayerRecorder');
    deviceNames = append_names_(deviceNames, names);
catch
end

% Query #2: object-style call supported in other MATLAB releases.
try
    apr = audioPlayerRecorder(SampleRate=48000);
    names = getAudioDevices(apr);
    release(apr);
    deviceNames = append_names_(deviceNames, names);
catch
end

% Keep stable order and unique values.
if ~isempty(deviceNames)
    [~, ia] = unique(deviceNames, 'stable');
    deviceNames = deviceNames(ia);
end
end

function out = append_names_(in, names)
% out = append_names_(in, names)
% Normalize device-name containers into a cellstr row vector.
out = in;
if isempty(names)
    return
end

if isstring(names)
    names = cellstr(names(:));
elseif ischar(names)
    names = cellstr(names);
elseif iscell(names)
    names = names(:);
else
    return
end

for i = 1:numel(names)
    n = names{i};
    if isstring(n)
        n = char(n);
    end
    if ischar(n)
        n = strtrim(n);
        if ~isempty(n)
            out{end+1} = n;
        end
    end
end
end
