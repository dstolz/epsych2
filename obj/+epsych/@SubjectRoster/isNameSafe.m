function [tf, why] = isNameSafe(name)
% [tf, why] = epsych.SubjectRoster.isNameSafe(name)
% True when name can be used as a filename component.
%
% A subject's Name becomes a data folder and a filename (ExptDispatch builds
% <DataPath>/<Name>/), so an illegal character would only surface at the moment
% a session tries to save. This mirrors epsych.SelfTest check D3 exactly, so
% the roster rejects up front what the self-test would later flag.
%
% Parameters:
%   name - candidate subject or project name.
%
% Returns:
%   tf  - logical scalar.
%   why - char explanation when tf is false, '' otherwise.
%
% See also: epsych.SelfTest.checkConfig, epsych.SubjectRoster.addSubject
arguments
    name (1,:) char
end

tf  = false;
why = '';

if isempty(strtrim(name))
    why = 'The name is empty.';
    return
end

illegal = '<>:"/\|?*';
bad = intersect(name, illegal);
if ~isempty(bad)
    why = sprintf('The name contains %s, which cannot be used in a filename.', ...
        strjoin(cellstr(bad'), ' '));
    return
end

if name(end) == ' ' || name(end) == '.'
    why = 'The name ends with a space or period, which Windows strips.';
    return
end

tf = true;
