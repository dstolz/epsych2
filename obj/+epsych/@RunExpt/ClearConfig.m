function ClearConfig(self)
% ClearConfig(self)
% Reset CONFIG to empty defaults and update program state if not running.
%
% CONFIG keeps one placeholder element rather than becoming empty, because
% epsych.RunExpt.appendSubjectToConfig_ reads CONFIG(1) to decide whether the
% first subject fills slot 1 or lands behind a blank row.
%
% Scoped to the class and epsych.SubjectRoster: a batch commit asked to replace
% the session's subject list clears it here, so the emptying and the refilling
% follow the same rules as every other write to CONFIG.
%
% See also: epsych.RunExpt.RemoveSubject, epsych.SubjectRoster.assignToSession
arguments
    self
end

self.CONFIG = struct('SUBJECT',[],'PROTOCOL',[],'RUNTIME',[],'protocol_fn',[]);
if self.STATE >= PRGMSTATE.RUNNING, return, end
self.STATE = PRGMSTATE.NOCONFIG;
if isfield(self.H,'subject_list') && isgraphics(self.H.subject_list)
    set(self.H.subject_list,'Data',[])
end
self.CheckReady
