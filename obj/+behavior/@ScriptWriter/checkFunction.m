function lines = checkFunction()
% lines = behavior.ScriptWriter.checkFunction()
% The local function every generated script ends with: compareWithRecorded,
% which compares a result against the values recorded when the script was
% written and says so, without ever throwing.
%
% A script re-runs the analysis; it does not carry the results across. What
% it can do is say whether it got the same numbers. compareWithRecorded
% compares the fields of expected (the literal written at generation) with
% the same-named fields of result by isequaln. A numeric value within 1e-6 of
% its own size of the recorded one is floating-point rounding, not a different
% analysis -- a later release may sum in another order -- and is counted
% rather than listed. The function never throws: a difference is information,
% and must not cost the analysis above it. It prints one of
%
%   <label>: replicated exactly (n recorded values compared).
%   <label>: replicated (n recorded values compared; m within floating-point
%            rounding of the recorded value).
%   <label>: k of n recorded values differ:
%       Threshold: recorded -14.5, now -13
%
% and returns ok, which is true in the first two cases.
%
% Returns:
%   lines - cellstr, one line of MATLAB source each, ready to append to a
%           script (which may hold local functions after its last command).
%
% See also: behavior.ScriptWriter, behavior.ScriptWriter.literal

lines = { ...
    'function ok = compareWithRecorded(result, expected, label)'
    '% Compare result''s fields with the values recorded when this script was'
    '% written. A numeric value within 1e-6 of its own size of the recorded one is'
    '% floating-point rounding, not a different analysis, and is counted rather'
    '% than listed. Never throws: a difference is information, and must not cost'
    '% the analysis above it.'
    'RELTOL = 1e-6;'
    'names = fieldnames(expected);'
    'diffs = cell(1, numel(names));'
    'nDiff = 0;'
    'nCompared = 0;'
    'nRounding = 0;'
    'for k = 1:numel(names)'
    '    name = names{k};'
    '    want = expected.(name);'
    '    if ~isfield(result, name)'
    '        nDiff = nDiff + 1;'
    '        diffs{nDiff} = sprintf(''%s: recorded %s, not in the result'', name, describeValue(want));'
    '        continue'
    '    end'
    '    got = result.(name);'
    '    nCompared = nCompared + 1;'
    '    if isequaln(got, want)'
    '        continue'
    '    end'
    '    if isnumeric(got) && isnumeric(want) && isequal(size(got), size(want))'
    '        g = double(got(:));'
    '        w = double(want(:));'
    '        same = (isnan(g) & isnan(w)) | (g == w) | ...'
    '            (abs(g - w) <= RELTOL * max(abs(g), abs(w)));'
    '        if all(same)'
    '            nRounding = nRounding + 1;'
    '            continue'
    '        end'
    '    end'
    '    nDiff = nDiff + 1;'
    '    diffs{nDiff} = sprintf(''%s: recorded %s, now %s'', name, describeValue(want), describeValue(got));'
    'end'
    'ok = nDiff == 0;'
    'if ok && nRounding == 0'
    '    fprintf(''%s: replicated exactly (%d recorded values compared).\n'', label, nCompared);'
    'elseif ok'
    '    fprintf([''%s: replicated (%d recorded values compared; %d within '' ...'
    '        ''floating-point rounding of the recorded value).\n''], label, nCompared, nRounding);'
    'else'
    '    fprintf(''%s: %d of %d recorded values differ:\n'', label, nDiff, numel(names));'
    '    fprintf(''    %s\n'', diffs{1:nDiff});'
    'end'
    'end'
    ''
    'function s = describeValue(x)'
    '% A value in a few characters: the numbers themselves while they fit, else'
    '% the class and size.'
    'if isnumeric(x) || islogical(x)'
    '    if numel(x) <= 6'
    '        s = mat2str(x, 15);'
    '    else'
    '        s = sprintf(''%s %s'', mat2str(size(x)), class(x));'
    '    end'
    'elseif ischar(x) || (isstring(x) && isscalar(x))'
    '    s = sprintf(''"%s"'', x);'
    'else'
    '    s = sprintf(''%s %s'', mat2str(size(x)), class(x));'
    'end'
    'end'
    };
lines = reshape(lines, 1, []);

end
