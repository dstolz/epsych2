function R = explore_oddball_data(datafile, options)
% R = explore_oddball_data(datafile, Name=Value, ...)
% Load a session saved by the oddball example, decode the response codes,
% and summarize the subject's behavior: outcome counts, hit and false-alarm
% rates and d', hit rate by deviant sound and by how many standards came
% before it, false alarms by position in the run, reaction times -- and a
% check that the stream really was block-randomized.
%
% Works on any session whose DATA records carry RespCode (epsych.BitMask
% codes, TrialType_0 = deviant, TrialType_1 = standard), StimFile, StimID,
% RunLength, RunPosition and RT_ms; run run_oddball_experiment (or a RunExpt
% session with OddballBehaviorGUI) to make one.
%
% Parameters:
%   datafile - Path to a session .mat (variables Data and, optionally,
%              Info and Sequences). Default: the newest .mat under data/ in
%              this folder.
%
% Options:
%   Plot - Draw the session figure (default true)
%
% Returns:
%   R - Results struct: datafile, nTrials, nDeviants, nStandards, counts
%       (Hit, Miss, FalseAlarm, CorrectReject), hitRate, faRate, dprime
%       (psychophysics.Metrics.fromCounts, default correction), byDeviant
%       and byRunLength (tables of hit rate), faByPosition (table),
%       runLengths (the length of every completed run), medianRT (hits),
%       and the decoded flag struct M.
%
% See also run_oddball_experiment, OddballSelector, epsych.BitMask,
%   psychophysics.Metrics

arguments
    datafile (1,:) char = ''
    options.Plot (1,1) logical = true
end

here = fileparts(mfilename('fullpath'));
if isempty(datafile)
    d = dir(fullfile(here, 'data', '**', '*.mat'));
    d = d(~startsWith({d.name}, 'RUNTIME_DATA_')); % skip crash-recovery seeds
    assert(~isempty(d), ...
        'No session files under %s - run run_oddball_experiment first.', fullfile(here, 'data'))
    [~, newest] = max([d.datenum]);
    datafile = fullfile(d(newest).folder, d(newest).name);
end

S = load(datafile);
assert(isfield(S, 'Data'), 'Expected a "Data" variable in %s', datafile)
DATA = S.Data;
need = {'RespCode', 'StimFile', 'StimID', 'RunLength', 'RunPosition', 'RT_ms'};
assert(all(isfield(DATA, need)), ...
    'This session lacks the fields this example analyzes: %s', strjoin(need, ', '))

% --- Session facts -------------------------------------------------------
% DATA is in presentation order. DATA.TrialID is the condition row (here
% 1 = deviant, 2 = standard), not the order -- always iterate by index.
fprintf('\nSession file : %s\n', datafile)
fprintf('Trials       : %d sounds\n', numel(DATA))
t = [DATA.computerTimestamp];
fprintf('Time span    : %s to %s\n', string(t(1)), string(t(end)))
if any([DATA.isTest])
    fprintf('NOTE         : flagged as test data (preview session)\n')
end
if isfield(S, 'Info') && isfield(S.Info, 'NotesText')
    % OddballSelector writes its seeds into the session notes, which every
    % saving function folds into Info -- the stream is replayable from them.
    lines = splitlines(string(S.Info.NotesText));
    seedNote = lines(contains(lines, 'sequence seeds'));
    if ~isempty(seedNote), fprintf('Sequences    : %s\n', strtrim(seedNote(1))); end
end

% --- Decode outcomes -----------------------------------------------------
M = epsych.BitMask.decode(uint32([DATA.RespCode]));
isDev = M.TrialType_0;
isStd = M.TrialType_1;
rt    = [DATA.RT_ms];
runLen = [DATA.RunLength];
runPos = [DATA.RunPosition];
stimID = [DATA.StimID];

C = struct('Hit', nnz(M.Hit), 'Miss', nnz(M.Miss), ...
    'FalseAlarm', nnz(M.FalseAlarm), 'CorrectReject', nnz(M.CorrectReject));
Sdt = psychophysics.Metrics.fromCounts(C.Hit, C.Miss, C.FalseAlarm, C.CorrectReject);

fprintf('\nOutcomes\n')
fprintf('  Deviants  : %3d  (%d hits, %d misses)\n', nnz(isDev), C.Hit, C.Miss)
fprintf('  Standards : %3d  (%d false alarms, %d correct rejects)\n', nnz(isStd), ...
    C.FalseAlarm, C.CorrectReject)
fprintf('  Hit rate %.2f, false-alarm rate %.2f, d'' %.2f (%s correction)\n', ...
    Sdt.Rate.Hit, Sdt.Rate.FalseAlarm, Sdt.DPrime, Sdt.Correction)

% --- By deviant sound ----------------------------------------------------
% StimID is the position within the bank in force at the time; the file
% name is the identity that survives a bank change, so group by that.
devFiles = string({DATA(isDev).StimFile});
[~, devNames, ext] = fileparts(devFiles);
devNames = devNames + ext;
[u, ~, g] = unique(devNames);
devHit = M.Hit(isDev);
byDeviant = table(u(:), accumarray(g(:), 1), accumarray(g(:), double(devHit(:)), [], @mean), ...
    VariableNames = {'Sound', 'N', 'HitRate'});
