function obj = fromStruct(S)
% obj = stimgen.StimType.fromStruct(S)
% Reconstruct a stimgen.StimType subclass instance from a serialized struct.
obj = feval(char(S.Class));
obj.DisplayName = S.DisplayName;
obj.Fs               = S.Fs;
obj.ApplyCalibration = S.ApplyCalibration;
obj.ApplyWindow      = S.ApplyWindow;
if isfield(S, 'VariantSelectionMode')
    obj.VariantSelectionMode = string(S.VariantSelectionMode);
end
if isfield(S, 'VariantCombinationMode')
    obj.VariantCombinationMode = string(S.VariantCombinationMode);
end
if isfield(S, 'VariantSelectorClass')
    obj.VariantSelectorClass = string(S.VariantSelectorClass);
end
if isfield(S, 'VariantSelectorConfig')
    obj.VariantSelectorConfig = S.VariantSelectorConfig;
end
if isfield(S, 'VariantReselectOnUpdate')
    obj.VariantReselectOnUpdate = logical(S.VariantReselectOnUpdate);
end
if isfield(S, 'Calibration')
    calData = S.Calibration;
    if isa(calData, 'stimgen.StimCalibration')
        obj.Calibration = calData;
    elseif isstruct(calData)
        obj.Calibration = stimgen.StimCalibration.loadobj(calData);
    end
end
for k = 1:numel(S.UserProperties)
    pname = char(S.UserProperties(k));
    if isprop(obj, pname) && isfield(S, pname)
        obj.(pname) = S.(pname);
    end
end
end
