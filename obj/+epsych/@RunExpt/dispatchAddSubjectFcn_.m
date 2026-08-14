function S = dispatchAddSubjectFcn_(self, seed, boxids, reservedNames)
% S = dispatchAddSubjectFcn_(self, seed, boxids, reservedNames)
% Open the configured subject dialog and return an epsych.Subject, or [].
%
% The single place that knows how FUNCS.AddSubjectFcn is called. AddSubject,
% the subject-list "Edit Subject Details..." action, and the Subjects &
% Projects manager's "New Subject..." all route through here, so a lab that
% points AddSubjectFcn at its own dialog keeps working everywhere rather than
% only in the one path that happened to be updated.
%
% Two calling conventions are supported, as they always have been: the modern
% epsych.DefaultSubject.open (which takes ReservedNames and returns an object)
% and the legacy S = fcn(S, boxids) form returning a plain struct.
%
% Parameters:
%   seed          - epsych.Subject or struct to pre-fill the dialog with.
%   boxids        - vector of selectable box IDs.
%   reservedNames - cellstr of names the dialog must reject as duplicates.
%
% Returns:
%   S - epsych.Subject, or [] when the operator cancelled or the result was
%       unusable.
%
% See also: epsych.RunExpt.AddSubject, epsych.RunExpt.DefineAddSubject
arguments
    self
    seed = struct()
    boxids double = 1:16
    reservedNames cell = {}
end

S = [];

if ~isfield(self.FUNCS, 'AddSubjectFcn') || isempty(self.FUNCS.AddSubjectFcn)
    self.FUNCS.AddSubjectFcn = getpref('ep_RunExpt', 'CONFIG_AddSubjectFcn', ...
        'epsych.DefaultSubject.open');
end

fcn = self.FUNCS.AddSubjectFcn;

ontop = self.AlwaysOnTop(false);
cleanupOnTop = onCleanup(@() self.AlwaysOnTop(ontop));

if isequal(fcn, 'epsych.DefaultSubject.open')
    % The built-in dialog validates duplicates live so entered data isn't lost
    result = epsych.DefaultSubject.open(seed, boxids, 'ReservedNames', reservedNames);
else
    % Legacy path — seed converted for the backward-compatible signature
    if isa(seed, 'epsych.Subject')
        seed = seed.toStruct();
    elseif ~isstruct(seed)
        seed = struct();
    end
    result = feval(fcn, seed, boxids);
end

if isempty(result), return, end

if isa(result, 'epsych.Subject')
    S = result;
elseif isstruct(result)
    S = epsych.DefaultSubject(result);
end
