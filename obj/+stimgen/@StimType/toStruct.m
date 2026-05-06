function S = toStruct(obj)
% S = toStruct(obj)
% Serialize StimType object to a struct.
% Signal, GUIHandles, and listeners are not included.
%
% Returns:
%   S - Struct with class metadata, core properties, calibration, and
%       user-defined property values.

% Basic class metadata
S = struct;
S.Class        = string(class(obj));
S.DisplayName  = obj.DisplayName;

% Core StimType properties
S.SoundLevel       = obj.SoundLevel;
S.Duration         = obj.Duration;
S.WindowDuration   = obj.WindowDuration;
S.WindowFcn        = obj.WindowFcn;
S.ApplyCalibration = obj.ApplyCalibration;
S.ApplyWindow      = obj.ApplyWindow;
S.Fs               = obj.Fs;
S.VariantSelectionMode = obj.VariantSelectionMode;
S.VariantCombinationMode = obj.VariantCombinationMode;
S.VariantSelectorClass = obj.VariantSelectorClass;
S.VariantSelectorConfig = obj.VariantSelectorConfig;
S.VariantReselectOnUpdate = obj.VariantReselectOnUpdate;

% Abstract/constant properties (same across instances of subclass)
S.CalibrationType  = obj.CalibrationType;
S.Normalization    = obj.Normalization;
S.IsMultiObj       = obj.IsMultiObj;

% Calibration
S.Calibration = obj.Calibration.toStruct;

% User-defined property list and values
S.UserProperties = obj.UserProperties;
for k = 1:numel(obj.UserProperties)
    pname = obj.UserProperties(k);
    if isprop(obj,pname)
        S.(pname) = obj.(pname);
    end
end
