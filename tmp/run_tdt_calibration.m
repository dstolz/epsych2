% run_tdt_calibration.m
% Full TDT (RPvds/RPcoX) sound-source calibration workflow — no GUI.
%
% Connects to a TDT device running an RPvds circuit, wraps it in an
% InterfaceAdapter, and drives stimgen.calibration.Engine directly to
% produce an .esgc calibration file. Edit the CONFIG section below to
% match your rig before running.
%
% The RPvds circuit MUST expose these tags (see the InterfaceAdapter
% contract and tmp/Calibration_TDT_RPcox_Template.json):
%   BufferSize   Integer, Write  - number of samples to play/record
%   BufferOut    Buffer,  Write  - output waveform data
%   x_Trigger    Boolean, Write  - start pulse (1 -> 0)
%   BufferIndex  Integer, Read   - acquisition progress counter
%   BufferIn     Buffer,  Read   - recorded microphone signal
%
% Usage:
%   run('run_tdt_calibration.m')
%   run_tdt_calibration          % if on the MATLAB path

%% ---- CONFIG ---- (edit these values for your rig) ----------------------

% TDT hardware / RPvds circuit
RPVDS_FILE     = fullfile(epsych_path,'examples','stimgen','StimGenCalibration.rcx'); % circuit exposing the tags above
MODULE_TYPE    = 'RZ6';   % 'RP2','RX6','RZ6','RZ5','RM1',... (must match your device)
MODULE_ALIAS   = 'RZ6Cal';% label for this module (used to name the output file)
DEVICE_NUMBER  = 1;       % device number as enumerated by zBUSmon
CONNECTION     = 'GB';    % 'GB' (Gigabit/Optibit) or 'USB'
FS_OVERRIDE    = 0;       % 0 = use circuit's native rate; else force Fs (Hz)

% Microphone reference
MIC_SENSITIVITY = .1;      % V/Pa. 0 = measure it via the calibrator below.
                          %       >0 = use this known value and SKIP the
                          %            reference measurement.
INTERACTIVE     = true;   % pause at the keyboard to place/remove the calibrator

% Engine calibration parameters
REF_LEVEL     = 94;       % dB SPL produced by your calibrator
REF_FREQ      = 1000;     % Hz produced by your calibrator
NORMATIVE     = 80;       % target SPL for the experiment
EXCITATION_V  = 1;        % output voltage during sweeps (TDT max 10 V; reduce if clipping)
SHOW_PLOTS    = true;     % display live waveform and spectrum during sweeps

% Tone sweep (required)
TONE_FREQS    = [];       % [] = default 50-point log sweep to Nyquist.
                          % e.g. logspace(log10(500), log10(40000), 40)
TONE_REPEATS  = 3;        % measurements averaged per frequency

% Optional additional calibrations
DO_CLICKS      = false;   % sweep click durations
CLICK_DURS     = [0.05 0.1 0.2 0.5 1.0] ./ 1000;  % seconds (50 us .. 1 ms)
CLICK_REPEATS  = 3;

DO_SWEPT_SINE  = false;   % broadband transfer-function measurement
SS_DURATION    = 1;       % chirp duration (s)
SS_REPEATS     = 4;

DO_FILTER      = true;   % design an equalization FIR filter from the tone LUT

% Output path for the calibration file
ESGC_FILE = fullfile(fileparts(mfilename('fullpath')), ...
    sprintf('%s_%s.esgc', MODULE_ALIAS, char(datetime('now', Format='yyyy-MM-dd'))));

%% ---- Connect to the TDT device ----------------------------------------
if ~isfile(RPVDS_FILE)
    error('RPvds circuit not found:\n  %s\nSet RPVDS_FILE in the CONFIG section.', RPVDS_FILE);
end

fprintf('Connecting to %s (device %d) on %s ...\n', MODULE_TYPE, DEVICE_NUMBER, CONNECTION);
try
    HW = hw.TDT_RPcox(RPVDS_FILE, MODULE_TYPE, MODULE_ALIAS, ...
        Interface=CONNECTION, Number=DEVICE_NUMBER, Fs=FS_OVERRIDE);
