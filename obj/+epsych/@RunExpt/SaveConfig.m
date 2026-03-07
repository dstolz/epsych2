function SaveConfig(self)
% SaveConfig — Persist CONFIG, FUNCS, and meta to a .config file.
% Behavior
%   Prompts for a destination, serializes current config/functions
%   together with EPsychInfo meta for reproducibility.
arguments
    self (1,1) ep_RunExpt2
end
if self.STATE == PRGMSTATE.NOCONFIG
    warndlg('Please first add a subject.','Save Configuration','modal')
    return
end

pn = getpref('ep_RunExpt_Setup','CDir',cd);
[fn,pn] = uiputfile('*.config','Save Current Configuration',pn);
if isequal(fn,0)
    vprintf(1,'Configuration not saved.\n')
    return
end

config = self.CONFIG; %#ok<NASGU>
funcs  = self.FUNCS;  %#ok<NASGU>

E = EPsychInfo;
meta = E.meta; %#ok<NASGU>

save(fullfile(pn,fn),'config','funcs','meta','-mat')
setpref('ep_RunExpt_Setup','CDir',pn)
vprintf(0,'Configuration saved as: ''%s''\n',fullfile(pn,fn))
