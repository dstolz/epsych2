function varargout = benchmarkIO(iface, varargin)
% results = hw.benchmarkIO(iface)
% results = hw.benchmarkIO(iface, Name=Value)
% twin    = hw.benchmarkIO("softwareTwin", iface)
% twin    = hw.benchmarkIO("softwareTwin", iface, Name=Value)
% fit     = hw.benchmarkIO("fit", N, seconds)
% fit     = hw.benchmarkIO("fit", N, seconds, TargetSamples=T)
% txt     = hw.benchmarkIO("contract")
%
% Time what a session pays to talk to its hardware -- scalar writes, scalar
% reads, triggers, and buffer writes and read-backs as a function of buffer
% length -- through the calls the runtime itself makes: set_parameter,
% get_parameter and trigger on an hw.Interface. Nothing below that layer is
% touched and nothing here depends on which backend it is, so the same call
% times any hw.Interface; what a backend knows that this function would
% otherwise have to ask about by class comes from two hw.Interface hooks,
% parameterCapacity and isSimulated.
%
% Four ROLES are measured, each filled by one contract parameter (named
% explicitly, or discovered by its default name -- see "contract"):
%   ScalarWrite  writable scalar                         default WScalar
%   ScalarRead   readable scalar                         default RScalar
%   Trigger      parameter flagged isTrigger             default BenchTrig (or !BenchTrig)
%   Buffers      writable (preferably readable) buffers  default Buf_<N>
% Each buffer is written at its capacity and read back. A role a backend
% cannot fill is reported in results.Unsupported, never as an error or a time.
%
% It writes to the contract parameters only, and leaves the last
% values written there. Run it between sessions, never during one: it shares
% the MATLAB thread with the trial loop and writes to the device.
%
% Parameters:
%   iface - hw.Interface, connected, or one whose isSimulated() is true.
%           A disconnected device is refused: several backends report a
%           write as successful and serve the cached Value while disconnected.
%
% Name=Value options:
%   ScalarWrite, ScalarRead, Trigger - parameter name (text) or hw.Parameter.
%       Omitted: discovered by default name; a role not found is reported
%       unsupported. Given: must exist and qualify, or this errors naming it.
%       Given as empty: the role is skipped.
%   Buffers     - names or hw.Parameter array. Same rules.
%   BufferSizes - declared element count per buffer, aligned with Buffers
%       (or with the discovered list, in results.Contract order). NaN =
%       unknown. Used only where parameterCapacity is NaN; after it, the N in
%       a Buf_<N> name, then the length one untimed read returns.
%   Repeats         - timed calls per measurement. Default 50.
%   Warmup          - calls discarded before them. Default 5.
%   VerifyRoundTrip - write a fresh vector to each readable buffer, read it
%       back, compare at float32 precision. Default true.
%   IncludeLookup   - also time each call by NAME, besides the pre-resolved
%       hw.Parameter, to separate lookup cost from transport. Default true.
%   TargetSamples   - length to predict one and two buffer uploads for.
%       Default 292969 (3 s at 97656.25 Hz).
%   SaveTo   - an existing folder (or a path ending in a separator), where
%       a timestamped stem is chosen, or a file stem; writes <stem>.mat
%       (results), <stem>.csv (raw table) and <stem>_summary.csv.
%       Default '' (none).
%   Plot     - draw the summary. Default true.
%   CompareToSoftware - run the same contract on an in-memory twin
%       (hw.Software) and report each time minus that floor. Skipped when
%       iface is itself simulated. Default true.
%
% Returns:
%   results - struct with fields
%     Raw          long table: Role, Parameter, Backend, Path, NRequested,
%                  NTransferred, Iteration, Seconds, Accepted
%     Summary      per Role/Parameter/Path: median, 5th/95th percentile, max,
%                  and for buffers MSamples/s and MB/s at 4 bytes per sample
%     Fit          per buffer role and path: t = Overhead + PerSample*N, and
%                  the predicted time for TargetSamples and for two buffers
%     RoundTrip    per buffer: samples written/read, max error, pass
%     Floor        per Summary row: backend median, twin median, difference
%     Software     the twin's own results (empty when not run)
%     Contract     what filled each role, from where, at what size
%     Unsupported  Role, Parameter, Path, Reason
%     Problems     measurement blocks that threw or had writes rejected
%     Environment  MATLAB, backend, modules, EPsych commit, verbosity levels
%     Options, Figure, Files
%
% Subcommands:
%   "softwareTwin" - the hw.Software interface the floor is measured on: one
%                    parameter per contract parameter, same Name, Type,
%                    Access, isTrigger, isArray, Visible and bounds.
%   "fit"          - the linear fit the Fit table uses, over any N and t.
%   "contract"     - the default contract, as text (also logged).
%
% Example:
%   R = hw.benchmarkIO(iface, Repeats=100);
%   R.Fit(R.Fit.Path == "param", :)
%
% See also: documentation/hw/hw_benchmarkIO.md, hw.Interface.parameterCapacity,
%   hw.Interface.isSimulated

% The entry point dispatches on its first argument, because a package
% function cannot carry the static helpers a class would; each branch is a
% local function with its own arguments block.
if isText_(iface)
    switch lower(string(iface))
        case "softwaretwin"
            [varargout{1:max(nargout, 1)}] = softwareTwinCommand_(varargin{:});
        case "fit"
            varargout{1} = fitLinear_(varargin{:});
        case "contract"
            txt = contractText_();
            vprintf(1, txt)
            varargout{1} = txt;
        otherwise
            error('hw:benchmarkIO:UnknownCommand', ...
                'Unknown command "%s"; expected "softwareTwin", "fit" or "contract".', iface);
    end
    return
end

varargout{1} = run_(iface, varargin{:});
end


