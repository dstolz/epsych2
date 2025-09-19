function stay_on_top(hObj)
% stay_on_top(hObj)
% 
% Where hObj is the handle to a GUI checkbox (uicheckbox).  The Value of
% the checkbox is used to determine if the parent figure is maintained in
% the foreground.
%
% Also sets a preference (setpref) with the parent figure name as the
% 'GROUP' and 'stayOnTop' as the 'PREF'.

f = ancestor(hObj,'figure');
if isempty(f), return; end
v = hObj.Value;
figAlwaysOnTop(f,v);
setpref(f.Tag,'stayOnTop',v);
