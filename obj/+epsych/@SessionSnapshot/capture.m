function S = capture(RUNTIME, subjectIdx, trialsStruct)
% S = epsych.SessionSnapshot.capture(RUNTIME, subjectIdx)
% Build the snapshot for one subject of a live runtime.
%
% Everything returned is plain data. The protocol is serialized through
% epsych.Protocol.toStruct -- which already carries interfaces, modules and
% every hw.Parameter's metadata -- rather than stored as a handle, because a
% saved handle would drag the whole backend class into the file and would not
% survive a load on a machine without that hardware's toolbox.
%
% Called once per subject by ep_TimerFcn_Start, at session start rather than at
% save time, for two reasons: the crash-recovery file is written there, so a
% crashed session ends up just as reviewable as a saved one; and the protocol
% at the start is the one the trial table was compiled from. A mid-session
% recompile is a deliberate exception -- see the note on TrialTable below.
%
% Parameters:
%   RUNTIME      - epsych.Runtime for the session.
%   subjectIdx   - Index into RUNTIME.TRIALS.
%   trialsStruct - One TRIALS element to describe, when the caller holds it but
%                  has not assigned it to the runtime yet. ep_TimerFcn_Start
%                  needs this: it builds the whole TRIALS array locally and
%                  assigns it in one go at the end, because assigning it is
%                  what dispatches the first trial.
%
% Returns:
%   S - Snapshot struct. Fields absent from a session are left empty rather
%       than omitted, so a reader can test them without isfield.
%
% See also: epsych.SessionSnapshot.fromInfo, epsych.ReviewSession

arguments
    RUNTIME (1,1) epsych.Runtime
    subjectIdx (1,1) double {mustBeInteger,mustBePositive} = 1
    trialsStruct = []
end

if isempty(trialsStruct)
    T = RUNTIME.TRIALS(subjectIdx);
else
    T = trialsStruct;
end

S = struct();
S.FormatVersion = epsych.SessionSnapshot.FORMAT_VERSION;

% Provenance. EPsychMeta is nested rather than flattened so that the whole
% snapshot can grow without colliding with a field name EPsychInfo adds later.
try
    S.EPsychMeta = EPsychInfo().meta;
catch ME
    vprintf(2, 'epsych.SessionSnapshot: no repository metadata available (%s)', ME.message)
    S.EPsychMeta = struct();
end

S.Subject      = T.Subject;
S.BoxID        = T.BoxID;
S.isTest       = RUNTIME.isTest;
S.DataFilename = char(string(T.DataFilename));

% RUNTIME.StartTime is stamped by set.TRIALS, which has not run yet when
% ep_TimerFcn_Start captures this -- assigning TRIALS is the last thing it
% does. Stamp it here in that case, so the snapshot always carries a real
% start time rather than NaT.
S.StartTime = RUNTIME.StartTime;
if isempty(S.StartTime) || all(isnat(S.StartTime))
    S.StartTime = datetime('now');
end

% The class name only. The selector object holds a runtime back-reference and
% its own adaptive state; serializing it would make the file depend on the
% paradigm folder being on the path just to open.
S.SelectorClass = '';
try
    S.SelectorClass = class(T.selector);
catch ME
    vprintf(3, 'epsych.SessionSnapshot: no trial selector to record (%s)', ME.message)
end

% The protocol, which is what makes the parameter tree rebuildable.
S.Protocol = struct();
try
    if isa(T.protocol, 'epsych.Protocol')
        S.Protocol = localTrimBuffers(T.protocol.toStruct());
    end
catch ME
    % A review without this degrades gracefully rather than failing: the
    % displays that read DATA still work and the controls are simply absent
    % (gui.BehaviorGUI.addControl skips parameters it cannot resolve).
    vprintf(0, 1, ME)
    vprintf(0, 1, 'epsych.SessionSnapshot: could not serialize the protocol; this session will review without its controls')
end

% The compiled trial table and the column map that names its columns, kept
% together for the same reason epsych.Runtime.compiledTrialColumns installs
% them together: a column index is meaningless without the map. This is the one
% part a mid-session recompile can outdate -- the table here is the one the
% session STARTED with, which is what a review of a recompiled session should
% say rather than a table that only the last few trials ran against.
S.TrialTable    = T.trials;
S.WriteParams   = T.writeparams;
S.WriteParamIdx = T.writeParamIdx;

% Present but empty. The operator's notes are typed during the session, long
% after this runs, so it is epsych.SessionSnapshot.withNotes -- called by
% forSubject at save time -- that fills these in. Declaring them here keeps the
% field set of a captured snapshot and a saved one the same.
S.Notes       = epsych.SessionNotes.emptyRecords();
S.NotesText   = '';
S.NotesEdited = false;

end




function ps = localTrimBuffers(ps)
% ps = localTrimBuffers(ps)
%
% Blank the CONTENTS of buffer parameters, keeping their metadata.
%
% This is the difference between a snapshot that costs 67 kB and one that costs
% 16 MB. hw.Parameter.toStruct serializes both Values and Value, and a
% calibration coefficient buffer is a 131072-sample vector -- measured at 245x
% the size of the entire rest of the protocol, and it would land in every
% session .mat AND every .epj info record.
%
% Nothing is lost that a review can use. gui.ParameterDebugger already refuses
% to read Buffer and Coefficient Buffer parameters for the same reason
% (megabytes off the device), and no display renders one. The name, type,
% access and bounds all survive, so the parameter still resolves and still
% appears; only its contents read empty.

if ~isfield(ps, 'InterfaceData') || isempty(ps.InterfaceData)
    return
end

BULK_TYPES = {'Buffer', 'Coefficient Buffer'};

for i = 1:numel(ps.InterfaceData)
    iface = ps.InterfaceData{i};
    if ~isfield(iface, 'Modules') || isempty(iface.Modules), continue; end

    for m = 1:numel(iface.Modules)
        mod = iface.Modules{m};
        if ~isfield(mod, 'Parameters') || isempty(mod.Parameters), continue; end

        for p = 1:numel(mod.Parameters)
            par = mod.Parameters{p};
            if ~isfield(par, 'Type') || ~ismember(char(string(par.Type)), BULK_TYPES)
                continue
            end
            if isfield(par, 'Values'), par.Values = {}; end
            if isfield(par, 'Value'),  par.Value  = []; end
            mod.Parameters{p} = par;
        end

        iface.Modules{m} = mod;
    end

    ps.InterfaceData{i} = iface;
end

end