% =====================================================================
function results = run_(iface, options)
arguments
    iface (1,1) hw.Interface
    % Role options carry no defaults, so "not stated" (discover) stays
    % distinguishable from "stated as empty" (skip).
    options.ScalarWrite
    options.ScalarRead
    options.Trigger
    options.Buffers
    options.BufferSizes (1,:) double = []
    options.Repeats (1,1) double {mustBeInteger, mustBePositive} = 50
    options.Warmup (1,1) double {mustBeInteger, mustBeNonnegative} = 5
    options.VerifyRoundTrip (1,1) logical = true
    options.IncludeLookup (1,1) logical = true
    options.TargetSamples (1,1) double {mustBePositive, mustBeFinite} = 292969
    options.SaveTo (1,:) char = ''
    options.Plot (1,1) logical = true
    options.CompareToSoftware (1,1) logical = true
end

% First, before anything else asks the interface for anything.
if ~iface.IsConnected && ~iface.isSimulated()
    error('hw:benchmarkIO:NotConnected', ...
        ['%s (%s) is not connected. A disconnected backend may accept writes ' ...
        'and answer reads from cached values without any device I/O, so its ' ...
        'timings would be meaningless. Connect it first.'], ...
        iface.displayLabel(), class(iface));
end

C = defaults_();
env = environment_(iface);
if env.IsSimulated
    vprintf(2, ['hw.benchmarkIO: %s has no device behind it; these timings ' ...
        'describe EPsych''s own overhead only'], env.DisplayLabel)
end

contract = resolveContract_(iface, options);

if isempty(contract.Blocks)
    txt = contractText_();
    vprintf(0, 1, txt)
    error('hw:benchmarkIO:NothingToMeasure', ...
        'Nothing on %s can be measured.\n%s\nUnsupported:\n%s', ...
        env.DisplayLabel, txt, strjoin(compose("  %s %s: %s", ...
        contract.Unsupported.Role, contract.Unsupported.Parameter, ...
        contract.Unsupported.Reason), newline));
end

nTotal = options.Warmup + options.Repeats;
blocks = contract.Blocks;
nBlocks = numel(blocks);
rawTables = cell(nBlocks, 1);
problems = emptyIssues_();
backend = string(class(iface));

for b = 1:nBlocks
    B = blocks(b);
    try
        [t, nOut, ok] = timeBlock_(iface, B.Kind, B.Target, B.Payload, nTotal);
    catch ME
        vprintf(0, 1, ME)
        problems = appendRow_(problems, issueRow_(B, string(ME.message)));
        continue
    end

    keep = (options.Warmup + 1):nTotal;
    n = numel(keep);
    rawTables{b} = table( ...
        repmat(B.Role, n, 1), repmat(B.Parameter, n, 1), repmat(backend, n, 1), ...
        repmat(B.Path, n, 1), repmat(B.NRequested, n, 1), nOut(keep), ...
        (1:n)', t(keep), ok(keep), ...
        'VariableNames', C.RAW_VARIABLES);

    if ~all(ok(keep))
        problems = appendRow_(problems, issueRow_(B, ...
            sprintf('%d of %d timed writes were reported failed by set_parameter', ...
            sum(~ok(keep)), n)));
    end
    if numel(unique(nOut(keep))) > 1
        problems = appendRow_(problems, issueRow_(B, ...
            sprintf('transferred count varied between calls (%g to %g)', ...
            min(nOut(keep)), max(nOut(keep)))));
    end

    vprintf(2, 'hw.benchmarkIO: %s %s [%s] N=%d: median %.4g ms over %d calls', ...
        B.Role, B.Parameter, B.Path, B.NRequested, 1e3 * median(t(keep)), n)
end

raw = vertcat(rawTables{~cellfun(@isempty, rawTables)});
if isempty(raw)
    raw = emptyRaw_();
end

results = struct();
results.Raw = raw;
results.Summary = summarize_(raw);
results.Fit = fitTable_(results.Summary, options.TargetSamples);

if options.VerifyRoundTrip
    results.RoundTrip = verifyRoundTrip_(iface, contract.Buffers);
else
    results.RoundTrip = emptyRoundTrip_();
end

results.Floor = emptyFloor_();
results.Software = [];
if options.CompareToSoftware && ~env.IsSimulated
    [results.Floor, results.Software] = softwareFloor_(contract, results.Summary, options);
elseif options.CompareToSoftware
    vprintf(2, 'hw.benchmarkIO: Software floor skipped; the interface is itself simulated')
end

% The handles stay internal: a saved hw.Parameter drags its whole
% interface, device handle included, into the MAT file.
results.Contract = removevars(contract.Table, 'Param');
results.Unsupported = contract.Unsupported;
results.Problems = problems;
results.Environment = env;
results.Options = rmfield(options, intersect(fieldnames(options), ...
    {'ScalarWrite', 'ScalarRead', 'Trigger', 'Buffers'}));
results.Figure = [];
results.Files = struct('Mat', '', 'Csv', '', 'SummaryCsv', '');

if options.Plot
    results.Figure = plot_(results);
end

if ~isempty(options.SaveTo)
    results.Files = save_(results, options.SaveTo);
end
end


% =====================================================================
function C = defaults_()
C.ROLES = ["ScalarWrite", "ScalarRead", "Trigger"];
C.DEFAULT_NAMES = {{'WScalar'}, {'RScalar'}, {'BenchTrig', '!BenchTrig'}};
C.BUFFER_PATTERN = '^Buf_(\d+)$';
C.BUFFER_TYPES = {'Buffer', 'Coefficient Buffer'};
C.NON_SCALAR_TYPES = {'Buffer', 'Coefficient Buffer', 'String', 'File', 'StimType'};
C.RAW_VARIABLES = {'Role', 'Parameter', 'Backend', 'Path', 'NRequested', ...
    'NTransferred', 'Iteration', 'Seconds', 'Accepted'};
% Fixed, private stream: reproducible payloads, and the global stream a
% trial selector may be drawing from is never touched.
C.SEED = 20261120;
% Bytes per sample for MB/s. RPvds buffers are float32 on the wire; a
% backend that sends text or another width moves a different byte count.
C.BYTES_PER_SAMPLE = 4;
end


% =====================================================================
function contract = resolveContract_(iface, options)
% Decide what fills each role, at what size, and which calls to time.
C = defaults_();
allP = iface.all_parameters(includeInvisible = true, includeTriggers = true);
if isempty(allP)
    allP = hw.Parameter.empty(1, 0);
