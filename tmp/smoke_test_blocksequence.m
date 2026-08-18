function smoke_test_blocksequence()
% smoke_test_blocksequence
% Gates epsych.BlockSequence: block balance, constraint satisfaction, and the
% guarantees the caller-owned index depends on -- determinism from a seed,
% rewind stability across an extension, and a frozen prefix across a
% mid-session edit to the value list.
%
% Headless-safe: no figures, no hardware.
%
%   matlab -batch "run('tmp/smoke_test_blocksequence.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

oldRng = rng(0);
restoreRng = onCleanup(@() rng(oldRng)); % restores the global rng on exit

failures = {};

% 1. Determinism ----------------------------------------------------------
try
    a = epsych.BlockSequence([1 2 3 4], Seed = 42);
    b = epsych.BlockSequence([1 2 3 4], Seed = 42);
    va = a.valueAt(1:500, Commit = false);
    assert(isequal(va, b.valueAt(1:500, Commit = false)), 'same seed gave different sequences');
    a.regenerate();
    assert(isequal(va, a.valueAt(1:500, Commit = false)), 'regenerate did not reproduce the sequence');
    fprintf('PASS: 1. same seed and config reproduce the sequence exactly\n');
catch ME
    failures{end+1} = sprintf('1. determinism: %s', ME.message);
    fprintf('FAIL: 1. %s\n', ME.message);
end

% 2. The global random stream is untouched ---------------------------------
try
    s0 = rng;
    q = epsych.BlockSequence([1 2 3 4 5], Seed = 7, MinLength = 5000);
    q.valueAt(1:5000, Commit = false);
    q.reseed(1234);
    q.extend(10);
    epsych.BlockSequence([1 2 3]);              % a shuffled seed, too
    s1 = rng;
    assert(isequal(s0.State, s1.State) && strcmp(s0.Type, s1.Type), ...
        'the global rng state moved');
    fprintf('PASS: 2. generation never advances the global random stream\n');
catch ME
    failures{end+1} = sprintf('2. global rng: %s', ME.message);
    fprintf('FAIL: 2. %s\n', ME.message);
end

% 3. Exact block balance --------------------------------------------------
try
    s = epsych.BlockSequence([1 2 3 4], Seed = 3);
    for k = 1:25
        n = histcounts(s.indexAt(1:4*k), 0.5:1:4.5);
        assert(all(n == k), 'block %d is unbalanced (%s)', k, mat2str(n));
    end

    s = epsych.BlockSequence([10 20 30 40], Repeats = [2 2 3 1], Seed = 3);
    B = s.BlockSize;
    assert(B == 8, 'BlockSize should be 8, got %d', B);
    for b = 1:40
        n = histcounts(s.indexAt((b-1)*B + (1:B)), 0.5:1:4.5);
        assert(isequal(n, [2 2 3 1]), 'block %d composition %s', b, mat2str(n));
    end
    fprintf('PASS: 3. every block holds each value exactly its Repeats count\n');
catch ME
    failures{end+1} = sprintf('3. block balance: %s', ME.message);
    fprintf('FAIL: 3. %s\n', ME.message);
end

% 4. Rewind stability under extension -------------------------------------
try
    s = epsych.BlockSequence([1 2 3 4 5], Seed = 88, MinLength = 100);
    v = s.valueAt(1:100, Commit = false);
    len = s.Length;
    for step = [500 2000 5000]
        s.valueAt(step, Commit = false);
        assert(s.Length > len, 'extension did not grow the sequence');
        len = s.Length;
        assert(isequal(s.valueAt(1:100, Commit = false), v), ...
            'extension to %d rewrote earlier elements', step);
    end
    fprintf('PASS: 4. extension only appends; a rewind returns the same values\n');
catch ME
    failures{end+1} = sprintf('4. rewind stability: %s', ME.message);
    fprintf('FAIL: 4. %s\n', ME.message);
