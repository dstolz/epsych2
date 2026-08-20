function load_(obj, datafile, protocolFile)
% load_(obj, datafile, protocolFile)
% Read a session file into obj.Data and obj.Snapshot.
%
% Three artifact shapes exist and all three have to open:
%
%   saved session   - Data [+ Info]. What a saving function writes.
%   recovery .mat   - info + data_0001..data_NNNN. What ep_TimerFcn_Start seeds
%                     and ep_TimerFcn_Stop (or epsych.TrialJournal.recover)
%                     merges the journal into. Reassembled here rather than by
%                     the caller, so a crashed session reviews like any other.
%   .epj journal    - read through epsych.TrialJournal, which also reports a
%                     torn tail. A live session's journal can be read while it
%                     is still being written, so this doubles as a way to look
%                     at a run in progress from a second MATLAB.
%
% Parameters:
%   obj          - epsych.ReviewSession being constructed.
%   datafile     - Path to the file.
%   protocolFile - Optional .eprot to take the parameter tree from when the
%                  file carries no snapshot.
%
% See also: epsych.SessionSnapshot.fromInfo, epsych.TrialJournal.read

arguments
    obj
    datafile (1,:) char
    protocolFile (1,:) char = ''
end

assert(isfile(datafile), 'epsych:ReviewSession:FileNotFound', ...
    'No such file: "%s"', datafile)

obj.DataFile = char(datafile);

[~, ~, ext] = fileparts(datafile);

if strcmpi(ext, '.epj')
    [S, torn] = epsych.TrialJournal.read(datafile);
    if torn
        vprintf(0, 1, ['epsych.ReviewSession: "%s" ends in a torn record; ' ...
            'every trial before it was recovered'], datafile)
    end
else
    S = load(datafile);
end

info = [];
if isfield(S, 'Info')
    info = S.Info;
elseif isfield(S, 'info')
    info = S.info;
end

% Multi-subject files write one file per subject, so Info is scalar. A struct
% array can only come from a hand-built file; take the requested subject.
if isstruct(info) && numel(info) > 1 && numel(info) >= obj.SubjectIndex
    info = info(obj.SubjectIndex);
end

obj.Snapshot = epsych.SessionSnapshot.fromInfo(info);

% --- The trial records ---------------------------------------------------
if isfield(S, 'Data') && isstruct(S.Data) && ~isempty(S.Data)
    obj.Data = reshape(S.Data, 1, []);
else
    obj.Data = localAssembleTrialRecords(S);
end

vprintf(1, 'epsych.ReviewSession: %d trial(s) from "%s"', numel(obj.Data), datafile)

% --- A protocol supplied by the caller wins ------------------------------
% Deliberately checked after the snapshot: an operator naming an .eprot is
% correcting or supplying what the file could not say, and should not have to
% argue with a stale embedded copy.
if ~isempty(protocolFile)
    obj.Snapshot.Protocol = localProtocolStruct(protocolFile);
end

end




function Data = localAssembleTrialRecords(S)
% Data = localAssembleTrialRecords(S)
%
% Rebuild the chronological record array from data_0001..data_NNNN variables.
% Sorted by NAME, which is the trial index zero-padded to four digits by
% ep_TimerFcn_RunTime -- so this is chronological, and stays so past trial
% 9999 only because the padding grows rather than wrapping. It is not sorted
% by TrialID: that is the condition label, not the presentation order.

Data = struct.empty(1,0);

fn = fieldnames(S);
fn = sort(fn(startsWith(fn, 'data_')));
if isempty(fn), return; end

records = cellfun(@(f) S.(f), fn, UniformOutput = false);

try
    Data = [records{:}];
catch ME
    % A mid-session recompile can change the recorded field set, and then the
    % records do not concatenate. Keep the longest run that does rather than
    % refusing to open the file at all.
    vprintf(0, 1, ME)
    Data = records{1};
    for k = 2:numel(records)
        try
            Data(end+1) = records{k};
        catch
            vprintf(0, 1, ['epsych.ReviewSession: trial %d records different fields ' ...
                'from the trials before it (a mid-session recompile); reviewing the first %d'], ...
                k, numel(Data))
            break
        end
    end
end

Data = reshape(Data, 1, []);

end




function ps = localProtocolStruct(protocolFile)
% ps = localProtocolStruct(protocolFile)
%
% The serialized form of an .eprot named by the operator, in the same shape
% epsych.SessionSnapshot.capture stores. Compiled first, so the parameter set
% matches what a session would have had.

ps = struct();

try
    P = epsych.Protocol.load(protocolFile);
    P.compile();
    ps = P.toStruct();
    vprintf(1, 'epsych.ReviewSession: parameters taken from "%s"', protocolFile)
catch ME
    vprintf(0, 1, ME)
    vprintf(0, 1, ['epsych.ReviewSession: could not read "%s"; ' ...
        'the review will show its data displays without parameter controls'], protocolFile)
end

end
