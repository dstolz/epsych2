function set_value(obj,value)

if isequal(obj.Access,'Read')
    vprintf(0,1,'"%s" is a read-only parameter',obj.Name)
    return
end

if ~ismember(obj.Type, {'String', 'File', 'StimType'}) && (value < obj.Min || value > obj.Max)
    vprintf(0,1,'Value for "%s" parameter is out of range: min = %g, max = %g, supplied = %g',obj.Min,obj.Max,value)
    return
end

obj.Value = value;
if ~isequal(obj.HW,0)
    obj.HW.set_parameter(obj,value);
end
% `now` is much faster than `datetime("now")`
% use: dt = datetime(obj.lastUpdated, 'ConvertFrom','datenum', 'TimeZone','local');
% convert to ms: ts = uint64((obj.lastUpdated - 719529) * 86400 * 1000);
 obj.lastUpdated = now;