end

unsupported = emptyIssueTable_();
rows = emptyContractTable_();
blocks = emptyBlocks_();
buffers = struct('Parameter', {}, 'N', {}, 'Readable', {});
rs = RandStream('mt19937ar', 'Seed', C.SEED);

% ---- scalar roles and the trigger
for r = 1:numel(C.ROLES)
    role = C.ROLES(r);
    field = char(role);
    explicit = isfield(options, field);
    if explicit
        if isEmptySpec_(options.(field))
            unsupported = appendRow_(unsupported, issueTableRow_(role, "", "", "skipped by the caller"));
            continue
        end
        P = resolveExplicit_(iface, allP, options.(field), role);
        if numel(P) ~= 1
            error('hw:benchmarkIO:RoleRequirement', ...
                'Role %s takes exactly one parameter; %d were given.', role, numel(P));
        end
        source = "explicit";
    else
        P = findByNames_(allP, C.DEFAULT_NAMES{r});
        if isempty(P)
            unsupported = appendRow_(unsupported, issueTableRow_(role, "", "", ...
                sprintf('no parameter named %s', strjoin(C.DEFAULT_NAMES{r}, ' or '))));
            continue
        end
        source = "discovered";
    end

    reason = scalarRequirement_(role, P);
    if reason ~= ""
        if explicit
            error('hw:benchmarkIO:RoleRequirement', ...
                'Role %s: parameter "%s" %s.', role, P.Name, reason);
        end
        unsupported = appendRow_(unsupported, issueTableRow_(role, string(P.Name), "", reason));
        continue
    end

    switch role
        case "ScalarWrite"
            kind = "scalarwrite";
            payload = scalarWriteValues_(P);
        case "ScalarRead"
            kind = "read";
            payload = [];
        otherwise
            kind = "trigger";
            payload = [];
    end

    [nm, nameReason] = namePath_(iface, P);
    rows = appendRow_(rows, contractRow_(role, P, source, NaN, NaN, 1, "scalar", nm, ""));
    [blocks, unsupported] = addBlocks_(blocks, unsupported, role, kind, P, nm, nameReason, ...
        payload, 1, options.IncludeLookup);
end

% ---- buffers
if isfield(options, 'Buffers')
    if isEmptySpec_(options.Buffers)
        P = hw.Parameter.empty(1, 0);
        unsupported = appendRow_(unsupported, issueTableRow_("Buffers", "", "", "skipped by the caller"));
    else
        P = resolveExplicit_(iface, allP, options.Buffers, "Buffers");
    end
    explicit = true;
else
    P = discoverBuffers_(allP, C);
    explicit = false;
    if isempty(P)
        unsupported = appendRow_(unsupported, issueTableRow_("Buffers", "", "", ...
            "no parameter named Buf_<N>"));
    end
end

declared = options.BufferSizes;
if ~isempty(declared) && numel(declared) ~= numel(P)
    error('hw:benchmarkIO:BufferSizesMismatch', ...
        'BufferSizes has %d entries for %d buffer(s); it is aligned with Buffers.', ...
        numel(declared), numel(P));
end

source = "discovered";
if explicit
    source = "explicit";
end

for k = 1:numel(P)
    p = P(k);
    d = NaN;
    if ~isempty(declared)
        d = declared(k);
    end
    [N, sizeSource, capacity, note] = bufferSize_(iface, p, d);

    reason = bufferRequirement_(p, N);
    if reason ~= ""
        if explicit
            error('hw:benchmarkIO:RoleRequirement', ...
                'Role Buffers: parameter "%s" %s.', p.Name, reason);
        end
        unsupported = appendRow_(unsupported, issueTableRow_("Buffers", string(p.Name), "", reason));
        continue
    end

    data = randomPayload_(rs, N);
    [nm, nameReason] = namePath_(iface, p);
    rows = appendRow_(rows, contractRow_("Buffers", p, source, capacity, d, N, sizeSource, nm, note));

    [blocks, unsupported] = addBlocks_(blocks, unsupported, "BufferWrite", "bufferwrite", p, nm, ...
        nameReason, {data}, N, options.IncludeLookup);

    readable = ~strcmp(p.Access, 'Write');
    if readable
        [blocks, unsupported] = addBlocks_(blocks, unsupported, "BufferRead", "read", p, nm, ...
            nameReason, [], N, options.IncludeLookup);
    else
        unsupported = appendRow_(unsupported, issueTableRow_("BufferRead", string(p.Name), "", ...
            "write-only parameter"));
    end
    buffers = appendRow_(buffers, struct('Parameter', p, 'N', N, 'Readable', readable));
end

contract.Blocks = blocks;
contract.Buffers = buffers;
contract.Table = rows;
contract.Unsupported = unsupported;
end


function [blocks, unsupported] = addBlocks_(blocks, unsupported, role, kind, P, nm, nameReason, payload, N, includeLookup)
arguments
    blocks struct
    unsupported table
    role (1,1) string
    kind (1,1) string
    P (1,1) hw.Parameter
    nm (1,1) string
    nameReason (1,1) string
    payload
    N (1,1) double
    includeLookup (1,1) logical
end
% One block per path: the pre-resolved parameter always, the name when asked.
blocks = appendRow_(blocks, makeBlock_(role, kind, P, P, "param", payload, N));
if ~includeLookup
    return
end
if nm == ""
    unsupported = appendRow_(unsupported, issueTableRow_(role, string(P.Name), "name", nameReason));
else
    blocks = appendRow_(blocks, makeBlock_(role, kind, P, char(nm), "name", payload, N));
end
end


function B = makeBlock_(role, kind, P, target, path, payload, N)
arguments
    role (1,1) string
    kind (1,1) string
    P (1,1) hw.Parameter
    target
    path (1,1) string
    payload
    N (1,1) double
end
B = struct('Role', role, 'Kind', kind, 'Parameter', string(P.Name), ...
    'Param', P, 'Target', {target}, 'Path', path, 'Payload', {payload}, ...
    'NRequested', N);
end