end

% 5. Constraint satisfaction ----------------------------------------------
try
    s = epsych.BlockSequence([1 2 3], Repeats = 2, MaxConsecutive = 2, ...
        Seed = 5, MinLength = 5000);
    v = s.valueAt(1:5000, Commit = false);
    m = longestRun(v);
    assert(m == 2, 'longest run is %d, expected exactly 2', m);

    s = epsych.BlockSequence([1 2 3 4], NoRepeatAcrossBlocks = true, ...
        Seed = 6, MinLength = 4000);
    v = s.valueAt(1:4000, Commit = false);
    B = s.BlockSize;
    seam = B:B:numel(v)-1;
    assert(~any(v(seam) == v(seam+1)), 'a value repeated across a block boundary');
    fprintf('PASS: 5. MaxConsecutive and NoRepeatAcrossBlocks are honoured\n');
catch ME
    failures{end+1} = sprintf('5. constraints: %s', ME.message);
    fprintf('FAIL: 5. %s\n', ME.message);
end

% 6. Unsatisfiable configurations throw at configure time ------------------
try
    assertThrows(@() mkValidate(3, 'MaxConsecutive', 1), ...
        'epsych:BlockSequence:UnsatisfiableConstraints', 'single value + run cap');
    assertThrows(@() mkValidate([1 2], 'Repeats', [5 1], 'MaxConsecutive', 1), ...
        'epsych:BlockSequence:UnsatisfiableConstraints', '5 copies cannot be separated');
    assertThrows(@() mkValidate([1 2 3], 'Repeats', [1 2]), ...
        'epsych:BlockSequence:RepeatsMismatch', 'Repeats length mismatch');
    fprintf('PASS: 6. unsatisfiable configurations throw rather than degrade\n');
catch ME
    failures{end+1} = sprintf('6. unsatisfiable: %s', ME.message);
    fprintf('FAIL: 6. %s\n', ME.message);
end

% 7. Exhaustion policies ---------------------------------------------------
try
    s = epsych.BlockSequence([1 2 3 4], Seed = 9, MinLength = 100, Exhaustion = "error");
    L = s.Length;
    assertThrows(@() s.valueAt(L+1), 'epsych:BlockSequence:IndexExceedsSequence', 'error mode');

    s = epsych.BlockSequence([1 2 3 4], Seed = 9, MinLength = 100, Exhaustion = "wrap");
    L = s.Length;
    [vw, iw] = s.valueAt(L+7, Commit = false);
    assert(isequal(vw, s.valueAt(7, Commit = false)), 'wrap did not fold onto index 7');
    assert(iw.Wrapped, 'info.Wrapped was not set');

    s = epsych.BlockSequence([1 2 3 4], Seed = 9, MinLength = 100, ChunkBlocks = 5);
    L = s.Length;
    [~, ie] = s.valueAt(L+1, Commit = false);
    assert(ie.Extended, 'info.Extended was not set');
    assert(s.Length > L, 'extend mode did not grow');
    fprintf('PASS: 7. "error", "wrap", and "extend" behave as documented\n');
catch ME
    failures{end+1} = sprintf('7. exhaustion: %s', ME.message);
    fprintf('FAIL: 7. %s\n', ME.message);
end

% 8. Index validation ------------------------------------------------------
try
    s = epsych.BlockSequence([1 2 3 4], Seed = 4);
    for bad = [0 -3 2.5]
        assertThrows(@() s.valueAt(bad), 'epsych:BlockSequence:InvalidIndex', ...
            sprintf('index %g', bad));
    end
    assertThrows(@() s.valueAt(1e9), 'epsych:BlockSequence:LengthLimit', 'huge index');
    fprintf('PASS: 8. bad indices are refused rather than clamped or rounded\n');
catch ME
    failures{end+1} = sprintf('8. index validation: %s', ME.message);
    fprintf('FAIL: 8. %s\n', ME.message);
