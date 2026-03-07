function DefineSavingFcn(self, a)
% DefineSavingFcn — Configure the data-saving function.
% Inputs
%   a — Function name/handle or 'default'; prompts if empty.
% Requirements
%   The function must accept one input (RUNTIME) and return no outputs.
arguments
    self (1,1) ep_RunExpt2
    a = []
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

if ~isempty(a) && ischar(a) && strcmp(a,'default')
    a = 'ep_SaveDataFcn';
elseif isempty(a) || ~isfield(self.FUNCS,'SavingFcn')
    if ~isfield(self.FUNCS,'SavingFcn') || isempty(self.FUNCS.SavingFcn)
        self.FUNCS.SavingFcn = 'ep_SaveDataFcn';
    end
    ontop = self.AlwaysOnTop(false);
    a = inputdlg('Data Saving Function','Saving Function',1,{self.FUNCS.SavingFcn});
    self.AlwaysOnTop(ontop);
    a = char(a);
    if isempty(a), return, end
end

if isa(a,'function_handle'), a = func2str(a); end
b = which(a);
if isempty(b)
    ontop = self.AlwaysOnTop(false);
    errordlg(sprintf('The function ''%s'' was not found on the current path.',a),'Saving Function','modal')
    self.AlwaysOnTop(ontop);
    return
end

if nargin(a) ~= 1 || nargout(a) ~= 0
    ontop = self.AlwaysOnTop(false);
    errordlg('The Saving Data function must take 1 input and return 0 outputs.','Saving Function','modal')
    self.AlwaysOnTop(ontop);
    return
end

vprintf(0,'Saving Data function:\t%s\t(%s)\n',a,b)
self.FUNCS.SavingFcn = a;
self.CheckReady
