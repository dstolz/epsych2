function DefineAddSubject(self, a)
% DefineAddSubject — Configure the subject creation function.
% Inputs
%   a — Function name/handle or 'default'; prompts if empty.
% Expected Signature
%   S = AddSubjectFcn(S, boxids)
arguments
    self
    a = []
end
if self.STATE >= PRGMSTATE.RUNNING, return, end
if ~isempty(a) && ischar(a) && strcmp(a,'default')
    a = 'ep_AddSubject';
elseif isempty(a) || ~isfield(self.FUNCS,'AddSubjectFcn')
    if ~isfield(self.FUNCS,'AddSubjectFcn') || isempty(self.FUNCS.AddSubjectFcn)
        self.FUNCS.AddSubjectFcn = 'ep_AddSubject';
    end
    ontop = self.AlwaysOnTop;
    self.AlwaysOnTop(false)
    if isa(self.FUNCS.AddSubjectFcn,'function_handle'), self.FUNCS.AddSubjectFcn = func2str(self.FUNCS.AddSubjectFcn); end
    a = inputdlg('Add Subject Fcn','Specify Custom Add Subject:',1,{self.FUNCS.AddSubjectFcn});
    self.AlwaysOnTop(ontop)
    a = char(a);
    if isempty(a), return, end
end

if isa(a,'function_handle'), a = func2str(a); end
b = which(a);
if isempty(b)
    ontop = self.AlwaysOnTop;
    self.AlwaysOnTop(false)
    errordlg(sprintf('The function ''%s'' was not found on the current path.',a),'Define Function','modal')
    self.AlwaysOnTop(ontop)
    return
end

vprintf(0,'AddSubject function:\t%s\t(%s)\n',a,b)
self.FUNCS.AddSubjectFcn = a;
self.CheckReady
