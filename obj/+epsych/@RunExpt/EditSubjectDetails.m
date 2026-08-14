function EditSubjectDetails(self, idx)
% EditSubjectDetails(self, idx)
% Edit a session subject's details, writing the change back to the roster too.
%
% Until now the subject-list context menu could only change protocols: fixing a
% typo or recording a new weight meant removing and re-adding the animal. This
% opens the configured subject dialog seeded from the existing record and
% updates CONFIG in place.
%
% The roster copy is updated as well when one matches, so the two do not drift.
% A roster that is unreachable or does not contain this subject is not an
% error — the session edit still stands.
%
% Parameters:
%   idx - row index; uses the selected row when omitted or NaN.
%
% See also: epsych.RunExpt.AddSubject, epsych.SubjectRoster.fromSubject
arguments
    self
    idx double = NaN
end

if self.STATE >= PRGMSTATE.RUNNING, return, end

if isnan(idx)
    selection = self.H.subject_list.Selection;
    if isempty(selection)
        uialert(self.H.figure1, 'Select a subject first.', 'EPsych', 'Icon', 'info');
        return
    end
    idx = selection(1);
end

if isempty(idx) || idx > numel(self.CONFIG), return, end
if ~isa(self.CONFIG(idx).SUBJECT, 'epsych.Subject'), return, end

current = self.CONFIG(idx).SUBJECT;
oldName = current.Name;

% Every box except this subject's own is flagged as in use, and every other name
% is a duplicate — but its own name must remain acceptable or OK would be refused.
boxids   = 1:16;
otherBoxes = [];
curnames = {};
if ~isempty(self.CONFIG(1).SUBJECT)
    taken    = arrayfun(@(c) c.SUBJECT.BoxID, self.CONFIG);
    otherBoxes = setdiff(taken, current.BoxID);
    boxids   = union(setdiff(boxids, taken), current.BoxID);
    allNames = arrayfun(@(c) c.SUBJECT.Name, self.CONFIG, 'uni', 0);
    curnames = allNames(~strcmp(allNames, oldName));
end

S = self.dispatchAddSubjectFcn_(current, boxids, curnames);

if isempty(S) || ~S.isValid(), return, end

if any(S.BoxID == otherBoxes)
    warndlg(sprintf('Box %d is already in use by another subject.', S.BoxID), ...
        'Edit Subject', 'modal')
    return
end

self.CONFIG(idx).SUBJECT = S;

self.UpdateSubjectList
self.CheckReady

localUpdateRoster(S, oldName);

self.setStatus(sprintf('Updated subject "%s" (box %d).', S.Name, S.BoxID));

end

% -----------------------------------------------------------------------
function localUpdateRoster(S, oldName)
% Mirror the edit into the roster when a record matches. Best-effort: an
% unreachable share must not undo an edit the operator already confirmed.
try
    R = epsych.SubjectRoster();
    rec = R.findSubject(oldName);
    if isempty(rec)
        vprintf(2, 'No roster record matches "%s"; the session edit was not mirrored.', ...
            oldName);
        return
    end

    R.updateSubject(rec.SubjectID, S);
catch ME
    vprintf(1, ME);
    vprintf(1, ['The session subject was updated, but the roster copy was not. ' ...
        'Open Subjects & Projects to reconcile it.']);
end
end
