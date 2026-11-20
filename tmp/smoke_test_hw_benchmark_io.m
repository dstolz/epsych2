% smoke_test_hw_benchmark_io.m
% Headless standing proof for hw.benchmarkIO and the two hw.Interface hooks
% it relies on (parameterCapacity, isSimulated).
%
% Everything runs in memory: hw.Software, tmp/BenchLoopbackInterface (an
% hw.Software that keeps what it is written), and -- for the offline hook
% checks only -- an hw.TDT_RPcox and an hw.TDT_Synapse constructed with
% Connect=false, plus hw.TDT_Synapse over tmp/SynapseAPI_Mock. No device,
% COM server, serial port or network socket is opened. The one figure is
% created with DefaultFigureVisible 'off', so no window appears.
%
% Groups:
%    1  hook defaults on the base class and the offline backends
%    2  hw.TDT_Synapse.parameterCapacity over the mock
%    3  role discovery by default names
%    4  explicit role options override discovery
%    5  explicit-missing errors; discovered-missing is unsupported
%    6  nothing measurable errors and states the contract
%    7  disconnected non-simulated interfaces are refused
%    8  parameterCapacity used when known; then BufferSizes, name, read
%    9  round-trip verification passes, and catches a corrupted read
%   10  linear fit recovers known overhead and per-sample cost
%   11  Software floor comparison and the softwareTwin command
%   12  SaveTo writes files that reload; the temporary folder is removed
%   13  Plot with figures invisible
%   14  no backend class name in hw.benchmarkIO
%   15  one Buf tag timed at several Sizes; capacity caps them; floor follows
%   (progress logging is checked in group 3; the other groups run with it off)
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_hw_benchmark_io.m')"

if exist('hw.benchmarkIO', 'file') ~= 2 || exist('BenchLoopbackInterface', 'file') ~= 2
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end

fprintf('\n=== hw.benchmarkIO Smoke Test ===\n\n');
results = {};
[I, lb, lbF, lbX, rpc, syn, sw, bp, rp] = deal([]);
quick = {'Repeats', 5, 'Warmup', 1, 'Plot', false, 'CompareToSoftware', false, 'Progress', false};
noScalars = {'ScalarWrite', [], 'ScalarRead', [], 'Trigger', []};

%% 1. Hook defaults
try
    sw = hw.Software();
    px = sw.add_parameter('X', 0);
    results(end+1,:) = check('1  hw.Software reports isSimulated', sw.isSimulated());
    results(end+1,:) = check('1  hw.Software parameterCapacity is NaN (base default)', ...
        isnan(sw.parameterCapacity(px)));

    bp = BatchProbeInterface();
    py = bp.add_parameter('Y', 0);
    results(end+1,:) = check('1  base default isSimulated is false', ~bp.isSimulated());
    results(end+1,:) = check('1  base default parameterCapacity is NaN', isnan(bp.parameterCapacity(py)));

    rp = hw.Replay();
    results(end+1,:) = check('1  hw.Replay reports isSimulated', rp.isSimulated());

    rpc = hw.TDT_RPcox({}, {}, {}, Interface='GB', Connect=false);
    Mr = hw.Module(rpc, 'RZ6', 'RZ6', uint8(1));
    pr = Mr.add_parameter('Buf_1024', 0, Type='Buffer', isArray=true);
    results(end+1,:) = check('1  TDT_RPcox offline: capacity NaN, no circuit loaded', ...
        isnan(rpc.parameterCapacity(pr)));
    results(end+1,:) = check('1  TDT_RPcox is not simulated', ~rpc.isSimulated());

    syn = hw.TDT_Synapse('localhost', Connect=false);
    Ms = hw.Module(syn, 'RZ6(1)', 'RZ6', uint8(1));
    ps = Ms.add_parameter('Stim', 0, Type='Buffer', isArray=true);
    results(end+1,:) = check('1  TDT_Synapse offline: capacity NaN, nothing cached', ...
        isnan(syn.parameterCapacity(ps)));
    results(end+1,:) = check('1  TDT_Synapse is not simulated', ~syn.isSimulated());
catch ME
    results(end+1,:) = check(sprintf('1  hook defaults threw: %s', ME.message), false);
end

%% 2. Synapse override over the mock
try
    api = SynapseAPI_Mock();
    I = TDT_Synapse_Mock(api, Connect=true);
    Ps = I.find_parameter('Stim');
    gizmo = char(I.Module(1).Info.SynapseName);
    expected = api.getParameterSize(gizmo, 'Stim');
    results(end+1,:) = check(sprintf('2  Synapse capacity of Stim is the server''s size (%d)', expected), ...
        expected > 1 && I.parameterCapacity(Ps) == expected);
    results(end+1,:) = check('2  asking again gives the same answer (cached)', ...
        I.parameterCapacity(Ps) == expected);
