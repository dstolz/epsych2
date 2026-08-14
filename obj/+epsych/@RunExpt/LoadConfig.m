function LoadConfig(self, cfn)
% LoadConfig — Load a .ecfg file and apply stored functions.
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
    [fn,pn] = uigetfile('*.ecfg','Open Configuration File',pn);
    if isequal(fn,0), return, end
    setpref('ep_RunExpt_Setup','CDir',pn);
    cfn = fullfile(pn,fn);
end

if ~exist(cfn,'file')
    warndlg(sprintf('The file "%s" does not exist.',cfn),'RunExpt','modal')
    self.setStatus(sprintf('Configuration file not found: %s',cfn))
    return
end

vprintf(0,'Loading configuration file: ''%s''\n',cfn)
[~,cfnName,cfnExt] = fileparts(cfn);
self.setStatus(sprintf('Loading configuration "%s%s"...',cfnName,cfnExt))
warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
S = load(cfn,'-mat');
warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

if ~isfield(S,'config')
    errordlg('Invalid Configuration file','PsychConfig','modal')
    self.setStatus(sprintf('"%s%s" is not a valid configuration file.',cfnName,cfnExt))
    return
end

self.ClearConfig
self.CONFIG = S.config;

% Reconstruct Protocol and Subject objects from serialized structs stored in config.
for i = 1:length(self.CONFIG)
    ps = self.CONFIG(i).PROTOCOL;
    if isstruct(ps) && isfield(ps, 'formatVersion')
        P = epsych.Protocol();
        P.fromStruct(ps);
        self.CONFIG(i).PROTOCOL = P;
    end
    % Reconstruct Subject from plain struct (saved by SaveConfig)
    ss = self.CONFIG(i).SUBJECT;
    if isstruct(ss) && isfield(ss, 'Name')
        self.CONFIG(i).SUBJECT = epsych.DefaultSubject(ss);
    end
    if isa(self.CONFIG(i).PROTOCOL, 'epsych.Protocol')
        report = self.CONFIG(i).PROTOCOL.validate();
        errs = report([report.severity] == 2);
        if ~isempty(errs)
            vprintf(0, 1, 'Protocol for subject "%s" has %d validation error(s). Review before starting.', ...
                self.CONFIG(i).SUBJECT.Name, numel(errs));
        end
    end
end

if isfield(S,'funcs')
    self.FUNCS = S.funcs;
    self.SetDefaultFuncs(self.FUNCS)
else
    self.FUNCS = self.GetDefaultFuncs;
end

self.UpdateSubjectList
self.CheckReady
self.CurrentConfigFile = string(cfn);
self.RememberRecentConfig(cfn)

% Posted after CheckReady so the state message it triggers does not overwrite it.
loadedMsg = sprintf('Loaded configuration "%s%s" (%d subject(s)).', ...
    cfnName, cfnExt, numel(self.CONFIG));
% A modal import prompt on every load would be intolerable on a rig that loads
% the same config each morning, so an unrostered subject is only mentioned in
% the status line's next-step half. Guarded because an unreachable shared
% roster must never be able to break loading a configuration.
nextStep = '';
try
    nextStep = localUnrosteredHint(self.CONFIG);
catch ME
    vprintf(2, ME);
end

if ~isempty(nextStep)
    self.setStatus(loadedMsg, nextStep)
elseif self.STATE >= PRGMSTATE.READY
    self.setStatus(loadedMsg,'press Run to record, or Preview to test without saving data.')
else
    self.setStatus(loadedMsg,'add a subject with a protocol to complete the configuration.')
end
end

% -----------------------------------------------------------------------
function hint = localUnrosteredHint(CONFIG)
% Next-step text naming how many of this config's subjects are missing from
% the roster, or '' when they are all present (or there are none).
hint = '';
if isempty(CONFIG) || ~isa(CONFIG(1).SUBJECT, 'epsych.Subject'), return, end

R = epsych.SubjectRoster();
if ~isempty(R.LoadError), return, end

missing = 0;
for i = 1:numel(CONFIG)
    if ~isa(CONFIG(i).SUBJECT, 'epsych.Subject'), continue, end
    if isempty(R.findSubject(CONFIG(i).SUBJECT.Name))
        missing = missing + 1;
    end
end

if missing == 0, return, end

hint = sprintf(['%d subject(s) are not in the roster; import them from ' ...
    'Subjects > Subjects & Projects.'], missing);
end

