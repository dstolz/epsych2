function [state, report] = apply(protocol, D, state)
% [state, report] = epsych.ParameterDefaults.apply(protocol, D)
% [state, report] = epsych.ParameterDefaults.apply(protocol, D, state)
% Put a subject's parameter defaults onto its protocol, undoing the last Run's.
%
% Two steps, in this order:
%   1. RESTORE. Everything STATE says an earlier call replaced on this same
%      protocol object is put back. A default removed since then therefore
%      returns the protocol's value, and one that is still there is applied to
%      the protocol's value rather than on top of the last run's.
%   2. APPLY. Each record in D is resolved to its parameter, checked, and its
%      bounds then its levels are written: Min/Max, then Values, then Value
%      when there is exactly one level. What it replaced is captured first.
%
% A record that names no parameter, or cannot be applied as it stands, is
% skipped and listed in report.Skipped -- never thrown -- so a protocol revised
% since the default was set still runs. Nothing here compiles: the caller
% recompiles when report.Changed, because Values are what the trial table is
% built from.
%
% Writing Value goes through hw.Parameter.set.Value, so on a connected backend
% it reaches the hardware and runs the parameter's update callbacks, exactly as
% a phase load does (epsych.Runtime.readParameters). A write that throws is
% logged and reported, and the default's Values still stand.
%
% Parameters:
%   protocol - epsych.Protocol to modify in place.
%   D        - record array (epsych.ParameterDefaults.blank shape); may be empty.
%   state    - what the previous call returned for this protocol, or omitted.
%              A state recorded against a different protocol object is ignored:
%              a protocol that was reloaded is pristine.
%
% Returns:
%   state  - pass back to the next call (keep it with the protocol).
%   report - struct:
%              Applied  - (1,:) struct Key, Label, Text
%              Skipped  - (1,:) struct Key, Label, Reason
%              Restored - how many parameters were put back
%              Changed  - true when any parameter was restored or applied
%
% See also: epsych.ParameterDefaults.check, epsych.ParameterDefaults.applyToConfigEntry,
%   epsych.RunExpt.ExptDispatch
arguments
    protocol (1,1) epsych.Protocol
    D = epsych.ParameterDefaults.empty()
    state = []
end

report = epsych.ParameterDefaults.emptyReport();

if isempty(state) || ~isstruct(state) || ~isfield(state, 'Originals')
    state = epsych.ParameterDefaults.emptyState();
end

% --- 1. restore ----------------------------------------------------------
if localSameProtocol(state.Protocol, protocol)
    % Reverse order, so a parameter captured twice (cannot happen through this
    % function, but a hand-built state could) ends on its earliest value.
    O = state.Originals;
    for k = numel(O):-1:1
        localRestore(O(k));
    end
    report.Restored = numel(O);
end
state = epsych.ParameterDefaults.emptyState();
state.Protocol = protocol;

% --- 2. apply ------------------------------------------------------------
D = epsych.ParameterDefaults.normalize(D);
touched = hw.Parameter.empty(1, 0);

for i = 1:numel(D)
    d = D(i);
    k = epsych.ParameterDefaults.key(d);
    lbl = epsych.ParameterDefaults.label(d);

    P = epsych.ParameterDefaults.resolve(protocol, d);
    if isempty(P)
        report.Skipped(end+1) = struct('Key', k, 'Label', lbl, ...
            'Reason', sprintf('%s is not in this protocol', lbl));
        continue
    end
    if any(touched == P)
        report.Skipped(end+1) = struct('Key', k, 'Label', lbl, ...
            'Reason', sprintf('%s already has a default', lbl));
        continue
    end

    [ok, why] = epsych.ParameterDefaults.check(d, P);
    if ~ok
        report.Skipped(end+1) = struct('Key', k, 'Label', lbl, 'Reason', why);
        continue
    end

    % Value is seated only for a single level; a list is the dispatcher's to
    % write trial by trial. Restoring re-seats only what was seated.
    seat = ~isempty(d.Value) ...
        && isscalar(epsych.ParameterDefaults.levels(d.Value, P.Type));
    state.Originals(end+1) = struct('Param', P, 'Values', {P.Values}, ...
        'Min', P.Min, 'Max', P.Max, 'SeatValue', seat && isscalar(P.Values));
    touched(end+1) = P;

    % Bounds first: set.Value clamps into [Min Max].
    if ~isnan(d.Min), P.Min = d.Min; end
    if ~isnan(d.Max), P.Max = d.Max; end

    if ~isempty(d.Value)
        L = epsych.ParameterDefaults.levels(d.Value, P.Type);
        P.Values = L;
        if seat
            localSeat(P, L{1}, lbl);
        end
    end

    report.Applied(end+1) = struct('Key', k, 'Label', lbl, ...
        'Text', epsych.ParameterDefaults.describe(d, P.Unit));
end

report.Changed = report.Restored > 0 || ~isempty(report.Applied);
end

% -----------------------------------------------------------------------
function tf = localSameProtocol(a, b)
% Handle identity; an invalid or absent protocol never matches.
tf = ~isempty(a) && isa(a, 'epsych.Protocol') && isvalid(a) && a == b;
end

% -----------------------------------------------------------------------
function localRestore(o)
% Put one parameter back the way apply found it. Bounds before the value for
% the same reason apply sets them first.
P = o.Param;
if isempty(P) || ~isvalid(P), return, end
P.Min = o.Min;
P.Max = o.Max;
P.Values = o.Values;
if o.SeatValue && ~isempty(o.Values)
    localSeat(P, o.Values{1}, P.Name);
end
end

% -----------------------------------------------------------------------
function localSeat(P, v, lbl)
% Write the single level to Value. A backend that refuses is logged, not
% rethrown: Values already hold the level, so the trial table still carries it.
try
    P.Value = v;
catch ME
    vprintf(0, 1, 'Subject default for %s set its design value but could not be written: %s', ...
        lbl, ME.message);
end
end