catch ME
    results(end+1,:) = check(sprintf('2  Synapse mock threw: %s', ME.message), false);
end

%% 3. Discovery by default names
try
    lb = makeLoopback();
    lb.put('RScalar', 3);
    R = hw.benchmarkIO(lb, quick{:});

    roles = sort(R.Contract.Role);
    results(end+1,:) = check('3  every role discovered', ...
        isequal(roles, sort(["ScalarWrite"; "ScalarRead"; "Trigger"; "Buffers"; "Buffers"])));
    results(end+1,:) = check('3  discovered by default name', ...
        R.Contract.Parameter(R.Contract.Role == "ScalarWrite") == "WScalar" && ...
        all(R.Contract.Source == "discovered"));
    results(end+1,:) = check('3  nothing unsupported, nothing failed', ...
        isempty(R.Unsupported) && isempty(R.Problems));
    % 3 scalar roles + 2 buffers x (write, read), each by param and by name
    results(end+1,:) = check('3  Repeats kept per block, warm-up discarded', ...
        height(R.Raw) == 14 * 5 && all(R.Summary.Iterations == 5));
    results(end+1,:) = check('3  both paths timed', ...
        isequal(sort(unique(R.Raw.Path)), ["name"; "param"]));
    % Progress reaches the console; Progress=false is silent.
    said = evalc('hw.benchmarkIO(lb, quick{:}, Repeats=2, Progress=true);');
    quiet = evalc('hw.benchmarkIO(lb, quick{:}, Repeats=2, Progress=false);');
    results(end+1,:) = check('3  progress is logged per measurement, and Progress=false silences it', ...
        contains(said, "[1/14]") && contains(said, "[14/14]") && contains(said, "round trip:") && ...
        ~contains(quiet, "hw.benchmarkIO"));
    m = R.Raw.Role == "BufferRead" & R.Raw.Parameter == "Buf_4096";
    results(end+1,:) = check('3  buffer sized from its name; read length recorded', ...
        all(R.Raw.NRequested(m) == 4096) && all(R.Raw.NTransferred(m) == 4096));
    results(end+1,:) = check('3  environment recorded', ...
        strcmp(R.Environment.BackendClass, 'BenchLoopbackInterface') && ...
        isfield(R.Environment, 'GLogVerbosity') && isfield(R.Environment, 'EPsychCommit') && ...
        R.Environment.TicTocOverhead_s >= 0);

    lbT = BenchLoopbackInterface();
    lbT.add_parameter('!BenchTrig', 0, isTrigger=true);
    RT = hw.benchmarkIO(lbT, quick{:}, VerifyRoundTrip=false);
    results(end+1,:) = check('3  !BenchTrig (the RPvds trigger spelling) is discovered', ...
        any(RT.Contract.Role == "Trigger" & RT.Contract.Parameter == "!BenchTrig"));

    lbU = BenchLoopbackInterface();
    lbU.add_parameter('WScalar', 0);
    lbU.add_parameter('BenchTrig', 0);
    RU = hw.benchmarkIO(lbU, quick{:});
    results(end+1,:) = check('3  a BenchTrig not flagged as a trigger is unsupported, with why', ...
        any(RU.Unsupported.Role == "Trigger" & contains(RU.Unsupported.Reason, "not flagged")));
catch ME
    results(end+1,:) = check(sprintf('3  discovery threw: %s', ME.message), false);
end

%% 4. Explicit options override discovery
try
    lb = makeLoopback();
    lb.add_parameter('OtherW', 0);
    pRead = lb.find_parameter('RScalar', includeInvisible=true);
    R = hw.benchmarkIO(lb, quick{:}, ScalarWrite="OtherW", ScalarRead=pRead, ...
        Trigger=[], Buffers="Buf_4096");

    c = R.Contract;
    results(end+1,:) = check('4  ScalarWrite by name overrides WScalar', ...
        c.Parameter(c.Role == "ScalarWrite") == "OtherW" && c.Source(c.Role == "ScalarWrite") == "explicit");
    results(end+1,:) = check('4  ScalarRead by hw.Parameter handle', ...
        c.Parameter(c.Role == "ScalarRead") == "RScalar" && c.Source(c.Role == "ScalarRead") == "explicit");
    results(end+1,:) = check('4  Buffers limited to the one named', ...
        isequal(c.Parameter(c.Role == "Buffers"), "Buf_4096"));
    results(end+1,:) = check('4  an empty role option skips the role', ...
        any(R.Unsupported.Role == "Trigger" & R.Unsupported.Reason == "skipped by the caller") && ...
        ~any(R.Raw.Role == "Trigger"));

    R2 = hw.benchmarkIO(lb, quick{:}, IncludeLookup=false);
    results(end+1,:) = check('4  IncludeLookup=false times the parameter path only', ...
        all(R2.Raw.Path == "param"));
