function apply_normalization(obj)
% apply_normalization(obj)
% Apply normalization to obj.Signal according to the Normalization constant.

if obj.temporarilyDisableSignalMods || isempty(obj.Signal), return; end
switch obj.Normalization
    case "absmax"
        obj.Signal = obj.Signal ./ max(abs(obj.Signal));
    case "max"
        obj.Signal = obj.Signal ./ max(obj.Signal);
    case "min"
        obj.Signal = obj.Signal ./ min(obj.Signal);
    case "rms"
        obj.Signal = obj.Signal ./ sqrt(mean(obj.Signal.^2));
end
