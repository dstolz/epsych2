function set_configuration(obj, options)
% set_configuration(obj)
% set_configuration(obj, Name=Value)
%
% Update engine calibration parameters in one call.
%
% Parameters (Name=Value):
%   MicSensitivity     - (1,1) double, > 0
%   ReferenceLevel     - (1,1) double, > 0
%   ReferenceFrequency - (1,1) double, > 0
%   NormativeValue     - (1,1) double, > 0
%   ExcitationVoltage  - (1,1) double, > 0
%   ShowLivePlots      - (1,1) logical
arguments
    obj
    options.MicSensitivity     (1,1) double {mustBePositive,mustBeFinite} = obj.MicSensitivity
    options.ReferenceLevel     (1,1) double {mustBePositive,mustBeFinite} = obj.ReferenceLevel
    options.ReferenceFrequency (1,1) double {mustBePositive,mustBeFinite} = obj.ReferenceFrequency
    options.NormativeValue     (1,1) double {mustBePositive,mustBeFinite} = obj.NormativeValue
    options.ExcitationVoltage  (1,1) double {mustBePositive} = obj.ExcitationVoltage
    options.ShowLivePlots      (1,1) logical = obj.ShowLivePlots
end

obj.MicSensitivity    = options.MicSensitivity;
obj.ReferenceLevel    = options.ReferenceLevel;
obj.ReferenceFrequency = options.ReferenceFrequency;
obj.NormativeValue    = options.NormativeValue;
obj.ExcitationVoltage = options.ExcitationVoltage;
obj.ShowLivePlots     = options.ShowLivePlots;
end