catch ME
    results(end+1,:) = check(sprintf('4  explicit options threw: %s', ME.message), false);
end

%% 5. Missing roles: explicit errors, discovered is unsupported
lb = makeLoopback();
results(end+1,:) = expectError('5  explicit missing ScalarWrite errors, naming it', ...
    @() hw.benchmarkIO(lb, quick{:}, ScalarWrite="NoSuch"), ...
    'hw:benchmarkIO:RoleNotFound', {'NoSuch', 'ScalarWrite'});
results(end+1,:) = expectError('5  explicit missing buffer errors, naming it', ...
    @() hw.benchmarkIO(lb, quick{:}, Buffers=["Buf_1024", "NoBuf"]), ...
    'hw:benchmarkIO:RoleNotFound', {'NoBuf', 'Buffers'});
results(end+1,:) = expectError('5  an explicit role the parameter cannot fill errors', ...
    @() hw.benchmarkIO(lb, quick{:}, Trigger="WScalar"), ...
    'hw:benchmarkIO:RoleRequirement', {'WScalar', 'Trigger'});
other = makeLoopback();
pOther = other.find_parameter('WScalar');
results(end+1,:) = expectError('5  a parameter from another interface is refused', ...
    @() hw.benchmarkIO(lb, quick{:}, ScalarWrite=pOther), ...
    'hw:benchmarkIO:RoleNotFound', {'ScalarWrite'});
try
    lbNoTrig = BenchLoopbackInterface();
    lbNoTrig.add_parameter('WScalar', 0);
    lbNoTrig.add_parameter('Buf_1024', 0, Type='Buffer', isArray=true);
    R = hw.benchmarkIO(lbNoTrig, quick{:});
    results(end+1,:) = check('5  discovered-missing roles are unsupported, not errors', ...
        all(ismember(["ScalarRead", "Trigger"], R.Unsupported.Role)) && ...
        ~any(ismember(R.Raw.Role, ["ScalarRead", "Trigger"])) && any(R.Raw.Role == "ScalarWrite"));
catch ME
    results(end+1,:) = check(sprintf('5  discovered-missing threw: %s', ME.message), false);
end

%% 6. Nothing measurable
empty = hw.Software();
empty.add_parameter('Unrelated', 0);
results(end+1,:) = expectError('6  nothing measurable errors and states the contract', ...
    @() hw.benchmarkIO(empty, quick{:}), ...
    'hw:benchmarkIO:NothingToMeasure', {'WScalar', 'RScalar', 'BenchTrig', 'Buf_<N>'});

%% 7. Disconnected interfaces
lbX = makeLoopback(Simulated=false);
lbX.disconnect();
results(end+1,:) = expectError('7  a disconnected non-simulated interface is refused', ...
    @() hw.benchmarkIO(lbX, quick{:}), 'hw:benchmarkIO:NotConnected', {'not connected'});
try
    rpc2 = hw.TDT_RPcox({}, {}, {}, Interface='GB', Connect=false);
    results(end+1,:) = expectError('7  a TDT_RPcox never connected is refused (no COM touched)', ...
        @() hw.benchmarkIO(rpc2, quick{:}), 'hw:benchmarkIO:NotConnected', {});
catch ME
    results(end+1,:) = check(sprintf('7  RPcox construction threw: %s', ME.message), false);
end
try
    lbS = makeLoopback(Simulated=true);
    lbS.disconnect();
    R = hw.benchmarkIO(lbS, quick{:});
    results(end+1,:) = check('7  a disconnected simulated interface still runs', ...
        ~isempty(R.Raw) && R.Environment.IsSimulated && ~R.Environment.IsConnected);
catch ME
    results(end+1,:) = check(sprintf('7  disconnected simulated threw: %s', ME.message), false);
end

