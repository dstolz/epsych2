function AddSubject(self, S)
% AddSubject(self)
% AddSubject(self, S)
% Create a new subject entry and assign a protocol.
%  S - (optional) pre-filled epsych.Subject or struct; opens dialog if omitted
arguments
    self
    S = struct()
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
    self.FUNCS.AddSubjectFcn = getpref('ep_RunExpt','CONFIG_AddSubjectFcn','epsych.DefaultSubject.open');
end

ontop = self.AlwaysOnTop(false);

% Dispatch: prefer the new epsych.Subject-based open() path; fall back to
% legacy function handles that return a plain struct.
fcn = self.FUNCS.AddSubjectFcn;
if isequal(fcn, 'epsych.DefaultSubject.open')
    % The built-in dialog validates duplicates live so entered data isn't lost
    result = epsych.DefaultSubject.open(S, boxids, 'ReservedNames', curnames);
else
    % Legacy path — seed struct converted for backward-compatible signature
    if isa(S, 'epsych.Subject')
        seed = S.toStruct();
    elseif isstruct(S)
        seed = S;
    else
        seed = struct();
    end
    result = feval(fcn, seed, boxids);
end

self.AlwaysOnTop(ontop);

% Normalise result to epsych.Subject
if isempty(result), return, end
if isa(result, 'epsych.Subject')
    S = result;
elseif isstruct(result)
    S = epsych.DefaultSubject(result);
else
    return
end

if ~S.isValid(), return, end

if ~isempty(curnames) && any(strcmpi(S.Name, curnames))
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

self.setStatus(sprintf('Added subject "%s" (box %d) with protocol "%s".', ...
    S.Name, S.BoxID, fn))
