function buildRuntime_(obj)
% buildRuntime_(obj)
% Construct the offline runtime the behavior GUI will be attached to.
%
% A real epsych.Runtime with a real epsych.EventHub, not a stand-in. That is
% what lets every component work unmodified -- and it is required rather than
% merely tidy for psychophysics.Detection, which is not a psychophysics.Psych
% subclass and has no struct-source path: it only knows how to listen to
% RUNTIME.EVENTS.
%
% Follows the same four lines that epsych.SelfTest's behavior-GUI check and
% examples/detection_task/run_detection_session.m already use, with two
% differences: ReviewMode is set before TRIALS (so the assignment does not
% dispatch a trial), and the interfaces are hw.Replay rather than hw.Software
% (so a parameter read reports the trial being reviewed rather than the
% protocol's design-time value).
%
% The interfaces are left in Standby. The move to Idle happens after the window
% is built, because that transition is what disables the controls.
%
% See also: hw.Replay.fromProtocolStruct, epsych.Runtime.set.TRIALS

arguments
    obj
end

rt = epsych.Runtime;
rt.ReviewMode = true;

% A review is not a run: nothing may be recorded from it, and any paradigm code
% that checks isTest already knows to keep its hands off.
rt.isTest = true;

rt.EVENTS = epsych.EventHub;
rt.StartTime = obj.Snapshot.StartTime;
rt.DataFile = string(obj.DataFile);

% --- The parameter tree ---------------------------------------------------
obj.Interfaces = hw.Replay.empty(1,0);
if isfield(obj.Snapshot, 'Protocol') && isstruct(obj.Snapshot.Protocol) ...
        && ~isempty(fieldnames(obj.Snapshot.Protocol))
    obj.Interfaces = hw.Replay.fromProtocolStruct(obj.Snapshot.Protocol, obj.Data);
end

if isempty(obj.Interfaces)
    vprintf(0, ['epsych.ReviewSession: this session carries no protocol, so it opens ' ...
        'without parameter controls. Pass Protocol="...eprot" to supply one.'])
else
    % Standby rather than Idle: gui.Parameter_Control disables on a mode
    % PostSet, and mode is AbortSet, so a control built while the interface is
    % already Idle would never see the transition and would stay enabled.
    for p = obj.Interfaces(:).'
        p.mode = hw.DeviceState.Standby;
    end
    rt.Interfaces = obj.Interfaces;
end

% --- The TRIALS shape -----------------------------------------------------
% Everything a live TRIALS(i) carries except the three fields seek() rewrites
% per trial (DATA, TrialIndex, NextTrialID). Kept in one place so seek stays
% small and so the struct a component receives has the shape it expects.
T = struct();
T.Subject     = obj.Snapshot.Subject;
T.BoxID       = obj.Snapshot.BoxID;
T.DataFilename = obj.Snapshot.DataFilename;
T.SessionInfo = obj.Snapshot;

% Never true in a review, but present because a paradigm hook may read them.
T.FORCE_TRIAL         = false;
T.RECOMPILE_REQUESTED = false;
T.protocol            = epsych.Protocol.empty;
T.selector            = [];

if isempty(T.Subject)
    % epsych.TrialsData reads Subject and BoxID off the struct, so they cannot
    % be absent. A file that never recorded them still has to review.
    T.Subject = localPlaceholderSubject(obj.DataFile);
end
if isempty(T.BoxID)
    T.BoxID = 0;
end

[T.parameters, T.trials, T.writeparams, T.writeParamIdx] = ...
    localTrialColumns(obj.Snapshot, obj.Interfaces);

T.DATA        = struct.empty(1,0);
T.TrialIndex  = 0;
T.NextTrialID = [];

obj.TrialsTemplate_ = T;

rt.TRIALS = T;

obj.RUNTIME = rt;

end




function [parameters, trials, writeparams, writeParamIdx] = localTrialColumns(snapshot, interfaces)
% [parameters, trials, writeparams, writeParamIdx] = localTrialColumns(snapshot, interfaces)
%
% The compiled trial table and the column map that names it, re-linked to the
% replay parameters. epsych.Runtime.compiledTrialColumns guarantees that
% parameters, trials and writeparams are column-aligned 1:1, and consumers
% (gui.NextTrial above all) index a column by name and then read
% parameters(i).Name/.Unit for its label -- so the handles must line up with
% the columns or a label ends up over the wrong number.
%
% They are re-linked by validName rather than by position, because the
% snapshot stores the parameters grouped by interface and module while the
% trial table stores them in compile order. Any name that does not resolve
% costs the whole table: a partial alignment is worse than none, since it
% mislabels silently while an absent table simply shows nothing.

parameters    = hw.Parameter.empty(1,0);
trials        = {};
writeparams   = {};
writeParamIdx = struct();

if ~isfield(snapshot, 'WriteParams') || isempty(snapshot.WriteParams)
    return
end

names = cellstr(snapshot.WriteParams);

available = hw.Parameter.empty(1,0);
for p = interfaces(:).'
    available = [available, p.all_parameters(Access='All', ...
        includeInvisible=true, includeTriggers=true)];
end

if isempty(available)
    return
end

availableNames = arrayfun(@(q) string(q.validName), available);

resolved = hw.Parameter.empty(1,0);
for k = 1:numel(names)
    j = find(availableNames == string(names{k}), 1);
    if isempty(j)
        vprintf(1, ['epsych.ReviewSession: trial column "%s" has no parameter in the ' ...
            'saved protocol; the upcoming-trial display will be empty'], names{k})
        return
    end
    resolved(end+1) = available(j);
end

parameters    = resolved;
trials        = snapshot.TrialTable;
writeparams   = names;
writeParamIdx = snapshot.WriteParamIdx;

end




function S = localPlaceholderSubject(datafile)
% S = localPlaceholderSubject(datafile)
%
% A stand-in for a file that recorded no subject. Named after the file, since
% that is the only identity such a file has, and it is what a display will
% show in its title.

[~, fn] = fileparts(datafile);
S = struct('Name', fn, 'BoxID', 0);

end