%% 8. Buffer sizing: capacity, then BufferSizes, name, read
try
    lbC = BenchLoopbackInterface();
    lbC.add_parameter('BigBuf', 0, Type='Buffer', isArray=true);
    lbC.add_parameter('Buf_1024', 0, Type='Buffer', isArray=true);
    lbC.add_parameter('DeclBuf', 0, Type='Buffer', isArray=true);
    lbC.add_parameter('ReadBuf', 0, Type='Buffer', isArray=true);
    lbC.Capacities.BigBuf = 3000;
    lbC.Capacities.Buf_1024 = 2048;      % the device outranks the name
    lbC.put('ReadBuf', zeros(1, 777, 'single'));

    R = hw.benchmarkIO(lbC, quick{:}, noScalars{:}, ...
        Buffers=["BigBuf", "Buf_1024", "DeclBuf", "ReadBuf"], BufferSizes=[NaN NaN 500 NaN]);
    c = R.Contract;
    sz = @(name) c.N(c.Parameter == name);
    src = @(name) c.SizeSource(c.Parameter == name);
    results(end+1,:) = check('8  parameterCapacity used when known', ...
        sz("BigBuf") == 3000 && src("BigBuf") == "parameterCapacity" && c.Capacity(c.Parameter == "BigBuf") == 3000);
    results(end+1,:) = check('8  capacity outranks the size in the name, and says so', ...
        sz("Buf_1024") == 2048 && strlength(c.Note(c.Parameter == "Buf_1024")) > 0);
    results(end+1,:) = check('8  NaN capacity falls back to the declared size', ...
        sz("DeclBuf") == 500 && src("DeclBuf") == "BufferSizes");
    results(end+1,:) = check('8  then to the length a read returns', ...
        sz("ReadBuf") == 777 && src("ReadBuf") == "read");
    m = R.Raw.Role == "BufferWrite" & R.Raw.Parameter == "BigBuf";
    results(end+1,:) = check('8  writes are made at that size', ...
        all(R.Raw.NRequested(m) == 3000) && all(R.Raw.NTransferred(m) == 3000));
    results(end+1,:) = expectError('8  BufferSizes must align with Buffers', ...
        @() hw.benchmarkIO(lbC, quick{:}, noScalars{:}, Buffers="BigBuf", BufferSizes=[1 2]), ...
        'hw:benchmarkIO:BufferSizesMismatch', {});
catch ME
    results(end+1,:) = check(sprintf('8  sizing threw: %s', ME.message), false);
end

%% 9. Round trip
try
    lb = makeLoopback();
    R = hw.benchmarkIO(lb, quick{:}, noScalars{:});
    results(end+1,:) = check('9  round trip passes on every readable buffer', ...
        height(R.RoundTrip) == 2 && all(R.RoundTrip.Pass) && all(R.RoundTrip.MaxAbsError == 0) && ...
        all(R.RoundTrip.NRead == R.RoundTrip.NWritten));

    lb.CorruptReads = true;
    R = hw.benchmarkIO(lb, quick{:}, noScalars{:});
    results(end+1,:) = check('9  a corrupted read is a failed result, not an exception', ...
        height(R.RoundTrip) == 2 && ~any(R.RoundTrip.Pass) && all(R.RoundTrip.MaxAbsError > 0));

    lbW = BenchLoopbackInterface();
    lbW.add_parameter('Buf_1024', 0, Type='Buffer', isArray=true, Access='Write');
    R = hw.benchmarkIO(lbW, quick{:}, noScalars{:});
    results(end+1,:) = check('9  a write-only buffer: write timed, read unsupported, not verified', ...
        any(R.Raw.Role == "BufferWrite") && ~any(R.Raw.Role == "BufferRead") && ...
        any(R.Unsupported.Role == "BufferRead") && isempty(R.RoundTrip));

    R = hw.benchmarkIO(makeLoopback(), quick{:}, noScalars{:}, VerifyRoundTrip=false);
    results(end+1,:) = check('9  VerifyRoundTrip=false skips verification', isempty(R.RoundTrip));
catch ME
    results(end+1,:) = check(sprintf('9  round trip threw: %s', ME.message), false);
end

