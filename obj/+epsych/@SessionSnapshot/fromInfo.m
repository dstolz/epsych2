function S = fromInfo(info)
% S = epsych.SessionSnapshot.fromInfo(info)
% Normalize whatever a file carries as Info into a snapshot struct.
%
% Three shapes are in the wild and all three have to open:
%
%   a snapshot          - written by capture(); used as-is, with any field a
%                         newer version added filled in empty.
%   flat EPsychInfo.meta - what cl_SaveDataFcn wrote as Info before this class
%                         existed. Version and checksum survive; there is no
%                         protocol, so a review of one of these shows its data
%                         displays and no controls.
%   the recovery info    - what ep_TimerFcn_Start seeds the crash-recovery .mat
%                         and .epj with: Subject, CompStartTimestamp,
%                         EPsychMeta, isTest. Since 2026-08 that record IS a
%                         snapshot, so only files written before then take this
%                         path.
%
% Missing fields are filled in empty rather than guessed, and the caller is
% expected to tell the operator what a degraded review is missing rather than
% let absent controls look like a bug.
%
% Parameters:
%   info - The Info (or info) variable from a session file; [] when absent.
%
% Returns:
%   S - Snapshot struct with every documented field present.
%
% See also: epsych.SessionSnapshot.capture, epsych.ReviewSession

arguments
    info = []
end

S = localBlank();

if isempty(info) || ~isstruct(info) || ~isscalar(info)
    return
end

if epsych.SessionSnapshot.isSnapshot(info)
    % Additive by contract: copy what the file has over the blank, so a field
    % this version knows about and an older file does not stays empty.
    for f = string(fieldnames(info))'
        S.(f) = info.(f);
    end
    return
end

% --- Legacy shapes -------------------------------------------------------
% Both carry provenance and nothing that can rebuild parameters.

if isfield(info, 'EPsychMeta') && isstruct(info.EPsychMeta)
    % The recovery info record.
    S.EPsychMeta = info.EPsychMeta;
elseif isfield(info, 'Version') || isfield(info, 'Checksum')
    % A flat EPsychInfo.meta written straight into Info.
    S.EPsychMeta = info;
end

if isfield(info, 'Subject'),  S.Subject = info.Subject; end
if isfield(info, 'BoxID'),    S.BoxID   = info.BoxID;   end
if isfield(info, 'isTest'),   S.isTest  = logical(info.isTest); end

if isfield(info, 'CompStartTimestamp')
    S.StartTime = info.CompStartTimestamp;
elseif isfield(info, 'StartTime')
    S.StartTime = info.StartTime;
end

% Debug level, not info: fromInfo is called by ordinary analysis scripts
% (examples/*/explore_*_data.m) that have no interest in reviewing anything,
% and a line about parameter controls is noise there. The review path says so
% itself, in its own words, from epsych.ReviewSession.buildRuntime_.
vprintf(2, 'epsych.SessionSnapshot: this file predates the session snapshot; its protocol is unknown')

end




function S = localBlank()
% S = localBlank()
%
% Every documented field, empty. Written out rather than built from capture()
% so that a reader can rely on the field set without a live runtime, and so
% that adding a field here is the one place a default has to be chosen.

S = struct( ...
    'FormatVersion',  epsych.SessionSnapshot.FORMAT_VERSION, ...
    'EPsychMeta',     struct(), ...
    'Subject',        [], ...
    'BoxID',          [], ...
    'StartTime',      NaT, ...
    'isTest',         false, ...
    'DataFilename',   '', ...
    'SelectorClass',  '', ...
    'Protocol',       struct(), ...
    'TrialTable',     {{}}, ...
    'WriteParams',    {{}}, ...
    'WriteParamIdx',  struct(), ...
    'Notes',          {epsych.SessionNotes.emptyRecords()}, ...
    'NotesText',      '', ...
    'NotesEdited',    false);

end
