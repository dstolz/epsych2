function DefineBoxFig(self, a)
% DefineBoxFig — Configure the per-box behavior GUI function.
% Inputs
%   a — Function name/handle or 'default'; prompts if empty; empty to disable.
% Expected Signature
%   BoxFig(RUNTIME)
arguments
    self (1,1) ep_RunExpt2
    a = []
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

if ~isempty(a) && ischar(a) && strcmp(a,'default')
    a = 'ep_GenericGUI';
elseif isempty(a) || ~isfield(self.FUNCS,'BoxFig')
    if ~isfield(self.FUNCS,'BoxFig') || isempty(self.FUNCS.BoxFig)
        self.FUNCS.BoxFig = 'ep_GenericGUI';
    end
    ontop = self.AlwaysOnTop(false);
    if isa(self.FUNCS.BoxFig,'function_handle'), self.FUNCS.BoxFig = func2str(self.FUNCS.BoxFig); end
    a = inputdlg('GUI Figure','Specify Custom GUI Figure:',1,{self.FUNCS.BoxFig});
    self.AlwaysOnTop(ontop);
    if isempty(a), return, end
    a = char(a);
end

if isempty(a)
    vprintf(0,'No GUI Figure specified. This is OK, but no figure will be called on start.')
    self.FUNCS.BoxFig = [];
    self.CheckReady
    return
end

if isa(a,'function_handle'), a = func2str(a); end
b = which(a);
if isempty(b)
    ontop = self.AlwaysOnTop(false);
    errordlg(sprintf('The figure ''%s'' was not found on the current path.',a),'Define Function','modal')
    self.AlwaysOnTop(ontop)
    return
end

vprintf(0,'GUI Figure:\t%s\t(%s)\n',a,b)
self.FUNCS.BoxFig = a;
self.CheckReady
