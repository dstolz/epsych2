function design_filter(obj)
% design_filter(obj)
% Design an arbitrary-magnitude FIR equalizer from the tone LUT.
% Stores the result in CalibrationData.filter and
% CalibrationData.filterGrpDelay.
% Requires a completed tone calibration.
if ~obj.IsCalibrated || ~isfield(obj.CalibrationData, 'tone')
    error('stimgen:calibration:Engine:noToneData', ...
        'Tone calibration must be completed before designing the filter.');
end
stimgen.util.vprintf(1, 'Designing equalization filter...');

fs   = obj.Fs;
d    = obj.CalibrationData.tone;
freq = d.frequency;
volt = d.voltage;

% Build [0, freqs, Nyquist] amplitude table.
fAll = [0;      freq(:); fs/2];
aAll = [volt(1); volt(:); volt(end)];

% Normalize to [0 1] range for designfilt; clamp endpoint.
fn       = fAll ./ (fs / 2);
fn(end)  = 1;
nOrd     = length(freq);

filt = designfilt('arbmagfir', ...
    'FilterOrder',  nOrd, ...
    'Frequencies',  fn, ...
    'Amplitudes',   aAll, ...
    'SampleRate',   fs);

gd = round(mean(grpdelay(filt)));

obj.CalibrationData.filter       = filt;
obj.CalibrationData.filterGrpDelay = gd;

stimgen.util.vprintf(1, 'Filter designed: order=%d, group delay=%d samples', nOrd, gd);
fprintf('<a href="matlab:fvtool(ans)">View filter</a>\n');
assignin('base', 'ans', filt);
end
