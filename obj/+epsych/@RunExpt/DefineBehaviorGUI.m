function DefineBehaviorGUI(self, a)
% DefineBehaviorGUI — Configure the session's behavior GUI function.
% Inputs
%   a — Function name/handle or 'default'; prompts if empty; empty to disable.
% Expected Signature
%   BehaviorGUI(RUNTIME)
% Notes
%   The operator's path is a project's BehaviorGUI field (Subjects & Projects), which
%   assignToSession applies here on commit. This method remains for scripts and
%   for a session assembled without the roster.
arguments
    self
    a = []
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

if ~isempty(a) && ischar(a) && strcmp(a,'default')
    a = 'ep_GenericGUI';
elseif isempty(a) || ~isfield(self.FUNCS,'BehaviorGUI')
    if ~isfield(self.FUNCS,'BehaviorGUI') || isempty(self.FUNCS.BehaviorGUI)
        self.FUNCS.BehaviorGUI = 'ep_GenericGUI';
    end
    ontop = self.AlwaysOnTop(false);
    if isa(self.FUNCS.BehaviorGUI,'function_handle'), self.FUNCS.BehaviorGUI = func2str(self.FUNCS.BehaviorGUI); end
    a = inputdlg('GUI Figure','Specify Custom GUI Figure:',1,{self.FUNCS.BehaviorGUI});
    self.AlwaysOnTop(ontop);
    if isempty(a), return, end
    a = char(a);
end

if isempty(a)
    vprintf(0,'No GUI Figure specified. This is OK, but no figure will be called on start.')
    self.FUNCS.BehaviorGUI = [];
    self.CheckReady
    return
end

if isa(a,'function_handle'), a = func2str(a); end
b = which(a);
if isempty(b)
    ontop = self.AlwaysOnTop(false);
    errordlg(sprintf('The figure ''%s'' was not found on the current path.',a),'Define Function','modal')
    self.AlwaysOnTop(ontop);
    return
end

vprintf(0,'GUI Figure:\t%s\t(%s)\n',a,b)
self.FUNCS.BehaviorGUI = a;
self.CheckReady
