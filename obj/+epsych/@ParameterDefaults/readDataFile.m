function [vals, report] = readDataFile(file, T)
% [vals, report] = epsych.ParameterDefaults.readDataFile(file, T)
% The values the parameters T name held on the last trial of a saved session.
%
% A saved session's Data array has one record per completed trial, with a
% field per readable parameter named by its validName (ep_TimerFcn_RunTime
% reads them at each trial's completion). The LAST filled record is the one
% read: where a staircase ended, the reward volume the session finished on.
% Bounds are not in the data -- only values are recorded per trial -- so this
% never proposes a Min or Max.
%
% A field that is missing (a write-only or hidden parameter never makes it into
% Data, and a renamed one is under its old name) leaves that row not Found.
%
% Parameters:
%   file - a saved session .mat (a variable named Data).
%   T    - rows from epsych.ParameterDefaults.parameters (Name is used).
%
% Returns:
%   vals   - (1,:) struct aligned with T: Found, Value.
%   report - struct: File, NumTrials, Message ('' when the file was read).
%
% See also: epsych.ParameterDefaults.latestDataFile, epsych.SessionFiles.summarize
arguments
    file (1,:) char
    T struct
end

vals = repmat(struct('Found', false, 'Value', []), 1, numel(T));
report = struct('File', file, 'NumTrials', 0, 'Message', '');

if ~isfile(file)
    report.Message = sprintf('The data file does not exist: %s', file);
    return
end

try
    w = whos('-file', file);
catch ME
    report.Message = sprintf('The data file could not be read: %s', ME.message);
    return
end
if ~any(strcmp({w.name}, 'Data') & strcmp({w.class}, 'struct'))
    report.Message = sprintf('%s holds no session Data.', file);
    return
end

% Warnings held back as epsych.SessionFiles does: a class that has changed since
% the file was saved warns per variable, and the values read here do not depend
% on those objects.
ws = warning('off', 'all');
restore = onCleanup(@() warning(ws));
try
    S = load(file, 'Data');
catch ME
    report.Message = sprintf('The data file could not be loaded: %s', ME.message);
    return
end
clear restore

Data = reshape(S.Data, 1, []);
if isempty(Data) || isempty(fieldnames(Data))
    report.Message = sprintf('%s holds no trials.', file);
    return
end

% An all-empty record is not a trial: older saving functions wrote one as a
% placeholder for a session that completed none.
c = struct2cell(Data);
filled = find(reshape(any(~cellfun(@isempty, c), 1), 1, []));
if isempty(filled)
    report.Message = sprintf('%s holds no trials.', file);
    return
end
report.NumTrials = numel(filled);
last = Data(filled(end));

for i = 1:numel(T)
    vn = matlab.lang.makeValidName(T(i).Name);
    if isfield(last, vn)
        vals(i).Found = true;
        vals(i).Value = last.(vn);
    end
end
end