%% 10. Linear fit
try
    a = 2e-3;
    b = 4e-8;
    T = 292969;
    N = [1024 16384 131072 300000 600000];
    f = hw.benchmarkIO("fit", N, a + b * N, TargetSamples=T);
    results(end+1,:) = check('10 exact synthetic timings: overhead and per-sample cost recovered', ...
        abs(f.Overhead_s - a) < 1e-12 && abs(f.PerSample_s - b) / b < 1e-9 && abs(f.RSquared - 1) < 1e-12);
    results(end+1,:) = check('10 prediction for TargetSamples and for two buffers', ...
        abs(f.Predicted_s - (a + b * T)) < 1e-12 && f.PredictedTwoBuffers_s == 2 * f.Predicted_s && ...
        ~f.Extrapolated);

    noise = 1 + 0.01 * [1 -1 1 -1 1];
    f = hw.benchmarkIO("fit", N, (a + b * N) .* noise, TargetSamples=T);
    results(end+1,:) = check('10 1% noise: recovered within 5%', ...
        abs(f.Overhead_s - a) / a < 0.05 && abs(f.PerSample_s - b) / b < 0.05);

    f = hw.benchmarkIO("fit", [4096 4096], [1 2], TargetSamples=T);
    results(end+1,:) = check('10 one size cannot separate the two terms: NaN, with why', ...
        isnan(f.Overhead_s) && isnan(f.PerSample_s) && strlength(f.Note) > 0);

    f = hw.benchmarkIO("fit", [1024 16384], a + b * [1024 16384], TargetSamples=T);
    results(end+1,:) = check('10 a target beyond the sizes measured is flagged extrapolated', f.Extrapolated);

    % End to end: a backend whose writes cost a known a + b*N.
    lbD = BenchLoopbackInterface();
    for n = [1024 16384 131072]
        lbD.add_parameter(sprintf('Buf_%d', n), 0, Type='Buffer', isArray=true);
    end
    lbD.DelayModel = [1e-3 2e-8];
    R = hw.benchmarkIO(lbD, noScalars{:}, Repeats=7, Warmup=1, IncludeLookup=false, ...
        VerifyRoundTrip=false, Plot=false, CompareToSoftware=false);
    F = R.Fit(R.Fit.Role == "BufferWrite" & R.Fit.Path == "param", :);
    results(end+1,:) = check(sprintf(['10 end to end: busy-wait 1 ms + 20 ns/sample recovered ' ...
        '(got %.3g ms + %.3g ns/sample)'], 1e3 * F.Overhead_s, 1e9 * F.PerSample_s), ...
        height(F) == 1 && abs(F.PerSample_s - 2e-8) / 2e-8 < 0.25 && abs(F.Overhead_s - 1e-3) < 0.5e-3);
catch ME
    results(end+1,:) = check(sprintf('10 fit threw: %s', ME.message), false);
end

%% 11. Software floor
try
    lbF = makeLoopback(Simulated=false);
    R = hw.benchmarkIO(lbF, Repeats=5, Warmup=1, Plot=false, CompareToSoftware=true);
    results(end+1,:) = check('11 a floor row for every summary row', ...
        height(R.Floor) == height(R.Summary) && all(isfinite(R.Floor.Floor_s)));
    results(end+1,:) = check('11 AboveFloor = backend - floor', ...
        max(abs(R.Floor.AboveFloor_s - (R.Floor.Backend_s - R.Floor.Floor_s))) == 0);
    results(end+1,:) = check('11 the twin ran on hw.Software with the same contract', ...
        isstruct(R.Software) && strcmp(R.Software.Environment.BackendClass, 'hw.Software') && ...
        isequal(sort(R.Software.Contract.Parameter), sort(R.Contract.Parameter)) && ...
        isequal(R.Software.Contract.N, R.Contract.N));

    R = hw.benchmarkIO(makeLoopback(), Repeats=5, Warmup=1, Plot=false, CompareToSoftware=true);
    results(end+1,:) = check('11 skipped on an interface that is itself simulated', ...
        isempty(R.Floor) && isempty(R.Software));

    twin = hw.benchmarkIO("softwareTwin", lbF);
    tp = twin.all_parameters(includeInvisible=true, includeTriggers=true);
    results(end+1,:) = check('11 softwareTwin is an hw.Software mirroring the contract', ...
        isa(twin, 'hw.Software') && ...
        isequal(sort(string({tp.Name})), sort(["WScalar", "RScalar", "BenchTrig", "Buf_1024", "Buf_4096"])));
    q = @(n) tp(strcmp({tp.Name}, n));
    results(end+1,:) = check('11 twin parameters keep trigger flag, access and type', ...
        q('BenchTrig').isTrigger && strcmp(q('RScalar').Access, 'Read') && strcmp(q('Buf_1024').Type, 'Buffer'));
    delete(twin)
catch ME
    results(end+1,:) = check(sprintf('11 floor threw: %s', ME.message), false);
end

%% 12. SaveTo
% An existing folder (or a path ending in a separator) is a folder; any
% other path is a file stem.
saveDir = tempname;
mkdir(saveDir);
try
    R = hw.benchmarkIO(makeLoopback(), Repeats=3, Warmup=0, Plot=false, ...
        CompareToSoftware=false, SaveTo=saveDir);
    results(end+1,:) = check('12 .mat, .csv and _summary.csv written into the folder', ...
        isfile(R.Files.Mat) && isfile(R.Files.Csv) && isfile(R.Files.SummaryCsv) && ...
        startsWith(R.Files.Mat, saveDir));
    L = load(R.Files.Mat);
    results(end+1,:) = check('12 the .mat reloads with the same raw and summary', ...
        isequal(L.results.Raw.Seconds, R.Raw.Seconds) && isequal(L.results.Summary.Median_s, R.Summary.Median_s));
    C = readtable(R.Files.Csv);
    results(end+1,:) = check('12 the .csv reloads with every raw row', ...
        height(C) == height(R.Raw) && max(abs(C.Seconds - R.Raw.Seconds)) < 1e-12);

    R = hw.benchmarkIO(makeLoopback(), Repeats=3, Warmup=0, Plot=false, ...
        CompareToSoftware=false, SaveTo=fullfile(saveDir, 'named.mat'));
    results(end+1,:) = check('12 a file stem names the files', ...
        isfile(fullfile(saveDir, 'named.mat')) && isfile(fullfile(saveDir, 'named.csv')));
