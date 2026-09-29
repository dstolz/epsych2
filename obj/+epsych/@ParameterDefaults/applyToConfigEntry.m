function [C, report] = applyToConfigEntry(C, options)
% [C, report] = epsych.ParameterDefaults.applyToConfigEntry(C)
% [C, report] = epsych.ParameterDefaults.applyToConfigEntry(C, Roster=R)
% Apply one epsych.RunExpt CONFIG entry's subject defaults to its protocol --
% what Run and Preview do for every subject before compiling.
%
% The entry's ROSTER field says where the subject came from (rosterLink) and
% carries the apply state between runs. An entry with no ROSTER field -- a
% subject added by hand, a scripted CONFIG -- has no defaults, and nothing is
% done to it.
%
% Parameters:
%   C - scalar CONFIG struct: PROTOCOL, SUBJECT and optionally ROSTER.
%
% Options:
%   Roster - an open epsych.SubjectRoster to reuse; see lookup.
%
% Returns:
%   C      - the entry, with ROSTER.State updated.
%   report - apply's report plus Source and Message (see lookup). The caller
%            recompiles the protocol when report.Changed.
%
% See also: epsych.ParameterDefaults.apply, epsych.ParameterDefaults.lookup,
%   epsych.RunExpt.ExptDispatch
arguments
    C (1,1) struct
    options.Roster = []
end

link = [];
if isfield(C, 'ROSTER') && isstruct(C.ROSTER) && isscalar(C.ROSTER)
    link = C.ROSTER;
end

[D, source, message] = epsych.ParameterDefaults.lookup(link, Roster = options.Roster);

state = [];
if ~isempty(link) && isfield(link, 'State')
    state = link.State;
end

if isempty(D) && (isempty(state) || isempty(state.Originals))
    % Nothing to apply and nothing to undo: leave the entry untouched.
    report = epsych.ParameterDefaults.emptyReport();
elseif ~isa(C.PROTOCOL, 'epsych.Protocol') || ~isscalar(C.PROTOCOL) || ~isvalid(C.PROTOCOL)
    % ExptDispatch refuses this entry itself, with a better message.
    report = epsych.ParameterDefaults.emptyReport();
else
    [state, report] = epsych.ParameterDefaults.apply(C.PROTOCOL, D, state);
    C.ROSTER.State = state;
end

report.Source = source;
report.Message = message;
end