end

% 9. Jitter is baked, quantized, and clamped -------------------------------
try
    base = [500 1000 1500];
    s = epsych.BlockSequence(base, Jitter = 50, JitterQuantum = 1, Seed = 17);
    v = s.valueAt(1:200, Commit = false);
    assert(all(mod(v, 1) == 0), 'JitterQuantum = 1 did not produce whole numbers');
    assert(all(min(abs(v(:) - base), [], 2) <= 50), 'a value fell outside +/-50');
    assert(~all(ismember(v, base)), 'jitter produced no variation');
    assert(isequal(v, s.valueAt(1:200, Commit = false)), 'jitter was redrawn on re-read');

    s = epsych.BlockSequence([500 1000], Jitter = 200, ValueLimits = [600 Inf], Seed = 18);
    assert(min(s.valueAt(1:400, Commit = false)) >= 600, 'ValueLimits was not applied');
    fprintf('PASS: 9. jitter is baked at generation, quantized, and clamped\n');
catch ME
    failures{end+1} = sprintf('9. jitter: %s', ME.message);
    fprintf('FAIL: 9. %s\n', ME.message);
end

% 10. String and cell value lists ------------------------------------------
try
    s = epsych.BlockSequence(["tone" "noise" "am"], MaxConsecutive = 2, Seed = 21);
    v = s.valueAt(1:300, Commit = false);
    assert(isstring(v), 'a string pool did not return strings');
    for b = 1:100
        assert(numel(unique(v((b-1)*3 + (1:3)))) == 3, 'string block %d is unbalanced', b);
    end
    assert(longestRun(double(categorical(v))) <= 2, 'MaxConsecutive ignored for strings');

    c = epsych.BlockSequence({'a.wav', 'b.wav', 'c.wav'}, Seed = 22);
    vc = c.valueAt(1:30, Commit = false);
    assert(iscellstr(vc), 'a cell pool did not return a cellstr');

    assertThrows(@() mkValidate(["a" "b"], 'Jitter', 5), ...
        'epsych:BlockSequence:JitterRequiresNumeric', 'jitter on a string pool');
    fprintf('PASS: 10. string and cellstr pools block-randomize identically\n');
catch ME
    failures{end+1} = sprintf('10. non-numeric values: %s', ME.message);
    fprintf('FAIL: 10. %s\n', ME.message);
end

% 11. Mid-session edit, same length ----------------------------------------
try
    s = epsych.BlockSequence([500 1000 1500 2000], Seed = 31);
    v40 = s.valueAt(1:40);                       % committed
    ord = s.indexAt(41:80);
    s.Values = [600 1100 1600 2100];
    assert(isequal(s.valueAt(1:40, Commit = false), v40), ...
        'delivered values changed after a same-length edit');
    assert(isequal(s.indexAt(41:80), ord), 'a same-length edit disturbed the ordering');
    v = s.valueAt(41:80, Commit = false);
    assert(all(ismember(v, [600 1100 1600 2100])), 'the tail did not take the new values');
    fprintf('PASS: 11. a same-length edit remaps in place and keeps the prefix\n');
catch ME
    failures{end+1} = sprintf('11. same-length edit: %s', ME.message);
    fprintf('FAIL: 11. %s\n', ME.message);
end

% 12. Mid-session edit, different length -----------------------------------
try
    s = epsych.BlockSequence([1 2 3 4], Seed = 33);
    v40 = s.valueAt(1:40);
    s.Values = [1 2 3 4 5];
    assert(isequal(s.valueAt(1:40, Commit = false), v40), ...
        'delivered values changed after a length-changing edit');
    assert(s.BlockSize == 5, 'BlockSize did not follow the new list');
    for b = 1:20
        blk = s.indexAt(40 + (b-1)*5 + (1:5));
        assert(isequal(sort(blk), 1:5), 'block %d after the splice is unbalanced', b);
    end
    fprintf('PASS: 12. the splice lands on a block boundary and rebalances\n');
