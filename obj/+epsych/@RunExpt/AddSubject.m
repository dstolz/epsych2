function AddSubject(self, S)
% AddSubject — Create a new subject entry and assign a protocol.
% Inputs
%   S (struct) — Optional pre-filled subject fields; dialog if empty.
% Behavior
%   Invokes FUNCS.AddSubjectFcn(S, boxids), enforces unique names,
%   prompts for a protocol file, appends to CONFIG, and updates UI.
arguments
    self (1,1) ep_RunExpt2
    S struct = struct()
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

boxids = 1:16;
curboxids = [];
curnames = {[]};
if ~isempty(self.CONFIG) && ~isempty(self.CONFIG(1).SUBJECT)
    curboxids = arrayfun(@(c) c.SUBJECT.BoxID, self.CONFIG);
    curnames = arrayfun(@(c) c.SUBJECT.Name, self.CONFIG, 'uni', 0);
    boxids = setdiff(boxids,curboxids);
end

if ~isfield(self.FUNCS,'AddSubjectFcn') || isempty(self.FUNCS.AddSubjectFcn)
    self.FUNCS.AddSubjectFcn = getpref('ep_RunExpt','CONFIG_AddSubjectFcn','ep_AddSubject');
end

ontop = self.AlwaysOnTop(false);
S = feval(self.FUNCS.AddSubjectFcn,S,boxids);
self.AlwaysOnTop(ontop);

if isempty(S) || ~isfield(S,'Name') || strlength(string(S.Name))==0, return, end

if ~isempty(curnames{1}) && ismember(S.Name, curnames)
    warndlg(sprintf('The subject name "%s" is already in use.',S.Name),'Add Subject','modal')
    return
end

pn = getpref('ep_RunExpt_Setup','PDir',cd);
if ~exist(pn,'dir'), pn = cd; end
[fn,pn] = uigetfile('*.prot','Locate Protocol',pn);
if isequal(fn,0), return, end
setpref('ep_RunExpt_Setup','PDir',pn)
pfn = fullfile(pn,fn);

if ~exist(pfn,'file')
    warndlg(sprintf('The file "%s" does not exist.',pfn),'Psych Config','modal')
    return
end

if ~isfield(self.CONFIG, 'protocol_fn') || isempty(self.CONFIG(1).protocol_fn)
    self.CONFIG(1).protocol_fn = pfn;
else
    self.CONFIG(end+1).protocol_fn = pfn;
end

self.CONFIG(end).SUBJECT = S;
self.UpdateSubjectList
self.CheckReady