function B = emptyBlocks_()
B = struct('Role', {}, 'Kind', {}, 'Parameter', {}, 'Param', {}, 'Target', {}, ...
    'Path', {}, 'Payload', {}, 'NRequested', {});
end


% =====================================================================
function [t, nOut, ok] = timeBlock_(iface, kind, target, payload, nTotal)
% Time nTotal calls of one kind, one call per tic/toc. Each kind has its own
% loop so nothing but the interface call sits between tic and toc.
arguments
    iface (1,1) hw.Interface
    kind (1,1) string {mustBeMember(kind, ["scalarwrite", "bufferwrite", "read", "trigger"])}
    target
    payload
    nTotal (1,1) double {mustBeInteger, mustBePositive}
end
t = zeros(nTotal, 1);
nOut = zeros(nTotal, 1);
ok = true(nTotal, 1);

switch kind
    case "scalarwrite"
        % Alternate two values so a backend that skips an unchanged write
        % still does the work.
        for k = 1:nTotal
            v = payload(mod(k, 2) + 1);
            t0 = tic;
            r = iface.set_parameter(target, v);
            t(k) = toc(t0);
            ok(k) = writeAccepted_(r);
        end
        nOut(:) = 1;

    case "bufferwrite"
        % The value is a scalar cell around the vector: the shape
        % hw.Parameter.set.Value hands every backend for an array.
        for k = 1:nTotal
            t0 = tic;
            r = iface.set_parameter(target, payload);
            t(k) = toc(t0);
            ok(k) = writeAccepted_(r);
        end
        nOut(:) = numel(payload{1});

    case "read"
        for k = 1:nTotal
            t0 = tic;
            v = iface.get_parameter(target);
            t(k) = toc(t0);
            nOut(k) = transferredCount_(v);
        end

    case "trigger"
        for k = 1:nTotal
            t0 = tic;
            iface.trigger(target);
            t(k) = toc(t0);
        end
        nOut(:) = 1;
end
end


function tf = writeAccepted_(r)
% set_parameter returns false on a failed write; anything else is accepted.
if (isnumeric(r) || islogical(r)) && ~isempty(r)
    tf = all(r(:) ~= 0);
else
    tf = true;
end
end


function n = transferredCount_(v)
% Elements actually returned by one read -- for a whole-tag read, the tag's
% size, whatever was asked for.
if iscell(v) && isscalar(v)
    v = v{1};
end
if isnumeric(v) || islogical(v)
    n = numel(v);
else
    n = NaN;
end
end


% =====================================================================
function S = summarize_(raw)
C = defaults_();
if isempty(raw)
    S = emptySummary_();
    return
end

[g, keys] = findgroups(raw(:, {'Role', 'Parameter', 'Path'}));
nG = height(keys);
NReq = zeros(nG, 1);
NTr = zeros(nG, 1);
nIt = zeros(nG, 1);
med = zeros(nG, 1);
p5 = zeros(nG, 1);
p95 = zeros(nG, 1);
mx = zeros(nG, 1);
for k = 1:nG
    m = g == k;
    s = raw.Seconds(m);
    NReq(k) = raw.NRequested(find(m, 1));
    NTr(k) = median(raw.NTransferred(m));
    nIt(k) = numel(s);
    med(k) = median(s);
    pr = prctile(s, [5 95]);
    p5(k) = pr(1);
    p95(k) = pr(2);
    mx(k) = max(s);
end

isBuf = ismember(keys.Role, ["BufferWrite", "BufferRead"]);
NFit = fitAbscissa_(keys.Role, NReq, NTr);
msps = NaN(nG, 1);
mbps = NaN(nG, 1);
msps(isBuf) = NFit(isBuf) ./ med(isBuf) / 1e6;
mbps(isBuf) = C.BYTES_PER_SAMPLE * NFit(isBuf) ./ med(isBuf) / 1e6;

S = [keys, table(NReq, NTr, nIt, med, p5, p95, mx, msps, mbps, ...
    'VariableNames', {'NRequested', 'NTransferred', 'Iterations', 'Median_s', ...
    'P5_s', 'P95_s', 'Max_s', 'MSamplesPerSec', 'MBPerSec'})];
S = sortrows(S, {'Role', 'Path', 'NRequested'});
end


function N = fitAbscissa_(role, NReq, NTr)
arguments
    role (:,1) string
    NReq (:,1) double
    NTr (:,1) double
end
% A write moves what was handed to it; a read moves what came back.
N = NReq;
isRead = role == "BufferRead";
N(isRead) = NTr(isRead);
end


% =====================================================================
function F = fitTable_(S, target)
F = emptyFit_();
for role = ["BufferWrite", "BufferRead"]
    for path = ["param", "name"]
        m = S.Role == role & S.Path == path;
        if ~any(m)
            continue
        end
        x = fitAbscissa_(S.Role(m), S.NRequested(m), S.NTransferred(m));
        y = S.Median_s(m);
        f = fitLinear_(x, y, TargetSamples = target);
        F = appendRow_(F, table(role, path, f.NumSizes, f.NMin, f.NMax, ...
            f.Overhead_s, f.PerSample_s, f.RSquared, target, f.Predicted_s, ...
            f.PredictedTwoBuffers_s, f.Extrapolated, f.Note, ...
            'VariableNames', F.Properties.VariableNames));
    end
end
end


function f = fitLinear_(N, t, options)
% f = fitLinear_(N, t, TargetSamples=T)
% Least-squares t = Overhead + PerSample*N. Needs two distinct N: with one,
% a fixed cost cannot be told from a per-sample one, so both are NaN.
arguments
    N (:,1) double
    t (:,1) double
    options.TargetSamples (1,1) double = NaN
end
if numel(N) ~= numel(t)
    error('hw:benchmarkIO:FitSizeMismatch', 'N has %d elements and t has %d.', numel(N), numel(t));
end

ok = isfinite(N) & isfinite(t);
N = N(ok);
t = t(ok);
f = struct('NumSizes', numel(unique(N)), 'NMin', NaN, 'NMax', NaN, ...
    'Overhead_s', NaN, 'PerSample_s', NaN, 'RSquared', NaN, ...
    'Predicted_s', NaN, 'PredictedTwoBuffers_s', NaN, 'Extrapolated', false, ...
    'Note', "");
