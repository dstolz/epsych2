function tf = is_non_vectorizable_property_(~, propName)
% tf = is_non_vectorizable_property_(obj, propName)
% Return true when propName is one of the properties that must remain scalar.
% Non-vectorizable properties: Fs, ApplyCalibration, ApplyWindow.

tf = any(strcmp(string(propName), ["Fs","ApplyCalibration","ApplyWindow"]));
