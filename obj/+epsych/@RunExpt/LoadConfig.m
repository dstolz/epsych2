function LoadConfig(self, cfn)
% LoadConfig — Load a .config file and apply stored functions.
% Inputs
%   cfn (string) — Optional config filepath; prompts if empty.
% Behavior
%   Loads CONFIG and FUNCS from file (if present), updates subject
%   list, and sets STATE to READY when requirements are met.
arguments
    self
    cfn string = ""
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

if strlength(cfn) == 0
    pn = getpref('ep_RunExpt_Setup','CDir',cd);
    [fn,pn] = uigetfile('*.config','Open Configuration File',pn);
    if isequal(fn,0), return, end
    setpref('ep_RunExpt_Setup','CDir',pn);
    cfn = fullfile(pn,fn);
end

if ~exist(cfn,'file')
    warndlg(sprintf('The file "%s" does not exist.',cfn),'RunExpt','modal')
    return
end

vprintf(0,'Loading configuration file: ''%s''\n',cfn)
warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
S = load(cfn,'-mat');
warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

if ~isfield(S,'config')
    errordlg('Invalid Configuration file','PsychConfig','modal')
    return
end

self.ClearConfig
self.CONFIG = S.config;

if isfield(S,'funcs')
    self.FUNCS = S.funcs;
    self.SetDefaultFuncs(self.FUNCS)
else
    self.FUNCS = self.GetDefaultFuncs;
end

self.UpdateSubjectList
self.CheckReady
self.RememberRecentConfig(cfn)