if ~isempty(N)
    f.NMin = min(N);
    f.NMax = max(N);
end

if f.NumSizes < 2
    f.Note = "needs at least two buffer sizes";
    return
end

% Centred and scaled: N spans several decades, and the slope is then read
% back in seconds per sample.
[p, ~, mu] = polyfit(N, t, 1);
f.PerSample_s = p(1) / mu(2);
f.Overhead_s = p(2) - p(1) * mu(1) / mu(2);
ssTot = sum((t - mean(t)).^2);
if ssTot > 0
    f.RSquared = 1 - sum((t - polyval(p, N, [], mu)).^2) / ssTot;
end

T = options.TargetSamples;
if isfinite(T)
    f.Predicted_s = f.Overhead_s + f.PerSample_s * T;
    f.PredictedTwoBuffers_s = 2 * f.Predicted_s;
    f.Extrapolated = T < f.NMin || T > f.NMax;
end
if f.Overhead_s < 0
    f.Note = "negative overhead: the fixed cost is below what these sizes resolve";
end
end


% =====================================================================
function RT = verifyRoundTrip_(iface, buffers)
% Untimed: write a vector the timed blocks never wrote, read it back through
% the pre-resolved parameter, compare at float32 precision.
C = defaults_();
RT = emptyRoundTrip_();
rs = RandStream('mt19937ar', 'Seed', C.SEED + 1);
for k = 1:numel(buffers)
    if ~buffers(k).Readable
        continue
    end
    P = buffers(k).Parameter;
    N = buffers(k).N;
    data = randomPayload_(rs, N);
    nRead = NaN;
    maxErr = NaN;
    tol = double(max(eps(abs(data))));
    pass = false;
    try
        accepted = writeAccepted_(iface.set_parameter(P, {data}));
        v = iface.get_parameter(P);
        if iscell(v) && isscalar(v)
            v = v{1};
        end
        if ~(isnumeric(v) || islogical(v))
            note = sprintf('read returned a %s, not numbers', class(v));
        else
            nRead = numel(v);
            n = min(nRead, N);
            % One float32 ulp per element: a float32 path returns exactly
            % what it was given, so anything above that is a corruption.
            err = abs(double(single(reshape(v(1:n), 1, []))) - double(data(1:n)));
            if n > 0
                maxErr = max(err);
            end
            pass = nRead >= N && all(err <= double(eps(abs(data(1:n)))));
            note = "";
            if nRead < N
                note = sprintf('read returned %d of %d samples', nRead, N);
            elseif nRead > N
                note = sprintf('read returned %d samples; the first %d compared', nRead, N);
            end
            if ~accepted
                note = strtrim(note + " write reported failed");
            end
        end
    catch ME
        vprintf(0, 1, ME)
        note = string(ME.message);
    end
    RT = appendRow_(RT, table(string(P.Name), N, nRead, maxErr, tol, pass, string(note), ...
        'VariableNames', RT.Properties.VariableNames));
end
end


% =====================================================================
function [Floor, twinResults] = softwareFloor_(contract, S, options)
% The same contract, the same sizes, on an in-memory twin: what EPsych's own
% call path costs with no transport under it.
arguments
    contract (1,1) struct
    S table
    options (1,1) struct
end
[twin, map] = buildTwin_(contract);

C = defaults_();
roles = C.ROLES;
args = cell(1, 2 * numel(roles));
for r = 1:numel(roles)
    args{2 * r - 1} = char(roles(r));
    args{2 * r} = twinFor_(map, contract.Table, roles(r));
end
bufRows = contract.Table(contract.Table.Role == "Buffers", :);
[~, loc] = ismember(bufRows.Parameter, map.Name);
qb = reshape(map.Twin(loc), 1, []);

twinResults = run_(twin, args{:}, Buffers = qb, BufferSizes = reshape(bufRows.N, 1, []), ...
    Repeats = options.Repeats, Warmup = options.Warmup, VerifyRoundTrip = false, ...
    IncludeLookup = options.IncludeLookup, TargetSamples = options.TargetSamples, ...
    Plot = false, CompareToSoftware = false);
twinResults.Figure = [];

T = twinResults.Summary;
Floor = emptyFloor_();
for k = 1:height(S)
    m = T.Role == S.Role(k) & T.Parameter == S.Parameter(k) & T.Path == S.Path(k);
    floorMed = NaN;
    if any(m)
        floorMed = T.Median_s(find(m, 1));
    end
    Floor = appendRow_(Floor, table(S.Role(k), S.Parameter(k), S.Path(k), ...
        S.NRequested(k), S.Median_s(k), floorMed, S.Median_s(k) - floorMed, ...
        'VariableNames', Floor.Properties.VariableNames));
end
delete(twin)
end


function q = twinFor_(map, rows, role)
% The twin parameter standing in for a role, or [] (skip) when the role was
% not measured.
arguments
    map table
    rows table
    role (1,1) string
end
q = [];
m = rows.Role == role;
if any(m)
    q = map.Twin(map.Name == rows.Parameter(find(m, 1)));
end
end


function varargout = softwareTwinCommand_(iface, options)
% twin = hw.benchmarkIO("softwareTwin", iface, Name=Value)
arguments
    iface (1,1) hw.Interface
    options.ScalarWrite
    options.ScalarRead
    options.Trigger
    options.Buffers
    options.BufferSizes (1,:) double = []
end
opts = options;
opts.IncludeLookup = false;
contract = resolveContract_(iface, opts);
[twin, map] = buildTwin_(contract);
varargout = {twin, map};
end


function [twin, map] = buildTwin_(contract)
% One in-memory parameter per contract parameter, carrying what decides how
% the call path treats it: name, type, access, trigger flag, visibility.
rows = contract.Table;
twin = hw.Software();
names = unique(rows.Parameter, 'stable');

