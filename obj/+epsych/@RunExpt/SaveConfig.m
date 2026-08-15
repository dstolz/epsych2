function SaveConfig(self)
% SaveConfig — Persist CONFIG, FUNCS, and meta to a .ecfg file.
% Behavior
%   Prompts for a destination, serializes current config/functions
%   together with EPsychInfo meta for reproducibility.
arguments
    self
end
if self.STATE >= PRGMSTATE.RUNNING, return, end
if self.STATE == PRGMSTATE.NOCONFIG
    warndlg('Please first add a subject.','Save Configuration','modal')
    return
end

pn = getpref('ep_RunExpt_Setup','CDir',cd);
[fn,pn] = uiputfile('*.ecfg','Save Current Configuration',pn);
if isequal(fn,0)
    vprintf(1,'Configuration not saved.\n')
    self.setStatus('Configuration was not saved.')
    return
end

config = self.CONFIG;

% Serialize embedded Protocol and Subject objects to portable structs so the
% .ecfg file contains only plain MAT data (no handle class objects).
for i = 1:length(config)
    if isa(config(i).PROTOCOL, 'epsych.Protocol') && isvalid(config(i).PROTOCOL)
        config(i).PROTOCOL = config(i).PROTOCOL.toStruct();
    end
    if isa(config(i).SUBJECT, 'epsych.Subject')
        config(i).SUBJECT = config(i).SUBJECT.toStruct();
    end
end

% The behavior-GUI callback is written under its former name too, so a rig one
% release behind still finds it. Mirrored onto the copy being saved rather than
% onto self.FUNCS, which keeps exactly one canonical field.
funcs  = self.FUNCS;
funcs.BehaviorGUI = funcs.BoxFig;

E = EPsychInfo;
meta = E.meta;

save(fullfile(pn,fn),'config','funcs','meta','-mat')
setpref('ep_RunExpt_Setup','CDir',pn)
self.CurrentConfigFile = string(fullfile(pn,fn));
vprintf(0,'Configuration saved as: ''%s''\n',fullfile(pn,fn))
self.setStatus(sprintf('Saved configuration as "%s".',fn))
