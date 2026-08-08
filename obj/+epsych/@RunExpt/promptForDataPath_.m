function promptForDataPath_(self)
% promptForDataPath_ — Ask for the default data directory when it was never customized.
% The 'RunExpt'/'DataPath' preference is only written by the Customize dialog
% or DefineDataPath, so its absence means the session would silently save into
% the current working directory. Dismissing the prompt leaves the preference
% unset so the question returns on the next launch.

if ispref('RunExpt','DataPath'), return, end

fig = self.H.figure1;
if ~isgraphics(fig), return, end

ontop = self.AlwaysOnTop(false);
sel = uiconfirm(fig, ...
    sprintf(['No default data path has been set. Experiment data will be saved to the ' ...
             'current directory:\n\n%s\n\nSelect a folder now?'], cd), ...
    'EPsych — Data Path', ...
    'Options',{'Select Folder...','Not Now'}, ...
    'DefaultOption',1,'CancelOption',2,'Icon','question');
self.AlwaysOnTop(ontop);

if ~isequal(sel,'Select Folder...'), return, end

self.DefineDataPath
