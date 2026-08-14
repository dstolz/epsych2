function S = toSubject(self, subjectId, options)
% S = toSubject(self, subjectId)
% S = toSubject(self, subjectId, BoxID=4)
% Materialize a roster record as an epsych.Subject for a session.
%
% This is the seam that keeps BoxID out of the roster. A box is a property of
% a session, not of an animal, so roster records carry no BoxID field at all --
% it is supplied here, at the one moment it is actually known. That is why
% epsych.Subject needs no subclassing and its isValid() contract (BoxID >= 1)
% is never violated by a roster record.
%
% Parameters:
%   subjectId - SubjectID or Name.
%
% Options:
%   BoxID - box to assign (default 1)
%
% Returns:
%   S - epsych.DefaultSubject.
%
% Throws:
%   epsych:SubjectRoster:NoSuchSubject
%
% See also: epsych.SubjectRoster.fromSubject, epsych.SubjectRoster.assignToSession
arguments
    self
    subjectId (1,:) char
    options.BoxID (1,1) double {mustBePositive, mustBeInteger} = 1
end

rec = self.findSubject(subjectId);
if isempty(rec)
    error('epsych:SubjectRoster:NoSuchSubject', 'No subject matches "%s".', subjectId);
end

S = epsych.DefaultSubject(struct( ...
    'BoxID',   options.BoxID, ...
    'Name',    rec.Name, ...
    'Sex',     rec.Sex, ...
    'Species', rec.Species, ...
    'Weight',  rec.Weight, ...
    'Notes',   rec.Notes));