made = cell(numel(names), 1);
for k = 1:numel(names)
    p = rows.Param(find(rows.Parameter == names(k), 1));
    made{k} = twin.add_parameter(p.Name, 0, Type = p.Type, Access = p.Access, ...
        Visible = p.Visible, isTrigger = p.isTrigger, isArray = p.isArray, ...
        Min = p.Min, Max = p.Max);
end
twinP = vertcat(made{:});
if isempty(twinP)
    twinP = hw.Parameter.empty(0, 1);
end
map = table(reshape(names, [], 1), twinP, 'VariableNames', {'Name', 'Twin'});
end


% =====================================================================
function [N, sizeSource, capacity, note] = bufferSize_(iface, P, declared)
% Capacity first; then what the caller declared; then the N in a Buf_<N>
% name; then the length one untimed read returns.
arguments
    iface (1,1) hw.Interface
    P (1,1) hw.Parameter
    declared (1,1) double
end
C = defaults_();
note = "";
capacity = NaN;
try
    capacity = double(iface.parameterCapacity(P));
catch ME
    vprintf(0, 1, ME)
end
if ~(isscalar(capacity) && isfinite(capacity) && capacity >= 1)
    capacity = NaN;
end

nameN = NaN;
tok = regexp(P.Name, C.BUFFER_PATTERN, 'tokens', 'once');
if ~isempty(tok)
    nameN = str2double(tok{1});
end

if isfinite(capacity)
    N = capacity;
    sizeSource = "parameterCapacity";
    stated = [declared, nameN];
    stated = stated(isfinite(stated));
    if any(stated ~= capacity)
        note = sprintf('stated size %g differs from the capacity the backend reports; capacity used', ...
            stated(find(stated ~= capacity, 1)));
        vprintf(1, 'hw.benchmarkIO: "%s": %s', P.Name, note)
    end
elseif isfinite(declared) && declared >= 1
    N = declared;
    sizeSource = "BufferSizes";
elseif isfinite(nameN) && nameN >= 1
    N = nameN;
    sizeSource = "name";
else
    N = NaN;
    sizeSource = "read";
    if ~strcmp(P.Access, 'Write')
        try
            N = transferredCount_(iface.get_parameter(P));
        catch ME
            vprintf(0, 1, ME)
        end
    end
    if ~(isfinite(N) && N >= 1)
        N = NaN;
        sizeSource = "unknown";
    end
end
N = round(N);
end


function reason = scalarRequirement_(role, P)
C = defaults_();
reason = "";
switch role
    case "ScalarWrite"
        if strcmp(P.Access, 'Read')
            reason = "is read-only";
        elseif P.isTrigger
            reason = "is a trigger";
        elseif P.isArray || ismember(P.Type, C.NON_SCALAR_TYPES)
            reason = sprintf("is not a numeric scalar (Type %s)", P.Type);
        end
    case "ScalarRead"
        if strcmp(P.Access, 'Write')
            reason = "is write-only";
        elseif P.isArray || ismember(P.Type, C.NON_SCALAR_TYPES)
            reason = sprintf("is not a numeric scalar (Type %s)", P.Type);
        end
    case "Trigger"
        if ~P.isTrigger
            reason = "is not flagged as a trigger (isTrigger is false)";
        end
end
end


function reason = bufferRequirement_(P, N)
C = defaults_();
reason = "";
if strcmp(P.Access, 'Read')
    reason = "is read-only";
elseif P.isTrigger
    reason = "is a trigger";
elseif ismember(P.Type, {'String', 'File', 'StimType'})
    reason = sprintf("holds Type %s, not samples", P.Type);
elseif ~isfinite(N)
    reason = "has no known size: parameterCapacity is NaN, no BufferSizes entry, " + ...
        "no N in its name, and a read returned no samples";
elseif ~(ismember(P.Type, C.BUFFER_TYPES) || P.isArray || N > 1)
    reason = sprintf("is a scalar (Type %s, size %d)", P.Type, N);
end
end


function v = scalarWriteValues_(P)
% Two distinct values inside the parameter's bounds where it has any.
lo = 0;
if isfinite(P.Min)
    lo = max(lo, P.Min);
end
if isfinite(P.Max)
    lo = min(lo, P.Max);
end
hi = lo + 1;
if isfinite(P.Max) && hi > P.Max
    hi = P.Max;
    lo = max(P.Min, hi - 1);
end
v = [lo hi];
end


function data = randomPayload_(rs, N)
% Full-length float32 noise in [-1 1).
data = 2 * rand(rs, 1, N, 'single') - 1;
end


function [nm, reason] = namePath_(iface, P)
% The name to time the by-name path with: P.Name, but only when
% find_parameter resolves it, at its default visibility (how most backends
% call it), to this very parameter.
nm = "";
reason = "";
Q = iface.find_parameter(P.Name, silenceParameterNotFound = true);
if ~isempty(Q) && Q(1) == P
    nm = string(P.Name);
elseif ~P.Visible
    reason = "invisible: find_parameter does not resolve it by name at default visibility";
else
    reason = "its name resolves to another parameter first";
end
end


function P = findByNames_(allP, names)
P = hw.Parameter.empty(1, 0);
if isempty(allP)
    return
end
hwNames = arrayfun(@hw.Interface.getHardwareParameterName, allP, 'UniformOutput', false);
for k = 1:numel(names)
    idx = find(strcmp({allP.Name}, names{k}) | strcmp(hwNames, names{k}), 1);
    if ~isempty(idx)
        P = allP(idx);
        return
    end
end
end


function P = discoverBuffers_(allP, C)
P = hw.Parameter.empty(1, 0);
if isempty(allP)
    return
end
tok = regexp({allP.Name}, C.BUFFER_PATTERN, 'tokens', 'once');
hit = ~cellfun(@isempty, tok);
if ~any(hit)
    return
