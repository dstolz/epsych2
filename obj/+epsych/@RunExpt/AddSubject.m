function AddSubject(self, S)
% AddSubject(self)
% AddSubject(self, S)
% Create a new subject entry and assign a protocol.
%  S - (optional) pre-filled subject struct; opens dialog if omitted
arguments
    self
    S struct = struct()
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

% Collect existing names and occupied box IDs to prevent conflicts
boxids   = 1:16;
curnames = {};
if ~isempty(self.CONFIG(1).SUBJECT)
    boxids   = setdiff(boxids, arrayfun(@(c) c.SUBJECT.BoxID, self.CONFIG));
    curnames = arrayfun(@(c) c.SUBJECT.Name, self.CONFIG, 'uni', 0);
end

if ~isfield(self.FUNCS,'AddSubjectFcn') || isempty(self.FUNCS.AddSubjectFcn)
    self.FUNCS.AddSubjectFcn = getpref('ep_RunExpt','CONFIG_AddSubjectFcn','ep_AddSubject');
end

ontop = self.AlwaysOnTop(false);
S = feval(self.FUNCS.AddSubjectFcn, S, boxids);
self.AlwaysOnTop(ontop);

if isempty(S) || ~isfield(S,'Name') || strlength(string(S.Name)) == 0, return, end

if ~isempty(curnames) && ismember(S.Name, curnames)
    warndlg(sprintf('The subject name "%s" is already in use.', S.Name), 'Add Subject', 'modal')
    return
end

pn = getpref('ep_RunExpt_Setup','PDir',cd);
if ~exist(pn,'dir'), pn = cd; end
[fn, pn] = uigetfile({'*.eprot;*.prot','Protocol Files (*.eprot, *.prot)'; ...
    '*.*','All Files (*.*)'},'Locate Protocol', pn);
if isequal(fn, 0), return, end
setpref('ep_RunExpt_Setup','PDir', pn)
pfn = fullfile(pn, fn);

protocol = epsych.Protocol.load(pfn);

% Populate the first slot when empty, otherwise append a new entry
if isempty(self.CONFIG(1).protocol_fn)
    idx = 1;
else
    idx = numel(self.CONFIG) + 1;
end
self.CONFIG(idx).protocol_fn = pfn;
self.CONFIG(idx).PROTOCOL    = protocol;
self.CONFIG(idx).SUBJECT     = S;

self.UpdateSubjectList
self.CheckReady
