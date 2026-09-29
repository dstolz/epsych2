function D = parameterDefaults(self, subjectId, projectId)
% D = parameterDefaults(self, subjectId, projectId)
% The parameter defaults one membership carries.
%
% A subject's defaults belong to its membership, like its protocol memory and
% session settings: parameter names come from the project's protocol, so the
% same animal in two studies keeps two sets. Empty when there are none, when
% the subject is not a member, or when either key matches nothing -- a reader
% asking "what does this subject override" gets "nothing", not an error.
%
% Parameters:
%   subjectId - SubjectID or Name.
%   projectId - ProjectID or Name.
%
% Returns:
%   D - (1,:) record array; see epsych.ParameterDefaults.blank.
%
% See also: epsych.SubjectRoster.setParameterDefaults, epsych.ParameterDefaults
arguments
    self
    subjectId (1,:) char
    projectId (1,:) char
end

D = epsych.ParameterDefaults.empty();

s = self.findSubject(subjectId);
p = self.findProject(projectId);
if isempty(s) || isempty(p), return, end

m = self.findMembership(s.SubjectID, p.ProjectID);
if isempty(m), return, end

D = epsych.ParameterDefaults.normalize(m.ParameterDefaults);
end
