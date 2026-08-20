function AddSubject(self, S)
% AddSubject(self)
% AddSubject(self, S)
% Create a new subject entry and assign a protocol.
%  S - (optional) pre-filled epsych.Subject or struct; opens dialog if omitted
%
% No toolbar button or menu routes here any more — the Subjects & Projects
% manager replaced that path. This remains the programmatic API and the one
% place that knows how to dispatch FUNCS.AddSubjectFcn, which the manager's
% "New Subject..." reuses so a lab's custom dialog keeps working.
%
% See also: epsych.RunExpt.OpenSubjectManager, epsych.SubjectRoster.assignToSession
arguments
    self
    S = struct()
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

% Collect existing names and free box IDs. The dialog marks the occupied boxes
% rather than hiding them, so the answer is checked here instead of being
% prevented there.
boxids   = 1:16;
curboxes = [];
curnames = {};
if ~isempty(self.CONFIG(1).SUBJECT)
    curboxes = arrayfun(@(c) c.SUBJECT.BoxID, self.CONFIG);
    boxids   = setdiff(boxids, curboxes);
    curnames = arrayfun(@(c) c.SUBJECT.Name, self.CONFIG, 'uni', 0);
end

S = self.dispatchAddSubjectFcn_(S, boxids, curnames);

if isempty(S) || ~S.isValid(), return, end

if ~isempty(curnames) && any(strcmpi(S.Name, curnames))
    warndlg(sprintf('The subject name "%s" is already in use.', S.Name), 'Add Subject', 'modal')
    return
end

if any(S.BoxID == curboxes)
    warndlg(sprintf('Box %d is already in use by another subject.', S.BoxID), ...
        'Add Subject', 'modal')
    return
end

pn = getpref('ep_RunExpt_Setup','PDir',cd);
if ~exist(pn,'dir'), pn = cd; end
[fn, pn] = uigetfile({'*.eprot','Protocol Files (*.eprot)'; ...
    '*.*','All Files (*.*)'},'Locate Protocol', pn);
if isequal(fn, 0), return, end
setpref('ep_RunExpt_Setup','PDir', pn)
pfn = fullfile(pn, fn);

protocol = epsych.Protocol.load(pfn);

self.appendSubjectToConfig_(S, pfn, protocol);

self.UpdateSubjectList
self.CheckReady

self.setStatus(sprintf('Added subject "%s" (box %d) with protocol "%s".', ...
    S.Name, S.BoxID, fn))
