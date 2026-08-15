function p = aliasBehaviorGUI_(p)
% p = epsych.SubjectRoster.aliasBehaviorGUI_(p)
% Mirror a project's BehaviorGUI field onto its former name, BoxGUI.
%
% The field was renamed when "box GUI" was renamed "behavior GUI": the GUI is
% launched once per session against RUNTIME, never once per box, so the old name
% borrowed BoxID's word for something else entirely.
%
% Mirroring runs in BOTH directions, on read and on write, because a roster is a
% shared file: one rig may be a release behind. Whichever name a record arrives
% with, both are present by the time normalize_ trims the record to the field set
% this build knows, and both are on disk for whoever reads it next.
%
% Remove alongside FORMAT_VERSION 2, once no rig writes BoxGUI.
%
% Parameters:
%   p - project record array, or anything a malformed file yielded.
%
% Returns:
%   p - the same array with BoxGUI and BehaviorGUI agreeing, when either exists.
%
% See also: epsych.SubjectRoster.normalize_, epsych.SubjectRoster.reload
arguments
    p
end

if ~isstruct(p) || isempty(p), return, end

hasNew = isfield(p, 'BehaviorGUI');
hasOld = isfield(p, 'BoxGUI');

if hasNew == hasOld, return, end     % both or neither: nothing to carry

if hasOld
    from = 'BoxGUI';   to = 'BehaviorGUI';
else
    from = 'BehaviorGUI'; to = 'BoxGUI';
end

% Assigned one at a time rather than with a comma-list: a 0x0 struct array with
% fields would make the deal form throw, and a roster read is never allowed to.
for i = 1:numel(p)
    p(i).(to) = p(i).(from);
end
