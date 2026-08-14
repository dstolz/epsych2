function tf = save(self)
% tf = save(self)
% Write the current in-memory roster to disk.
%
% Rarely needed: every CRUD method already persists through mutate_. This
% exists for the case where a caller has built a roster up programmatically and
% wants it committed, and for tests.
%
% Returns:
%   tf - true on success.
%
% See also: epsych.SubjectRoster.mutate_, epsych.SubjectRoster.reload
arguments
    self
end

tf = self.mutate_(@(~) []);