catch ME
    results(end+1,:) = check(sprintf('12 SaveTo threw: %s', ME.message), false);
end
if isfolder(saveDir)
    rmdir(saveDir, 's');
end
results(end+1,:) = check('12 temporary folder removed', ~isfolder(saveDir));

%% 13. Plot, figures invisible
oldVisible = get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');
try
    R = hw.benchmarkIO(makeLoopback(), Repeats=3, Warmup=0, Plot=true, CompareToSoftware=false);
    results(end+1,:) = check('13 a figure is drawn and stays invisible', ...
        isgraphics(R.Figure) && R.Figure.Visible == "off");
    axs = findobj(R.Figure, 'Type', 'axes');
    sub = arrayfun(@(a) string(strjoin(string(a.Subtitle.String), " ")), axs);
    results(end+1,:) = check('13 four panels, the lookup-cost one explained in its subtitle', ...
        numel(axs) == 4 && any(contains(sub, "find_parameter")) && any(contains(sub, "By handle")));
    results(end+1,:) = check('13 a throughput panel states how the bit rate is computed', ...
        any(contains(sub, "32 bits x samples moved")));
    leg = findobj(R.Figure, 'Type', 'legend');
    legNames = strings(0, 1);
    for l = leg(:)'
        legNames = [legNames; string(l.String(:))];
    end
    results(end+1,:) = check('13 legends name the call path in words, and TX/RX in the throughput panel', ...
        any(contains(legNames, "by handle")) && any(contains(legNames, "by name")) && ...
        any(contains(legNames, "TX")) && any(contains(legNames, "RX")));
    delete(R.Figure)

    R = hw.benchmarkIO(makeLoopback(), noScalars{:}, Repeats=3, Warmup=0, Plot=true, CompareToSoftware=false);
    results(end+1,:) = check('13 a buffers-only run plots too', isgraphics(R.Figure));
    delete(R.Figure)

    R = hw.benchmarkIO(makeLoopback(), Repeats=3, Warmup=0, Plot=true, IncludeLookup=false, CompareToSoftware=false);
    txts = findobj(R.Figure, 'Type', 'text');
    said = any(arrayfun(@(t) contains(strjoin(string(t.String), " "), "IncludeLookup"), txts));
    results(end+1,:) = check('13 without IncludeLookup the lookup panel says so instead of failing', ...
        isgraphics(R.Figure) && said);
    delete(R.Figure)
catch ME
    results(end+1,:) = check(sprintf('13 Plot threw: %s', ME.message), false);
end
set(groot, 'DefaultFigureVisible', oldVisible);

%% 14. No backend class name in hw.benchmarkIO
src = fileread(which('hw.benchmarkIO'));
backends = {'TDT_RPcox', 'TDT_Synapse', 'Teensy', 'Bpod', 'Intan', 'NE1000', ...
    'VlcRecorder', 'Replay', 'TDTRP', 'SynapseAPI'};
results(end+1,:) = check('14 no backend class name in hw.benchmarkIO', ...
    ~any(cellfun(@(b) contains(src, b), backends)));
% hw.Parameter is the contract's own value type (a role may be given as a
% handle), not a backend, so testing for it is not interface type-sniffing.
results(end+1,:) = check('14 no isa() test against an hw backend class', ...
    isempty(regexp(src, 'isa\([^)]*''hw\.(?!Parameter'')', 'once')));

