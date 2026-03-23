function rstr = get_string(hObj)
% rstr = get_string(hObj)
%
% Get currently select string in a gui control such as popup menu or
% listbox
%
% Daniel.Stolzberg@gmail.com 2013
% [MIGRATED from helpers/get_string.m to obj/+utils/get_string.m]

v = get(hObj,'Value');
s = cellstr(get(hObj,'String'));
if isempty(s)
    rstr = '';
elseif length(v) == 1
    rstr = s{v};
else
    rstr = s(v);
end