fprintf('\nHit rate by deviant sound\n')
disp(byDeviant)

% --- By number of preceding standards ------------------------------------
% A deviant's RunLength IS the number of standards it followed.
[uL, ~, gL] = unique(runLen(isDev));
byRunLength = table(uL(:), accumarray(gL(:), 1), accumarray(gL(:), double(devHit(:)), [], @mean), ...
    VariableNames = {'StandardsBefore', 'N', 'HitRate'});
fprintf('Hit rate by number of standards before the deviant\n')
disp(byRunLength)

% --- False alarms by position in the run ---------------------------------
[uP, ~, gP] = unique(runPos(isStd));
stdFA = M.FalseAlarm(isStd);
faByPosition = table(uP(:), accumarray(gP(:), 1), accumarray(gP(:), double(stdFA(:)), [], @mean), ...
    VariableNames = {'Position', 'N', 'FARate'});
fprintf('False-alarm rate by position of the standard in its run\n')
disp(faByPosition)

% --- Was the stream block-randomized? ------------------------------------
% Every completed run ends in a deviant whose RunLength is the run's
% length. Within each block of B runs (B = number of allowed lengths),
% every length should appear exactly once -- the block guarantee, which
% plain random sampling would not give.
runLengths = runLen(isDev);
fprintf('Run lengths, in order: %s\n', mat2str(runLengths))
allowed = unique(runLengths);
fprintf('Allowed lengths seen : %s (each %s times)\n', mat2str(allowed), ...
    mat2str(arrayfun(@(L) nnz(runLengths == L), allowed)))
stdFiles = string({DATA(isStd).StimFile});
[~, stdNames, ext] = fileparts(stdFiles);
[us, ~, gs] = unique(stdNames + ext);
fprintf('Standards played     : %s\n', strjoin(compose('%s x%d', us(:), accumarray(gs(:), 1)), ', '))

% --- Reaction times ------------------------------------------------------
hitRT = rt(M.Hit);
faRT  = rt(M.FalseAlarm);
fprintf('Median RT: hits %.0f ms (n=%d), false alarms %.0f ms (n=%d)\n', ...
    median(hitRT), numel(hitRT), median(faRT), numel(faRT))

R = struct('datafile', datafile, 'nTrials', numel(DATA), ...
    'nDeviants', nnz(isDev), 'nStandards', nnz(isStd), 'counts', C, ...
    'hitRate', Sdt.Rate.Hit, 'faRate', Sdt.Rate.FalseAlarm, 'dprime', Sdt.DPrime, ...
    'byDeviant', byDeviant, 'byRunLength', byRunLength, 'faByPosition', faByPosition, ...
    'runLengths', runLengths, 'medianRT', median(hitRT), 'M', M, 'stimID', stimID);

if options.Plot
    plotSession(DATA, M, rt, byRunLength, byDeviant, datafile);
end
end


function plotSession(DATA, M, rt, byRunLength, byDeviant, datafile)
f = figure(Name = 'Oddball session', Color = 'w');
tl = tiledlayout(f, 2, 2, TileSpacing = 'compact', Padding = 'compact');
[~, nm] = fileparts(datafile);
title(tl, nm, Interpreter = 'none')

% Timeline: every sound, deviants up, standards down, colored by outcome.
ax = nexttile(tl, [1 2]);
hold(ax, 'on')
n = 1:numel(DATA);
y = double(M.TrialType_0) - double(M.TrialType_1);
outcomes = {'Hit', 'Miss', 'FalseAlarm', 'CorrectReject'};
for k = 1:numel(outcomes)
    o = outcomes{k};
    idx = M.(o);
    stem(ax, n(idx), y(idx), 'filled', Color = epsych.BitMask.getDefaultColors(epsych.BitMask.(o)), ...
        DisplayName = o, MarkerSize = 4);
end
yline(ax, 0, 'k-', HandleVisibility = 'off');
ylim(ax, [-1.5 1.5])
yticks(ax, [-1 1]); yticklabels(ax, {'standard', 'deviant'})
xlabel(ax, 'Trial (sound)')
legend(ax, Location = 'eastoutside')
title(ax, 'Every sound and how it was scored')

ax = nexttile(tl);
bar(ax, byRunLength.StandardsBefore, byRunLength.HitRate, FaceColor = [0.12 0.63 0.31]);
ylim(ax, [0 1]); xlabel(ax, 'Standards before the deviant'); ylabel(ax, 'Hit rate')
title(ax, 'Hit rate by run length')

ax = nexttile(tl);
hold(ax, 'on')
edges = 0:100:max([rt(rt >= 0), 1500]);
if any(M.Hit), histogram(ax, rt(M.Hit), edges, DisplayName = 'Hits'); end
if any(M.FalseAlarm), histogram(ax, rt(M.FalseAlarm), edges, DisplayName = 'False alarms'); end
xlabel(ax, 'Reaction time from onset (ms)'); ylabel(ax, 'Count')
if any(M.Hit) || any(M.FalseAlarm), legend(ax); end
title(ax, sprintf('Reaction times (%d deviant sounds)', height(byDeviant)))
end