%% 15. One Buf tag timed at several Sizes
try
    lbS = BenchLoopbackInterface();
    lbS.add_parameter('Buf', 0, Type='Buffer', isArray=true);
    Rs = hw.benchmarkIO(lbS, quick{:}, noScalars{:}, Sizes=[1024 4096]);
    sz = unique(Rs.Summary.NRequested(Rs.Summary.Role == "BufferWrite"))';
    results(end+1,:) = check('15 a single Buf is discovered and timed at every size', ...
        isequal(sz, [1024 4096]) && all(Rs.Contract.Parameter == "Buf"));
    results(end+1,:) = check('15 contract has one row per size, sourced from Sizes', ...
        height(Rs.Contract) == 2 && all(Rs.Contract.SizeSource == "Sizes"));
    results(end+1,:) = check('15 each size is its own summary row (not pooled)', ...
        sum(Rs.Summary.Role == "BufferWrite" & Rs.Summary.Path == "param") == 2);
    fw = Rs.Fit(Rs.Fit.Role == "BufferWrite" & Rs.Fit.Path == "param", :);
    results(end+1,:) = check('15 the fit sees two distinct sizes', ...
        ~isempty(fw) && fw.NumSizes(1) == 2);
    results(end+1,:) = check('15 round trip checked at every size and passes', ...
        height(Rs.RoundTrip) == 2 && all(Rs.RoundTrip.Pass));

    % A device that reports a capacity caps the sizes it is asked for.
    lbC = BenchLoopbackInterface();
    lbC.add_parameter('Buf', 0, Type='Buffer', isArray=true);
    lbC.Capacities.Buf = 2048;
    Rc = hw.benchmarkIO(lbC, quick{:}, noScalars{:}, Sizes=[1024 4096]);
    results(end+1,:) = check('15 a size above the reported capacity is skipped and reported', ...
        isequal(unique(Rc.Summary.NRequested)', 1024) && ...
        any(contains(Rc.Unsupported.Reason, "4096")));

    % ... and the plot says so, rather than just missing the points.
    oldV = get(groot, 'DefaultFigureVisible');
    set(groot, 'DefaultFigureVisible', 'off');
    Rp = hw.benchmarkIO(lbC, Repeats=3, Warmup=0, Plot=true, CompareToSoftware=false, ...
        ScalarWrite=[], ScalarRead=[], Trigger=[], Sizes=[1024 4096]);
    pt = findobj(Rp.Figure, 'Type', 'text');
    noted = any(arrayfun(@(t) contains(strjoin(string(t.String), " "), "4096 (holds 2048)"), pt));
    delete(Rp.Figure)
    set(groot, 'DefaultFigureVisible', oldV);
    results(end+1,:) = check('15 the buffer plot names the skipped sizes and what the buffer holds', noted);

    % The Software floor follows the same sizes, size by size.
    lbD = BenchLoopbackInterface(Simulated=false);
    lbD.add_parameter('Buf', 0, Type='Buffer', isArray=true);
    Rf = hw.benchmarkIO(lbD, Repeats=5, Warmup=1, Plot=false, CompareToSoftware=true, ...
        ScalarWrite=[], ScalarRead=[], Trigger=[], Sizes=[1024 4096]);
    results(end+1,:) = check('15 floor rows line up with summary rows, size by size', ...
        height(Rf.Floor) == height(Rf.Summary) && all(isfinite(Rf.Floor.Floor_s)) && ...
        isequal(Rf.Floor.NRequested, Rf.Summary.NRequested));

    delete(lbS); delete(lbC); delete(lbD);
catch ME
    results(end+1,:) = check(sprintf('15 Sizes threw: %s', ME.message), false);
end

%% 17. TX / RX bit rate
try
    lbR = BenchLoopbackInterface();
    lbR.add_parameter('Buf', 0, Type='Buffer', isArray=true);
    Rb = hw.benchmarkIO(lbR, quick{:}, noScalars{:}, Sizes=[1024 4096]);
    sb = Rb.Summary(Rb.Summary.Path == "param" & startsWith(Rb.Summary.Role, "Buffer"), :);
    nMoved = sb.NRequested;
    results(end+1,:) = check('17 MbitPerSec is 32 bits x samples moved / median call time', ...
        max(abs(sb.MbitPerSec - 32 * sb.NTransferred ./ sb.Median_s / 1e6) ./ sb.MbitPerSec) < 1e-9 ...
        && all(sb.NTransferred == nMoved));
    results(end+1,:) = check('17 MbitPerSec is 8 x MBPerSec and set only on buffer rows', ...
        max(abs(sb.MbitPerSec - 8 * sb.MBPerSec)) < 1e-9 && ...
        all(isnan(Rb.Summary.MbitPerSec(~startsWith(Rb.Summary.Role, "Buffer")))));

    % A device with a known cost recovers its line speed: 20 ns/sample is a
    % 1.6 Gbit/s ceiling, and the measured rate approaches it from below.
    lbR.DelayModel = [0 2e-8];
    Rc2 = hw.benchmarkIO(lbR, quick{:}, noScalars{:}, IncludeLookup=false, Sizes=[16384 131072]);
    tx = Rc2.Summary(Rc2.Summary.Role == "BufferWrite", :);
    results(end+1,:) = check('17 TX of a 20 ns/sample device is within 10% of 1.6 Gbit/s', ...
        abs(tx.MbitPerSec(end) - 1600) / 1600 < 0.10);
    delete(lbR);
catch ME
    results(end+1,:) = check(sprintf('17 bit rate threw: %s', ME.message), false);
end

%% 16. CancelFcn stops the run between calls
try
    lbK = makeLoopback();
    setappdata(0, 'bench_polls', 0);
    try
        hw.benchmarkIO(lbK, quick{:}, Repeats=50, CancelFcn=@() stopAfter(30));
        cancelledId = '';
    catch ME
        cancelledId = ME.identifier;
    end
    results(end+1,:) = check('16 a true CancelFcn ends the run with hw:benchmarkIO:Cancelled', ...
        strcmp(cancelledId, 'hw:benchmarkIO:Cancelled'));
    results(end+1,:) = check('16 it is polled between calls, so the stop is prompt (31 polls)', ...
        getappdata(0, 'bench_polls') == 31);

    % A flag set by a callback that only runs at drawnow (as the Stop button's
    % does): the CancelFcn must yield for it to be seen.
    assignin('base', 'bench_stop_flag', false);
    tm = timer(StartDelay=0.05, TimerFcn=@(~,~) assignin('base', 'bench_stop_flag', true));
    start(tm);
    t0 = tic;
    try
        hw.benchmarkIO(lbK, quick{:}, Repeats=200000, Warmup=0, CancelFcn=@() pollFlag());
        stopped = false;
    catch ME
        stopped = strcmp(ME.identifier, 'hw:benchmarkIO:Cancelled');
    end
    stop(tm); delete(tm);
    evalin('base', 'clear bench_stop_flag')
    results(end+1,:) = check('16 a callback that runs at drawnow stops a long run promptly', ...
        stopped && toc(t0) < 10);

    % Cancelling during the Software floor run also unwinds cleanly.
    lbD = BenchLoopbackInterface(Simulated=false);
    lbD.add_parameter('Buf', 0, Type='Buffer', isArray=true);
    setappdata(0, 'bench_polls', 0);
    try
        hw.benchmarkIO(lbD, Repeats=5, Warmup=1, Plot=false, Progress=false, ...
            ScalarWrite=[], ScalarRead=[], Trigger=[], Sizes=[1024 4096], ...
            VerifyRoundTrip=false, CancelFcn=@() stopAfter(80));
        floorCancelled = false;
    catch ME
        floorCancelled = strcmp(ME.identifier, 'hw:benchmarkIO:Cancelled');
    end
    results(end+1,:) = check('16 cancelling during the Software floor run also ends the call', floorCancelled);
    delete(lbK); delete(lbD);
catch ME
    results(end+1,:) = check(sprintf('16 cancel threw: %s', ME.message), false);
end

%% Teardown
for h = {I, lb, lbF, lbX, rpc, syn, sw, bp, rp}
    try
        if ~isempty(h{1}) && isvalid(h{1})
            delete(h{1});
        end
    catch ME
        fprintf('    (teardown: %s)\n', ME.message);
    end
end

%% Summary
labels = results(:,1);
passed = cell2mat(results(:,2));
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
fprintf('\n%d passed, %d failed, %d total\n\n', sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_hw_benchmark_io:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function lb = makeLoopback(varargin)
% The default contract on an in-memory backend that keeps what it is written.
lb = BenchLoopbackInterface(varargin{:});
lb.add_parameter('WScalar', 0);
lb.add_parameter('RScalar', 0, Access='Read');
lb.add_parameter('BenchTrig', 0, isTrigger=true);
lb.add_parameter('Buf_1024', 0, Type='Buffer', isArray=true);
lb.add_parameter('Buf_4096', 0, Type='Buffer', isArray=true);
lb.add_parameter('Distractor', 5);
end


function row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end


function row = expectError(label, fcn, id, mustMention)
% Pass when fcn throws id and its message names every string in mustMention.
try
    fcn();
    row = {sprintf('%s (did not throw)', label), false};
catch ME
    ok = strcmp(ME.identifier, id) && all(cellfun(@(s) contains(ME.message, s), mustMention));
    if ok
        row = {label, true};
    else
        row = {sprintf('%s (threw %s: %s)', label, ME.identifier, ME.message), false};
    end
end
end


function tf = stopAfter(n)
% True once it has been called more than n times; the count lives in appdata
% so the test can zero and read it.
k = getappdata(0, 'bench_polls');
if isempty(k)
    k = 0;
end
k = k + 1;
setappdata(0, 'bench_polls', k);
tf = k > n;
end


function tf = pollFlag()
% What a Stop button's CancelFcn does: yield so queued callbacks run, then read
% the flag they set.
drawnow limitrate
tf = evalin('base', 'bench_stop_flag');
end
