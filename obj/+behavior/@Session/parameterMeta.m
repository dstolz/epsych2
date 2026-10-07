function m = parameterMeta(sess, field)
% m = parameterMeta(sess, field)
% What the session's snapshot says about the parameter saved under a DATA
% field: its name, unit and range.
%
% Parameters:
%   field - DATA field (matlab.lang.makeValidName of the parameter's Name)
%
% Returns:
%   m - struct Field, Name, Unit, Type, Interface, Module (string, "" when
%       unknown) and Min, Max (double, NaN when unknown). A field the
%       snapshot does not describe -- a legacy file, or a field that is not
%       a parameter -- gets Name = field and everything else unknown.
%
% See also: behavior.Session.parameterTable

arguments
    sess (1,1) behavior.Session
    field (1,1) string
end

m = struct('Field', field, 'Name', field, 'Unit', "", 'Min', NaN, 'Max', NaN, ...
    'Type', "", 'Interface', "", 'Module', "");

P = sess.ParameterMeta;
if isempty(P), return, end
k = find(P.Field == field, 1);
if isempty(k), return, end

for f = ["Name" "Unit" "Type" "Interface" "Module"]
    m.(f) = string(P.(f)(k));
end
m.Min = double(P.Min(k));
m.Max = double(P.Max(k));

end