end
P = allP(hit);
n = cellfun(@(c) str2double(c{1}), tok(hit));
[~, order] = sortrows([n(:), (1:numel(n))']);
P = P(order);
end


function P = resolveExplicit_(iface, allP, spec, role)
% Names or hw.Parameter handles, each of which must exist on this interface.
arguments
    iface (1,1) hw.Interface
    allP hw.Parameter
    spec
    role (1,1) string
end
if isa(spec, 'hw.Parameter')
    for k = 1:numel(spec)
        if isempty(allP) || ~any(allP == spec(k))
            error('hw:benchmarkIO:RoleNotFound', ...
                'Role %s: parameter "%s" does not belong to this interface.', role, spec(k).Name);
        end
    end
    P = reshape(spec, 1, []);
    return
end

if ~(ischar(spec) || isstring(spec) || iscellstr(spec))
    error('hw:benchmarkIO:RoleSpec', ...
        'Role %s takes parameter names or hw.Parameter objects, not a %s.', role, class(spec));
end
names = cellstr(spec);
found = cell(1, numel(names));
for k = 1:numel(names)
    q = iface.find_parameter(names{k}, includeInvisible = true, silenceParameterNotFound = true);
    if isempty(q)
        error('hw:benchmarkIO:RoleNotFound', ...
            'Role %s: no parameter "%s" on %s.', role, names{k}, iface.displayLabel());
    end
    found{k} = q(1);
end
P = [found{:}];
end


function tf = isEmptySpec_(spec)
tf = isempty(spec) || (isstring(spec) && all(strlength(spec) == 0));
end


function tf = isText_(x)
tf = (ischar(x) && (isrow(x) || isempty(x))) || (isstring(x) && isscalar(x));
end


% =====================================================================
function env = environment_(iface)
% What a reader needs to compare one run with another. Every value is read
% through the interface's public API, before any timing starts.
global GVerbosity GLogVerbosity
C = defaults_();
env = struct();
env.Date = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
env.MATLABVersion = version;
env.MATLABRelease = version('-release');
env.Computer = computer;
env.BackendClass = class(iface);
env.BackendType = char(string(iface.Type));
env.DisplayLabel = iface.displayLabel();
env.IsSimulated = iface.isSimulated();
env.IsConnected = iface.IsConnected;

env.Mode = '';
try
    m = iface.mode;
    if ~isempty(m)
        env.Mode = char(string(m));
    end
catch ME
    vprintf(2, 'hw.benchmarkIO: mode not readable: %s', ME.message)
end

env.CreationSpec = struct('type', '', 'label', '', 'description', '');
try
    spec = iface.getCreationSpec();
    env.CreationSpec = struct('type', spec.type, 'label', spec.label, ...
        'description', spec.description);
catch ME
    vprintf(2, 'hw.benchmarkIO: creation spec not available: %s', ME.message)
end

env.Modules = struct('Label', {}, 'Name', {}, 'Index', {}, 'Fs', {}, 'Info', {});
if ~isempty(iface.Module)
    env.Modules = arrayfun(@(q) struct('Label', q.Label, 'Name', q.Name, ...
        'Index', double(q.Index), 'Fs', q.Fs, 'Info', q.Info), iface.Module);
end

env.EPsychCommit = '';
try
    E = EPsychInfo;
    env.EPsychCommit = char(string(E.chksum));
catch ME
    vprintf(2, 'hw.benchmarkIO: EPsych commit not available: %s', ME.message)
end

% Every set_parameter on some backends logs a level-4 record, and the log
% takes everything by default, so the log write is part of what is timed.
env.GVerbosity = GVerbosity;
env.GLogVerbosity = GLogVerbosity;
env.Level4ToConsole = NaN;
env.Level4ToLog = NaN;
try
    env.Level4ToConsole = granary.isEnabled(4, 'console');
    env.Level4ToLog = granary.isEnabled(4, 'log');
catch ME
    vprintf(2, 'hw.benchmarkIO: verbosity gate not available: %s', ME.message)
end

% The floor under every number in the tables.
e = zeros(1000, 1);
for k = 1:numel(e)
    t0 = tic;
    e(k) = toc(t0);
end
env.TicTocOverhead_s = median(e);
env.PayloadSeed = C.SEED;
env.BytesPerSample = C.BYTES_PER_SAMPLE;
end


% =====================================================================
function fig = plot_(results)
S = results.Summary;
F = results.Fit;
fig = figure('Name', sprintf('hw.benchmarkIO: %s', results.Environment.DisplayLabel), ...
    'NumberTitle', 'off', 'Color', 'w');
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s (%s), %s', results.Environment.DisplayLabel, ...
    results.Environment.BackendClass, results.Environment.Date), 'Interpreter', 'none');

% ---- buffers: median with 5th-95th percentile bars, fit, prediction
ax = nexttile(tl);
hold(ax, 'on')
grid(ax, 'on')
colors = lines(4);
ci = 0;
for role = ["BufferWrite", "BufferRead"]
    for path = ["param", "name"]
        m = S.Role == role & S.Path == path;
        if ~any(m)
            continue
        end
        ci = ci + 1;
        c = colors(mod(ci - 1, size(colors, 1)) + 1, :);
        x = fitAbscissa_(S.Role(m), S.NRequested(m), S.NTransferred(m));
        y = 1e3 * S.Median_s(m);
        errorbar(ax, x, y, y - 1e3 * S.P5_s(m), 1e3 * S.P95_s(m) - y, 'o', ...
            'Color', c, 'MarkerFaceColor', c, 'DisplayName', sprintf('%s (%s)', role, path));

        f = F(F.Role == role & F.Path == path, :);
        if ~isempty(f) && isfinite(f.PerSample_s(1))
            xx = logspace(log10(max(1, min(x))), log10(max([x; f.TargetSamples(1)])), 64);
            plot(ax, xx, 1e3 * (f.Overhead_s(1) + f.PerSample_s(1) * xx), '-', ...
                'Color', c, 'HandleVisibility', 'off');
            plot(ax, f.TargetSamples(1), 1e3 * f.Predicted_s(1), 'p', 'MarkerSize', 12, ...
                'Color', c, 'MarkerFaceColor', c, 'HandleVisibility', 'off');
        end
    end
