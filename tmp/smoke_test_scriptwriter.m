function smoke_test_scriptwriter()
% smoke_test_scriptwriter
% Standing proof of behavior.ScriptWriter's two exactness guarantees:
%   1-6. literal: for every value below, eval(literal(v)) is isequaln to v, of
%        the same class and size, with a datetime's zone and format and a
%        categorical's categories and order intact; long lists wrap at
%        LineWidth and still read back; an unsupported value throws.
%   7.   checkFunction: the compareWithRecorded local function a generated
%        script ends with reports an exact match, counts rounding, lists real
%        differences and missing fields, and never throws.
%
%   run('tmp/smoke_test_scriptwriter.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
if exist('epsych.BitMask', 'class') ~= 8
    run(fullfile(repoRoot, 'epsych_startup.m'));
end

results = cell(0, 2);

%% 1. Numbers
try
    vals = { ...
        0, -0, 1/3, pi, 1e-320, 1e300, -2.5, NaN, Inf, -Inf, realmax, realmin, eps, ...
        123456789012345680, 0.1 + 0.2, [1 2 3], [1; 2; 3], magic(3), [NaN -Inf 0 -0], ...
        zeros(0, 3), [], zeros(3, 0), zeros(2, 0, 2), ...
        single(0.1), single([1 2; 3 4]), single(NaN), single.empty(0, 2), ...
        int32(-5), uint8([1 2 3]), int64(-9007199254740993), uint64(18446744073709551615), ...
        intmin('int64'), int16.empty(1, 0), uint32(magic(3))};
    rows = cellfun(@checkRoundTrip, vals, 'UniformOutput', false);
    results = [results; vertcat(rows{:})];
    x = reshape(1:24, [2 3 4]);
    results(end+1,:) = checkRoundTrip(x);
    results(end+1,:) = check('-0 keeps its sign bit', ...
        1 / eval(behavior.ScriptWriter.literal(-0)) == -Inf);
catch ME
    results(end+1,:) = check(['group 1: ' ME.message], false);
end

%% 2. Logicals, char and string
try
    vals = { ...
        true, false, [true false true], true(2, 2), false(0, 3), logical([1 0; 0 1]), ...
        'abc', '', 'it''s', sprintf('a\nb'), ['ab'; 'cd'], char(zeros(1, 0)), ...
        char([956 86 8212]), ...                       % µV—
        "x", "", string(missing), ["a" "b"; "c" "d"], strings(0, 1), "quote""d", ...
        "tab" + char(9) + "bed", "é", ["a" string(missing)], strings(1, 0)};
    rows = cellfun(@checkRoundTrip, vals, 'UniformOutput', false);
    results = [results; vertcat(rows{:})];
catch ME
    results(end+1,:) = check(['group 2: ' ME.message], false);
end

%% 3. Cells and structs
try
    s3 = struct('a', {1, 2, 3}, 'b', {'x', 'y', 'z'});
    vals = { ...
        {}, {1, 'a', [1 2]}, {1; 2}, {{1}, {'x', {}}}, cell(0, 2), {1, 2; 3, 4}, ...
        struct('a', 1, 'b', 'x'), struct(), struct([]), struct('a', {}), ...
        reshape(struct('a', {}), 1, 0), s3, s3', struct('c', {{1, 2}}), ...
        struct('d', datetime(2026, 10, 7), 't', {{"a"; "b"}}), ...
        struct('n', struct('m', [1 2 3]), 'e', [])};
    rows = cellfun(@checkRoundTrip, vals, 'UniformOutput', false);
    results = [results; vertcat(rows{:})];
catch ME
    results(end+1,:) = check(['group 3: ' ME.message], false);
end

%% 4. Times, categories and enumerations
try
    d = datetime(2026, 10, 7, 11, 42, 23.123456789);
    dz = datetime(2026, 10, 7, 11, 42, 23, 'TimeZone', 'America/New_York');
    dn = datetime('now');
    dn.Format = 'dd-MMM-yyyy HH:mm:ss';
    vals = { ...
        d, NaT, dz, [d d + seconds(1) NaT], dn, NaT(0, 1), ...
        seconds(1.5), [minutes(1) hours(2)], seconds(NaN), ...
        categorical({'a', 'b', 'a'}), categorical({'lo', 'hi'}, {'lo', 'hi'}, 'Ordinal', true), ...
        categorical({'a', ''}, {'a', 'b'}), ...
        epsych.BitMask.Hit, [epsych.BitMask.Hit epsych.BitMask.Miss], epsych.BitMask.empty(1, 0)};
    rows = cellfun(@checkRoundTrip, vals, 'UniformOutput', false);
    results = [results; vertcat(rows{:})];
    w = eval(behavior.ScriptWriter.literal(dz));
    results(end+1,:) = check('a zoned datetime keeps its zone', strcmp(w.TimeZone, dz.TimeZone));
    w = eval(behavior.ScriptWriter.literal(dn));
    results(end+1,:) = check('a datetime keeps its display format', strcmp(w.Format, dn.Format));
    c = categorical({'lo', 'hi'}, {'lo', 'hi'}, 'Ordinal', true);
    w = eval(behavior.ScriptWriter.literal(c));
    results(end+1,:) = check('an ordinal categorical keeps its order', ...
        isordinal(w) && isequal(categories(w), categories(c)));
catch ME
    results(end+1,:) = check(['group 4: ' ME.message], false);
end

%% 5. Tables
try
    T1 = table([1; 2], {'a'; 'b'}, ["x"; "y"], 'VariableNames', {'n', 'c', 's'});
    T2 = T1;
    T2.Properties.RowNames = {'first', 'second'};
    T3 = table(zeros(0, 1), strings(0, 1), 'VariableNames', {'n', 's'});
    T4 = table([1; 2], [3 4; 5 6], 'VariableNames', {'a', 'm'});
    vals = {T1, T2, T3, T4, table()};
    rows = cellfun(@checkRoundTrip, vals, 'UniformOutput', false);
    results = [results; vertcat(rows{:})];
catch ME
    results(end+1,:) = check(['group 5: ' ME.message], false);
end

%% 6. Wrapping and refusals
try
    long = 1:200;
    txt = behavior.ScriptWriter.literal(long);
    lines = splitlines(string(txt));
    results(end+1,:) = check('a long list is continued', numel(lines) > 1);
    results(end+1,:) = check('no continued line exceeds LineWidth by more than one token', ...
        all(strlength(lines) <= behavior.ScriptWriter.LineWidth + 8));
    results(end+1,:) = check('every continued line but the last ends in ...', ...
        all(endsWith(lines(1:end-1), "...")));
    results(end+1,:) = check('the continued list reads back', isequal(eval(txt), long));
    txt = behavior.ScriptWriter.literal(long, LineWidth=40, Indent=2);
    lines = splitlines(string(txt));
    results(end+1,:) = check('LineWidth and Indent are honoured', ...
        numel(lines) > 5 && all(startsWith(lines(2:end), "  ")) && isequal(eval(txt), long));
    big = struct('Levels', (1:60)', 'Names', string(1:60));
    results(end+1,:) = checkRoundTrip(big);

    results(end+1,:) = check('a function handle is refused', ...
        throwsWith(@() behavior.ScriptWriter.literal(@sin), 'behavior:ScriptWriter:Unsupported'));
    results(end+1,:) = check('a Map is refused', ...
        throwsWith(@() behavior.ScriptWriter.literal(containers.Map()), 'behavior:ScriptWriter:Unsupported'));
    results(end+1,:) = check('a complex number is refused', ...
        throwsWith(@() behavior.ScriptWriter.literal(1 + 2i), 'behavior:ScriptWriter:Unsupported'));
catch ME
    results(end+1,:) = check(['group 6: ' ME.message], false);
end

%% 7. The replication check a generated script ends with
try
    lines = behavior.ScriptWriter.checkFunction();
    results(end+1,:) = check('checkFunction returns the local function''s source', ...
        iscell(lines) && all(cellfun(@ischar, lines)) && startsWith(lines{1}, 'function ok = compareWithRecorded'));

    folder = fullfile(tempdir, sprintf('epsych_scriptwriter_smoke_%d', feature('getpid')));
    mkdir(folder);
    cleaner = onCleanup(@() localRemove(folder));
    addpath(folder);
    body = { ...
        'function R = check_smoke()'
        'result = struct(''Threshold'', -14.5, ''ReversalCount'', 17, ''Fit'', 1.00000001, ''Levels'', [1 2 NaN]);'
        'R.exact = compareWithRecorded(result, struct(''Threshold'', -14.5, ''Levels'', [1 2 NaN]), "exact");'
        'R.rounding = compareWithRecorded(result, struct(''Fit'', 1), "rounding");'
        'R.differs = compareWithRecorded(result, struct(''Threshold'', -13, ''Missing'', 1, ''Levels'', [1 2 3]), "differs");'
        'R.type = compareWithRecorded(result, struct(''ReversalCount'', "17"), "type");'
        'end'
        ''};
    fid = fopen(fullfile(folder, 'check_smoke.m'), 'w');
    fprintf(fid, '%s\n', body{:}, lines{:});
    fclose(fid);
    out = evalc('R = check_smoke();');
    results(end+1,:) = check('an exact match is reported as replicated exactly', ...
        R.exact && contains(out, 'exact: replicated exactly (2 recorded values compared)'));
    results(end+1,:) = check('a rounding-level difference is counted, not listed', ...
        R.rounding && contains(out, 'rounding: replicated (1 recorded values compared; 1 within floating-point rounding'));
    results(end+1,:) = check('a real difference and a missing field are listed', ...
        ~R.differs && contains(out, 'differs: 3 of 3 recorded values differ') ...
        && contains(out, 'Threshold: recorded -13, now -14.5') ...
        && contains(out, 'Missing: recorded 1, not in the result') ...
        && contains(out, 'Levels: recorded [1 2 3], now [1 2 NaN]'));
    results(end+1,:) = check('a type difference is a difference', ...
        ~R.type && contains(out, 'type: 1 of 1 recorded values differ'));
    clear cleaner
catch ME
    results(end+1,:) = check(['group 7: ' ME.message], false);
end

%% Summary
fprintf('\n');
nFail = 0;
for k = 1:size(results, 1)
    if results{k,2}
        tag = 'PASS';
    else
        tag = 'FAIL';
        nFail = nFail + 1;
    end
    fprintf('  %s  %s\n', tag, results{k,1});
end
fprintf('smoke_test_scriptwriter: %d checks, %d failed\n', size(results, 1), nFail);
if nFail > 0
    error('smoke_test_scriptwriter:Failed', '%d check(s) failed', nFail);
end
end



function row = check(label, tf)
row = {char(label), logical(tf)};
end

function row = checkRoundTrip(v)
label = sprintf('%s %s round-trips', mat2str(size(v)), class(v));
try
    txt = behavior.ScriptWriter.literal(v);
    w = eval(txt);
    ok = isequaln(w, v) && strcmp(class(w), class(v)) && isequal(size(w), size(v));
    if ~ok
        label = sprintf('%s  [got: %s]', label, strtrim(evalc('disp(txt)')));
    end
catch ME
    ok = false;
    label = sprintf('%s  [%s]', label, ME.message);
end
row = {label, ok};
end

function tf = throwsWith(fcn, id)
tf = false;
try
    fcn();
catch ME
    tf = strcmp(ME.identifier, id);
end
end

function localRemove(folder)
rmpath(folder);
if isfolder(folder)
    rmdir(folder, 's');
end
end
