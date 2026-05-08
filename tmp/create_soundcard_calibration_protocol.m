% create_soundcard_calibration_protocol.m
% create_soundcard_calibration_protocol(outFile)
% Create a minimal Software-only .eprot for Windows sound card calibration.
%
% Generates a compiled protocol with a single Software interface containing
% placeholder metadata parameters. There are no hardware modules — the protocol
% is used only so that the CalibrationGui "Initialize Runtime From Protocol"
% menu item has a valid file to load. The WindowsSoundCardAdapter is attached
% separately after the protocol loads (see run_soundcard_calibration.m).
%
% Parameters:
%   outFile - (optional) full path for the saved .eprot file.
%             Defaults to soundcard_calibration.eprot in the same folder.
%
% Usage:
%   create_soundcard_calibration_protocol()
%   create_soundcard_calibration_protocol('C:\MyRig\soundcard_cal.eprot')

function create_soundcard_calibration_protocol(outFile)
arguments
    outFile (1,:) char = fullfile(fileparts(mfilename('fullpath')), 'soundcard_calibration.eprot')
end

%% Build protocol
p = epsych.Protocol( ...
    Name='SoundCardCalibration', ...
    Info='Minimal Software-only protocol for Windows sound card calibration. ' ...
       + 'Load this in CalibrationGui > File > Initialize Runtime From Protocol, ' ...
       + 'then attach WindowsSoundCardAdapter via the run_soundcard_calibration script.');

p.setOption('randomize',         false);
p.setOption('numReps',           1);
p.setOption('ISI',               0);
p.setOption('trialFunc',         '');
p.setOption('compileAtRuntime',  false);
p.setOption('IncludeWAVBuffers', false);
p.setOption('ConnectionType',    'GB');

%% Add informational parameters to the default Software module.
% These are not used during calibration sweeps but keep the protocol
% non-empty so compile() succeeds.
mod = p.SoftwareModule.Module;

mod.add_parameter('SampleRate',    48000,  Type='Float',   Access='Any');
mod.add_parameter('InputChannel',  1,      Type='Integer', Access='Any');
mod.add_parameter('DeviceName',    '',     Type='String',  Access='Any');

%% Compile and save
p.compile();
p.save(outFile);
fprintf('Protocol saved to: %s\n', outFile);
end