catch ME
    failures{end+1} = sprintf('12. length-changing edit: %s', ME.message);
    fprintf('FAIL: 12. %s\n', ME.message);
end

% 13. Seed change mid-session ----------------------------------------------
try
    s = epsych.BlockSequence([1 2 3 4 5 6], Seed = 41);
    v40 = s.valueAt(1:40);
    tail = s.valueAt(41:140, Commit = false);
    s.Seed = 4242;
    assert(s.Seed == 4242, 'Seed did not read back the new value');
    assert(isequal(s.valueAt(1:40, Commit = false), v40), 'a reseed disturbed the prefix');
    assert(~isequal(s.valueAt(41:140, Commit = false), tail), 'a reseed left the tail unchanged');
    fprintf('PASS: 13. a mid-session reseed keeps the prefix and redraws the tail\n');
catch ME
    failures{end+1} = sprintf('13. seed change: %s', ME.message);
    fprintf('FAIL: 13. %s\n', ME.message);
end

% 14. Shuffled seeds -------------------------------------------------------
try
    a = epsych.BlockSequence([1 2 3 4 5]);
    b = epsych.BlockSequence([1 2 3 4 5]);
    assert(a.Seed >= 0 && mod(a.Seed, 1) == 0, 'Seed did not resolve to a whole number');
    assert(a.Seed ~= b.Seed, 'two shuffled sequences drew the same seed');
    va = a.valueAt(1:200, Commit = false);
    assert(~isequal(va, b.valueAt(1:200, Commit = false)), 'two shuffled sequences agree');
    c = epsych.BlockSequence([1 2 3 4 5], Seed = a.Seed);
    assert(isequal(va, c.valueAt(1:200, Commit = false)), ...
        'the reported seed does not reproduce the sequence');
    fprintf('PASS: 14. a shuffled seed is reported and reproduces the sequence\n');
catch ME
    failures{end+1} = sprintf('14. shuffle: %s', ME.message);
    fprintf('FAIL: 14. %s\n', ME.message);
end

% 15. Struct round trip ----------------------------------------------------
try
    s = epsych.BlockSequence([2 4 6 8], Repeats = [1 1 2 1], Seed = 99, ...
        MaxConsecutive = 3, Jitter = 1, Label = "ITI");
    v = s.valueAt(1:500, Commit = false);
    r = epsych.BlockSequence.fromStruct(s.toStruct());
    assert(r.Seed == s.Seed, 'Seed did not round trip');
    assert(isequal(r.valueAt(1:500, Commit = false), v), 'values did not round trip');

    s.valueAt(1:40);
    s.Repeats = 1;                               % edited as a set, validated lazily
    s.Values  = [2 4 6 8 10];
    r = epsych.BlockSequence.fromStruct(s.toStruct());
    assert(isequal(r.valueAt(1:40, Commit = false), s.valueAt(1:40, Commit = false)), ...
        'the frozen prefix did not round trip');

    d = epsych.BlockSequence.fromStruct(struct('junk', 1));
    assert(isa(d, 'epsych.BlockSequence') && isempty(d.Values), ...
        'fromStruct did not degrade to a default object');

    cfg = s.toStruct(IncludeSequence = false);
    assert(~isfield(cfg, 'SequenceIndex'), 'IncludeSequence = false still stored the sequence');
    fprintf('PASS: 15. toStruct/fromStruct round trips values, seed, and prefix\n');
catch ME
    failures{end+1} = sprintf('15. struct round trip: %s', ME.message);
    fprintf('FAIL: 15. %s\n', ME.message);
end

