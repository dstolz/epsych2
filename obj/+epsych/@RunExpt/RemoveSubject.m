function RemoveSubject(self, idx)
% RemoveSubject — Delete a subject from CONFIG.
% Inputs
%   idx (double) — Optional row index; uses selected table row if NaN.
% Behavior
%   Removes the specified subject (or clears CONFIG if singleton)
%   then updates the table and readiness state.
arguments
    self
    idx double = NaN
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

if isnan(idx)
    idx = self.H.subject_list.Selection(1);
end
if isempty(idx) || isempty(self.CONFIG), return, end

if isscalar(self.CONFIG)
    self.ClearConfig
else
    self.CONFIG(idx) = [];
end

self.UpdateSubjectList
self.CheckReady
