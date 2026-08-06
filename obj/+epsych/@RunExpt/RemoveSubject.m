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

% The placeholder entry that exists before the first subject is added carries
% an empty SUBJECT, so the name is read defensively for the status message.
name = "";
if isa(self.CONFIG(idx).SUBJECT,'epsych.Subject')
    name = string(self.CONFIG(idx).SUBJECT.Name);
end

if isscalar(self.CONFIG)
    self.ClearConfig
else
    self.CONFIG(idx) = [];
end

self.UpdateSubjectList
self.CheckReady

if strlength(name) > 0
    self.setStatus(sprintf('Removed subject "%s".',name))
end
