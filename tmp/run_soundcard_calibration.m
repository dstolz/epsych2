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
adapter = stimgen.calibration.WindowsSoundCardAdapter( ...
    SampleRate=SAMPLE_RATE, ...
    Device=DEVICE_NAME, ...
    SamplesPerFrame=SAMPLES_PER_FRAME, ...
    InputChannel=INPUT_CHANNEL);

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
