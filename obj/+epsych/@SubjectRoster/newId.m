function id = newId(prefix)
% id = epsych.SubjectRoster.newId(prefix)
% Mint a stable record identifier, e.g. 'S_20260814T143012_7f3a9c'.
%
% Timestamp plus six random hex characters: collision-free at lab scale, sorts
% chronologically, and stays readable in a debug dump — which a bare UUID does
% not. java.util.UUID is avoided because Java is being removed from MATLAB, and
% matlab.lang.internal.uuid because it is unsupported internal API.
%
% Parameters:
%   prefix - short record-kind tag, 'S' for subjects, 'P' for projects.
%
% Returns:
%   id - char identifier.
%
% See also: epsych.SubjectRoster.addSubject, epsych.SubjectRoster.addProject
arguments
    prefix (1,:) char
end

stamp = char(datetime('now', Format='yyyyMMdd''T''HHmmss'));
suffix = lower(dec2hex(randi([0, 16^6 - 1]), 6));

id = sprintf('%s_%s_%s', prefix, stamp, suffix);