% 16. Inspection never commits ---------------------------------------------
try
    s = epsych.BlockSequence([1 2 3 4], Seed = 55);
    s.preview(1, 50);
    s.indexAt(1:50);
    s.blockAt(1:50);
    s.tally(20);
    assert(s.CommittedThrough == 0, 'an inspection advanced CommittedThrough');
    s.valueAt(1:12);
    assert(s.CommittedThrough == 12, 'valueAt did not commit');
    s.setCommitted(4);
    assert(s.CommittedThrough == 4, 'setCommitted did not rewind the mark');
    n = s.tally(12);
    assert(sum(n) == 12, 'tally did not count every index');
    fprintf('PASS: 16. preview/indexAt/blockAt/tally leave CommittedThrough alone\n');
catch ME
    failures{end+1} = sprintf('16. commit policy: %s', ME.message);
    fprintf('FAIL: 16. %s\n', ME.message);
end

% 17. A zero repeat drops the value ----------------------------------------
try
    s = epsych.BlockSequence([1 2 3], Repeats = [1 0 2], Seed = 61, MinLength = 2000);
    v = s.valueAt(1:2000, Commit = false);
    assert(~any(v == 2), 'a value with Repeats = 0 still appeared');
    assert(s.BlockSize == 3, 'BlockSize should be 3, got %d', s.BlockSize);
    fprintf('PASS: 17. Repeats = 0 drops a value without editing the list\n');
catch ME
    failures{end+1} = sprintf('17. zero repeat: %s', ME.message);
    fprintf('FAIL: 17. %s\n', ME.message);
end

% 18. Empty value list ------------------------------------------------------
try
    s = epsych.BlockSequence();
    assert(s.Length == 0, 'an empty sequence reported a length');
    assert(~s.IsValid, 'an empty sequence reported itself valid');
    assertThrows(@() s.valueAt(1), 'epsych:BlockSequence:NoValues', 'empty pool');
    d = describe(s);
    assert(contains(d, 'empty'), 'describe did not say the sequence is empty');
    fprintf('PASS: 18. an empty value list constructs and throws only on use\n');
catch ME
    failures{end+1} = sprintf('18. empty values: %s', ME.message);
    fprintf('FAIL: 18. %s\n', ME.message);
end

% 19. The rejection loop stays cheap ---------------------------------------
try
    t = tic;
    s = epsych.BlockSequence([1 2 3 4], MaxConsecutive = 2, Seed = 77, MinLength = 10000);
    s.valueAt(1:10000, Commit = false);
    el = toc(t);
    assert(el < 5, 'generating 10000 constrained elements took %.2f s', el);
    fprintf('PASS: 19. 10000 constrained elements generated in %.2f s\n', el);
catch ME
    failures{end+1} = sprintf('19. performance: %s', ME.message);
    fprintf('FAIL: 19. %s\n', ME.message);
end

% -------------------------------------------------------------------------
if isempty(failures)
    fprintf('\nsmoke_test_blocksequence: ALL PASS\n');
else
    fprintf('\nsmoke_test_blocksequence: %d FAILURE(S)\n', numel(failures));
    fprintf('  - %s\n', failures{:});
    error('smoke_test_blocksequence:failed', '%d failure(s)', numel(failures));
end
end

% -------------------------------------------------------------------------
function m = longestRun(x)
% Longest run of one value in a vector, for verifying MaxConsecutive.
x = x(:).';
if isempty(x), m = 0; return; end
st = [true, x(2:end) ~= x(1:end-1)];
m = max(diff([find(st), numel(x) + 1]));
end

function assertThrows(fcn, identifier, what)
% Assert that fcn throws a specific error identifier.
try
    fcn();
catch ME
    assert(strcmp(ME.identifier, identifier), ...
        '%s threw %s, expected %s', what, ME.identifier, identifier);
    return
end
error('%s did not throw %s', what, identifier);
end

function mkValidate(values, varargin)
% Construct and validate in one call, so a constructor can be wrapped in an
% anonymous function for assertThrows.
s = epsych.BlockSequence(values, varargin{:});
s.validate();
end
