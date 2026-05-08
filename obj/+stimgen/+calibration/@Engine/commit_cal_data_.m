function cd = commit_cal_data_(obj)
% Return a valid CalibrationData struct, preserving any existing
% fields (tone, click, filter) so incremental sweeps accumulate.
if isstruct(obj.CalibrationData)
    cd = obj.CalibrationData;
else
    cd = struct( ...
        'filter',        [], ...
        'filterGrpDelay', 0);
end
end
