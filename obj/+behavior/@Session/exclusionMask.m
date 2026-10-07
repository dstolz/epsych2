function [excl, info] = exclusionMask(Data, options)
% [excl, info] = behavior.Session.exclusionMask(Data)
% [excl, info] = behavior.Session.exclusionMask(Data, Window = "20+", ...
%     ExcludeTest = true, ExcludeTrialTypes = 2)
% Which trials an analysis leaves out: THE rule, called by the browser, the
% analysis and every generated script.
%
% A trial is excluded when it lies outside the trial window, when it is a
% test (Preview) trial and test trials are excluded, or when its trial type
% is one of ExcludeTrialTypes. The trial type is the record's TrialType field
% where it has one, else the TrialType_k bit of its RespCode -- the order
% psychophysics.Psych resolves trial types in. The window counts RECORDS
% (the 20th record is trial 20), as psychophysics.TrialWindow.resolve does.
%
% Parameters:
%   Data              - trial records (struct array)
%   Window            - anything psychophysics.TrialWindow.parse reads
%                       ("all", "last 100", "3-83", "20+", a TrialWindow);
%                       default "all". Text it cannot read is an error.
%   ExcludeTest       - leave out isTest trials (default true)
%   ExcludeTrialTypes - trial types to leave out (default none)
%
% Returns:
%   excl - (1,n) logical, true = left out. find(excl) is what
%          psychophysics.Psych's ExcludedTrials takes.
%   info - struct:
%          NumTrials   - records
%          NumInWindow - records inside the window
%          NumTest     - test records inside the window
%          NumByType   - table TrialType/Count/Excluded over the window
%          NumExcluded, NumIncluded
%          Window      - the window as psychophysics.TrialWindow.toText
%          WindowLabel - TrialWindow.label: description and span
%
% See also: psychophysics.TrialWindow, behavior.Session.analyze

arguments
    Data
    options.Window = "all"
    options.ExcludeTest (1,1) logical = true
    options.ExcludeTrialTypes double = zeros(1, 0)
end

Data = reshape(Data, 1, []);
n = numel(Data);
w = psychophysics.TrialWindow.parse(options.Window);

inWindow = false(1, n);
inWindow(w.resolve(n)) = true;

fields = behavior.Session.fieldsOf_(Data);
isTest = reshape(behavior.Session.numeric_(Data, "isTest", fields) > 0, 1, []);
tt = behavior.Session.trialTypes_(Data);
byType = ismember(tt, options.ExcludeTrialTypes);

excl = ~inWindow | (options.ExcludeTest & isTest) | byType;

known = tt(inWindow & ~isnan(tt));
[u, ~, g] = unique(reshape(known, [], 1));
info = struct( ...
    'NumTrials',   n, ...
    'NumInWindow', sum(inWindow), ...
    'NumTest',     sum(isTest & inWindow), ...
    'NumByType',   table(u, accumarray(g, 1, [numel(u) 1]), ismember(u, options.ExcludeTrialTypes), ...
                       'VariableNames', {'TrialType', 'Count', 'Excluded'}), ...
    'NumExcluded', sum(excl), ...
    'NumIncluded', n - sum(excl), ...
    'Window',      w.toText(), ...
    'WindowLabel', w.label(n));

end