end
set(ax, 'XScale', 'log')
xlabel(ax, 'Samples per call')
ylabel(ax, 'Time per call (ms)')
title(ax, 'Buffers (pentagram: predicted at TargetSamples)')
if ci > 0
    xline(ax, results.Options.TargetSamples, ':', 'TargetSamples', 'HandleVisibility', 'off');
    lgd = legend(ax);
    lgd.Location = 'northwest';
    lgd.Interpreter = 'none';
else
    text(ax, 0.5, 0.5, 'No buffer measurements', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center')
end

% ---- scalars and triggers
ax = nexttile(tl);
m = ismember(S.Role, ["ScalarWrite", "ScalarRead", "Trigger"]);
if any(m)
    labels = S.Role(m) + " (" + S.Path(m) + ")";
    y = 1e3 * S.Median_s(m);
    x = (1:numel(y))';
    bar(ax, x, y)
    hold(ax, 'on')
    errorbar(ax, x, y, y - 1e3 * S.P5_s(m), 1e3 * S.P95_s(m) - y, 'k.', 'LineStyle', 'none')
    set(ax, 'XTick', x, 'XTickLabel', cellstr(labels), 'TickLabelInterpreter', 'none')
    ylabel(ax, 'Median time per call (ms)')
else
    text(ax, 0.5, 0.5, 'No scalar or trigger measurements', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center')
end
grid(ax, 'on')
title(ax, 'Scalars and triggers (bars: 5th-95th percentile)')
end


% =====================================================================
function files = save_(results, saveTo)
[folder, stem] = fileparts(saveTo);
if isfolder(saveTo) || endsWith(saveTo, {'/', '\'})
    folder = saveTo;
    stem = sprintf('benchmarkIO_%s_%s', ...
        matlab.lang.makeValidName(results.Environment.BackendType), ...
        char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss')));
end
if isempty(folder)
    folder = pwd;
end
if ~isfolder(folder)
    mkdir(folder);
end

files = struct( ...
    'Mat', fullfile(folder, [stem '.mat']), ...
    'Csv', fullfile(folder, [stem '.csv']), ...
    'SummaryCsv', fullfile(folder, [stem '_summary.csv']));

results.Figure = [];
results.Files = files;
save(files.Mat, 'results');
writetable(results.Raw, files.Csv);
writetable(results.Summary, files.SummaryCsv);
vprintf(1, 'hw.benchmarkIO: saved %s', files.Mat)
end


% =====================================================================
function txt = contractText_()
txt = sprintf([ ...
    'hw.benchmarkIO default contract (role: default name -- requirement)\n' ...
    '  ScalarWrite: WScalar -- writable numeric scalar\n' ...
    '  ScalarRead:  RScalar -- readable numeric scalar, e.g. driven by a counter\n' ...
    '  Trigger:     BenchTrig or !BenchTrig -- isTrigger true (an RPvds tag needs the ! prefix)\n' ...
    '  Buffers:     Buf_<N> -- writable, preferably readable, buffer of capacity N\n' ...
    'Or name them: hw.benchmarkIO(iface, ScalarWrite="X", Buffers=["A" "B"])']);
end


% =====================================================================
% Tables and rows. Rows are appended through appendRow_ so no loop grows an
% array in place.
function T = appendRow_(T, row)
T = [T; row];
end


function T = emptyIssueTable_()
T = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', {'Role', 'Parameter', 'Path', 'Reason'});
end


function row = issueTableRow_(role, param, path, reason)
arguments
    role (1,1) string
    param (1,1) string
    path (1,1) string
    reason (1,1) string
end
row = table(string(role), string(param), string(path), string(reason), ...
    'VariableNames', {'Role', 'Parameter', 'Path', 'Reason'});
end


function T = emptyIssues_()
T = emptyIssueTable_();
end


function row = issueRow_(B, reason)
row = issueTableRow_(B.Role, B.Parameter, B.Path, reason);
end


function T = emptyContractTable_()
T = table(strings(0, 1), strings(0, 1), hw.Parameter.empty(0, 1), strings(0, 1), ...
    strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', {'Role', 'Parameter', 'Param', 'Source', 'Type', 'Access', ...
    'Capacity', 'DeclaredSize', 'N', 'SizeSource', 'NamePath', 'Note'});
end


function row = contractRow_(role, P, source, capacity, declared, N, sizeSource, nm, note)
arguments
    role (1,1) string
    P (1,1) hw.Parameter
    source (1,1) string
    capacity (1,1) double
    declared (1,1) double
    N (1,1) double
    sizeSource (1,1) string
    nm (1,1) string
    note (1,1) string
end
row = table(string(role), string(P.Name), P, string(source), string(P.Type), ...
    string(P.Access), capacity, declared, N, string(sizeSource), string(nm), string(note), ...
    'VariableNames', {'Role', 'Parameter', 'Param', 'Source', 'Type', 'Access', ...
    'Capacity', 'DeclaredSize', 'N', 'SizeSource', 'NamePath', 'Note'});
end


function T = emptyRaw_()
C = defaults_();
T = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), true(0, 1), 'VariableNames', C.RAW_VARIABLES);
end


function T = emptySummary_()
T = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    'VariableNames', {'Role', 'Parameter', 'Path', 'NRequested', 'NTransferred', ...
    'Iterations', 'Median_s', 'P5_s', 'P95_s', 'Max_s', 'MSamplesPerSec', 'MBPerSec'});
end


function T = emptyFit_()
T = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    false(0, 1), strings(0, 1), ...
    'VariableNames', {'Role', 'Path', 'NumSizes', 'NMin', 'NMax', 'Overhead_s', ...
    'PerSample_s', 'RSquared', 'TargetSamples', 'Predicted_s', ...
    'PredictedTwoBuffers_s', 'Extrapolated', 'Note'});
end


function T = emptyRoundTrip_()
T = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    false(0, 1), strings(0, 1), ...
    'VariableNames', {'Parameter', 'NWritten', 'NRead', 'MaxAbsError', ...
    'Tolerance', 'Pass', 'Note'});
end


function T = emptyFloor_()
T = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), ...
    'VariableNames', {'Role', 'Parameter', 'Path', 'NRequested', 'Backend_s', ...
    'Floor_s', 'AboveFloor_s'});
end
