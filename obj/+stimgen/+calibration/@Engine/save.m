function save(obj, ffn)
% obj.save()
% obj.save(ffn)
% Save calibration to a .esgc file.
%
% Parameters:
%   ffn - full file path (char, optional); prompts if omitted
arguments
    obj
    ffn (1,:) char = ''
end
if ~obj.IsCalibrated
    error('stimgen:calibration:Engine:notCalibrated', ...
        'Nothing to save - calibration has not been run.');
end
if isempty(ffn)
    pn = getpref('StimCalibration', 'path', pwd);
    [fn, pn] = uiputfile( ...
        {'*.esgc','EPsych Stim Calibration (*.esgc)'}, ...
        'Save Calibration', pn);
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
    setpref('StimCalibration', 'path', pn);
end
[~, ~, ext] = fileparts(ffn);
if ~strcmpi(ext, '.esgc')
    ffn = [ffn '.esgc'];
end

s.version             = 1;
s.CalibrationData     = obj.CalibrationData;
s.MicSensitivity      = obj.MicSensitivity;
s.NormativeValue      = obj.NormativeValue;
s.ReferenceLevel      = obj.ReferenceLevel;
s.ReferenceFrequency  = obj.ReferenceFrequency;
s.ExcitationVoltage   = obj.ExcitationVoltage;
s.CalibrationTimestamp = obj.CalibrationTimestamp;

save(ffn, '-struct', 's');
stimgen.util.vprintf(0, 'Saved calibration: "%s"', ffn);
end
