function ok = LocateProtocol(self, pfn)
% LocateProtocol — Set or add the protocol file for a subject.
% Inputs
%   pfn (string) — Optional protocol filepath; prompts if empty.
% Output
%   ok (logical) — True when a valid protocol file is assigned.
arguments
    self
    pfn string = ""
end
ok = false;
if self.STATE >= PRGMSTATE.RUNNING, return, end

if strlength(pfn) == 0
    pn = getpref('ep_RunExpt_Setup','PDir',cd);
    if ~exist(pn,'dir'), pn = cd; end
    [fn,pn] = uigetfile('*.prot','Locate Protocol',pn);
    if isequal(fn,0), return, end
    setpref('ep_RunExpt_Setup','PDir',pn);
    pfn = fullfile(pn,fn);
end

if ~exist(pfn,'file')
    warndlg(sprintf('The file "%s" does not exist.',pfn),'Psych Config','modal')
    return
end

if isempty(self.CONFIG) || isempty(self.CONFIG(1).PROTOCOL)
    self.CONFIG(1).protocol_fn = pfn;
else
    self.CONFIG(end+1).protocol_fn = pfn;
end
ok = true;
