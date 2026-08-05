function S = ep_AddSubject(S, boxids)
% S = ep_AddSubject(S, boxids)
%
% Legacy-compatible wrapper around the modern subject entry dialog
% (epsych.DefaultSubject.open). Kept so saved configs and custom code that
% reference 'ep_AddSubject' by name continue to work; the GUIDE
% implementation it replaced is gone.
%
% Optionally input a structure S with fields already populated.
%
% Output/Input (optional) structure:
%   S.BoxID
%   S.Name
%   S.Sex
%   S.Species
%   S.Weight
%   S.Notes
%
% A second optional input specifies the available Box IDs:
%   S = ep_AddSubject([], [3 4 6]);
%
% Returns [] if the dialog is cancelled.
%
% * Any custom AddSubject function must accept a structure as input and
% return one as output with at least these fields:
%   .BoxID  ... Scalar index of the apparatus the subject is running in
%               (set to 1 if only one apparatus is in use).
%   .Name   ... Some identifier for the subject.
% Any other fields are carried through to the data output.
%
% See also: epsych.DefaultSubject, epsych.Subject
%
% Daniel.Stolzberg@gmail.com

arguments
    S = []
    boxids (1,:) {mustBeNumeric} = 1:16
end

obj = epsych.DefaultSubject.open(S, boxids);

if isempty(obj)
    S = [];
else
    S = obj.toStruct();
end