catch ME
    fprintf(2, '\nTDT connection failed:\n  %s\n\n', ME.message);
    fprintf(2, ['Troubleshooting:\n', ...
        '  - Confirm the device is powered and enumerated in zBUSmon.\n', ...
        '  - Check DEVICE_NUMBER and CONNECTION (%s) match your rig.\n', ...
        '  - Verify MODULE_TYPE (%s) matches the physical device.\n', ...
        '  - Make sure the RPvds file compiles for this device.\n'], ...
        CONNECTION, MODULE_TYPE);
    return
end

if ~HW.IsConnected
    error('TDT device did not report a connected/loaded circuit. Check zBUSmon and the RPvds file.');
end

% Ensure hardware is halted/torn down when the script ends or errors out.
cleanupHW = onCleanup(@() safe_disconnect_(HW));

%% ---- Build adapter and engine ------------------------------------------
try
    adapter = stimbridge.InterfaceAdapter(HW);   % Fs auto-discovered from module
catch ME
    fprintf(2, '\nInterfaceAdapter setup failed:\n  %s\n\n', ME.message);
    fprintf(2, ['The RPvds circuit must expose these tags:\n', ...
        '  BufferSize, BufferOut, !Trigger (or x_Trigger), BufferIndex, BufferIn\n', ...
        'See tmp/Calibration_TDT_RPcox_Template.json for the expected layout.\n']);
    return
end

fprintf('Adapter attached. Sample rate: %.4f Hz\n', adapter.sample_rate());

eng = stimgen.calibration.Engine(adapter);

eng.set_configuration( ...
    ReferenceLevel=REF_LEVEL, ...
    ReferenceFrequency=REF_FREQ, ...
    NormativeValue=NORMATIVE, ...
    ExcitationVoltage=EXCITATION_V, ...
    ShowLivePlots=SHOW_PLOTS);

%% ---- Step 1: microphone reference --------------------------------------
if MIC_SENSITIVITY > 0
    eng.set_configuration(MicSensitivity=MIC_SENSITIVITY);
    fprintf('Using known mic sensitivity: %.6g V/Pa (reference measurement skipped).\n', MIC_SENSITIVITY);
else
    if INTERACTIVE
        prompt_(sprintf(['Place the %g dB SPL / %g Hz calibrator on the microphone and turn it on.\n', ...
            'Press ENTER to measure the reference ...'], REF_LEVEL, REF_FREQ));
    end
    eng.calibrate_reference();
    fprintf('Measured mic sensitivity: %.6g V/Pa\n', eng.MicSensitivity);
    if INTERACTIVE
        prompt_(['Remove the calibrator and position the microphone at the measurement point.\n', ...
            'Press ENTER to begin the tone sweep ...']);
    end
end

%% ---- Step 2: tone calibration (required) -------------------------------
fprintf('Calibrating tones (%d repeats/point) ...\n', TONE_REPEATS);
eng.calibrate_tones(TONE_FREQS, TONE_REPEATS);

%% ---- Step 3: optional additional calibrations --------------------------
if DO_CLICKS
    fprintf('Calibrating clicks (%d repeats/point) ...\n', CLICK_REPEATS);
    eng.calibrate_clicks(CLICK_DURS, CLICK_REPEATS);
end

if DO_SWEPT_SINE
    fprintf('Calibrating swept sine (%g s chirp, %d repeats) ...\n', SS_DURATION, SS_REPEATS);
    eng.calibrate_swept_sine(SS_DURATION, [], SS_REPEATS);
end

if DO_FILTER
    fprintf('Designing equalization filter from tone LUT ...\n');
    eng.design_filter();
end

%% ---- Step 4: save ------------------------------------------------------
eng.save(ESGC_FILE);
fprintf('\nCalibration complete. Saved to:\n  %s\n', ESGC_FILE);

%% ---- Local helpers -----------------------------------------------------
function prompt_(msg)
% prompt_(msg)
% Print a message and block until the user presses ENTER.
input(sprintf('\n%s ', msg), 's');
end

function safe_disconnect_(HW)
% safe_disconnect_(HW)
% Halt and disconnect the TDT interface, ignoring teardown errors.
try
    HW.disconnect();
catch
    % Ignore disconnect failures during cleanup.
end
end
