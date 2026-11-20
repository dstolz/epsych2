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
% otherwise have to ask about by class comes from three hw.Interface hooks,
% parameterCapacity, isSimulated and transferContext.
%
% Four ROLES are measured, each filled by one contract parameter (named
% explicitly, or discovered by its default name -- see "contract"):
%   ScalarWrite  writable scalar                         default WScalar
%   ScalarRead   readable scalar                         default RScalar
%   Trigger      parameter flagged isTrigger             default BenchTrig (or !BenchTrig)
%   Buffers      writable (preferably readable) buffers  default Buf (or Buf_<N>)
% Each buffer is written and read back at every length in Sizes -- one tag
% timed at several lengths is what the Fit table needs -- or, with no Sizes,
% once at its own size. A role a backend
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
%   Sizes       - element counts to time every buffer at, e.g. [1024 4096].
%       A size above what the backend, BufferSizes or a Buf_<N> name says the
%       buffer holds is reported in results.Unsupported and skipped; where
%       none of those is known (hw.Software) the sizes are trusted. Default
%       [] (each buffer once, at its own size). A backend that reads a
%       whole tag back returns its full size whatever was written: once a
%       read has returned more than its block asked for, the later read
%       blocks of that buffer and path are not timed (they would repeat the
%       same transfer) and are listed in results.Unsupported. The read fit
%       then has one distinct length and reports no slope.
%   Repeats         - timed calls per measurement. Default 50.
%   Warmup          - calls discarded before them. Default 5.
%   VerifyRoundTrip - write a fresh vector to each readable buffer, read it
%       back, compare at float32 precision. Default true.
%   IncludeLookup   - also time each call by NAME, besides the pre-resolved
%       hw.Parameter ("by handle"), so the lookup cost -- what find_parameter
%       adds -- can be told from the transport and is plotted. A session
%       dispatches handles, so the by-handle times are the ones it pays.
%       Default true.
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
%   Progress - log what is being timed, and how long each measurement took,
%       as it runs (vprintf level 1, so it reaches the command window at the
%       default verbosity). A large buffer over a slow link can take minutes;
%       without this the call is silent until the end. Default true.
%   CancelFcn - function handle called with no arguments between timed calls;
%       when it returns true the run ends with the error
%       hw:benchmarkIO:Cancelled and no results. It is checked outside every
%       timed span, so it never adds to a measurement, and a call already in
%       progress (one large buffer write) finishes first. Make it yield to the
%       GUI (drawnow) if it reads a flag a button sets. Default [] (never).
%
% Returns:
%   results - struct with fields
%     Raw          long table: Role, Parameter, Backend, Path, NRequested,
%                  NTransferred, Iteration, Seconds, Accepted
%     Summary      per Role/Parameter/Path/NRequested: min, 5th percentile,
%                  median, mean, 95th percentile, max, and for buffers
%                  MSamples/s and MB/s at 4 bytes per sample. NTransferred is
%                  what moved; on a read it can exceed NRequested
%     Fit          per buffer role and path: t = Overhead + PerSample*N, the
%                  predicted time for TargetSamples and for two buffers,
%                  Extrapolated and ExtrapolationFactor
%     Lookup       per measurement timed both ways: by-handle and by-name
%                  medians, their difference, a rank-sum p-value and a Status
%                  ("resolved", "below resolution" or "negative")
%     RoundTrip    per buffer and size: samples written, read and compared,
%                  how many differ, in how many contiguous runs, where, the
%                  max error, pass
%     Floor        per Summary row: backend median, twin median, difference
%     Software     the twin's own results (empty when not run)
%     Contract     what filled each role, from where, what it holds, at what size
%     Unsupported  Role, Parameter, Path, Reason
%     Problems     blocks that threw, had writes rejected or returned varying
%                  lengths, and every failed round trip (Role "RoundTrip")
%     Environment  MATLAB, backend, modules, transfer context (device, link,
%                  calls, cycle usage), EPsych commit, verbosity levels
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
%   hw.Interface.isSimulated, hw.Interface.transferContext

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
    options.Sizes (1,:) double {mustBeInteger, mustBePositive} = []
    options.Repeats (1,1) double {mustBeInteger, mustBePositive} = 50
    options.Warmup (1,1) double {mustBeInteger, mustBeNonnegative} = 5
    options.VerifyRoundTrip (1,1) logical = true
    options.IncludeLookup (1,1) logical = true
    options.TargetSamples (1,1) double {mustBePositive, mustBeFinite} = 292969
    options.SaveTo (1,:) char = ''
    options.Plot (1,1) logical = true
    options.CompareToSoftware (1,1) logical = true
    options.Progress (1,1) logical = true
    options.CancelFcn = []
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
        'describe its in-memory call path only'], env.DisplayLabel)
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
unsupported = contract.Unsupported;
backend = string(class(iface));
runTimer = tic;

% A backend that reads a buffer's whole storage back moves the same samples
% whatever length was written before, so the second and later reads of that
% buffer on that path would time one transfer again under a different size.
% Keyed by Parameter|Path, recorded once a read returns MORE than its block
% asked for. A read returning fewer (a simulated backend's NaN) says nothing
% about the storage and does not count.
wholeReadKey = strings(0, 1);
wholeReadAsked = zeros(0, 1);
wholeReadMoved = zeros(0, 1);

progress_(options.Progress, 'hw.benchmarkIO: timing %s -- %d measurements of %d calls each (%d warm-up)', ...
    env.DisplayLabel, nBlocks, options.Repeats, options.Warmup)

for b = 1:nBlocks
    B = blocks(b);
    readKey = B.Parameter + "|" + B.Path;
    if B.Role == "BufferRead" && any(wholeReadKey == readKey)
        j = find(wholeReadKey == readKey, 1);
        reason = sprintf(['not timed at N=%d: the read at N=%d returned %d samples, the ' ...
            'whole buffer, so this read would repeat that same transfer'], ...
            B.NRequested, wholeReadAsked(j), wholeReadMoved(j));
        unsupported = appendRow_(unsupported, issueRow_(B, reason));
        progress_(options.Progress, 'hw.benchmarkIO: [%d/%d] %s, %s: %s', b, nBlocks, ...
            B.Role, char(pathWords_(B.Path)), reason)
        continue
    end

    % Said before the block runs, since one large buffer write can take long
    % enough that the operator needs to know it has not hung.
    progress_(options.Progress, 'hw.benchmarkIO: [%d/%d] %s, %s%s ...', b, nBlocks, ...
        B.Role, char(pathWords_(B.Path)), sizeSuffix_(B))
    blockTimer = tic;
    try
        checkCancel_(options.CancelFcn)
        [t, nOut, ok] = timeBlock_(iface, B.Kind, B.Target, B.Payload, nTotal, options.CancelFcn);
    catch ME
        if strcmp(ME.identifier, 'hw:benchmarkIO:Cancelled')
            rethrow(ME)
        end
        vprintf(0, 1, ME)
        problems = appendRow_(problems, issueRow_(B, string(ME.message)));
        progress_(options.Progress, 'hw.benchmarkIO: [%d/%d] FAILED: %s', b, nBlocks, ME.message)
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

    % A buffer block also says what its median came to as a line speed, and
    % a read says how many samples it actually moved.
    rateNote = '';
    if ismember(B.Role, ["BufferWrite", "BufferRead"])
        direction = "TX";
        if B.Role == "BufferRead"
            direction = "RX";
            moved = nOut(keep);
            rateNote = sprintf(', moved %d samples', round(median(moved)));
            if ~isempty(moved) && all(moved == moved(1)) && moved(1) > B.NRequested
                rateNote = [rateNote sprintf(' (the whole buffer, not the %d requested)', B.NRequested)];
                wholeReadKey = appendRow_(wholeReadKey, readKey);
                wholeReadAsked = appendRow_(wholeReadAsked, B.NRequested);
                wholeReadMoved = appendRow_(wholeReadMoved, moved(1));
            end
        end
        mbit = 8 * C.BYTES_PER_SAMPLE * median(nOut(keep)) / median(t(keep)) / 1e6;
        rateNote = sprintf('%s, %s %s', rateNote, direction, formatRate_(mbit));
    end
    % The spread beside the median, since a backend's occasional slow call
    % (scheduler, USB polling) is what a trial boundary actually waits on.
    tk = t(keep);
    pr = prctile(tk, [5 95]);
    progress_(options.Progress, 'hw.benchmarkIO: [%d/%d] median %s over %d calls%s (%.1f s)', ...
        b, nBlocks, formatTime_(median(tk)), n, rateNote, toc(blockTimer))
    progress_(options.Progress, 'hw.benchmarkIO: [%d/%d]   min %s | p5 %s | mean %s | p95 %s | max %s', ...
        b, nBlocks, formatTime_(min(tk)), formatTime_(pr(1)), formatTime_(mean(tk)), ...
        formatTime_(pr(2)), formatTime_(max(tk)))
    if ~all(ok(keep))
        progress_(options.Progress, 'hw.benchmarkIO: [%d/%d] WARNING: %d of %d writes were reported failed', ...
            b, nBlocks, sum(~ok(keep)), n)
    end
end

raw = vertcat(rawTables{~cellfun(@isempty, rawTables)});
if isempty(raw)
    raw = emptyRaw_();
end

results = struct();
results.Raw = raw;
results.Summary = summarize_(raw);
results.Fit = fitTable_(results.Summary, options.TargetSamples);
results.Lookup = lookupTable_(raw, results.Summary);

% A buffer that could hold TargetSamples but was not timed on both sides of
% it gets an extrapolated prediction it did not need to. Said, never fixed:
% adding sizes is the caller's decision, since each costs device time.
targetNotes = targetNotes_(contract.Table, options.TargetSamples);
for k = 1:numel(targetNotes)
    vprintf(1, 'hw.benchmarkIO: %s', targetNotes(k))
end
results.Fit = annotateFit_(results.Fit, targetNotes);

if options.VerifyRoundTrip
    progress_(options.Progress, 'hw.benchmarkIO: verifying the transfer (%d write-and-read-back checks) ...', ...
        sum([contract.Buffers.Readable]))
    results.RoundTrip = verifyRoundTrip_(iface, contract.Buffers, options.CancelFcn);
    if ~isempty(results.RoundTrip)
        progress_(options.Progress, 'hw.benchmarkIO: round trip: %d of %d passed', ...
            sum(results.RoundTrip.Pass), height(results.RoundTrip))
    end
else
    results.RoundTrip = emptyRoundTrip_();
end
% A failed round trip means the buffer times may not describe a clean
% transfer, so it is a Problem, not only a row in RoundTrip.
problems = appendRow_(problems, roundTripProblems_(results.RoundTrip, env.IsSimulated));

results.Floor = emptyFloor_();
results.Software = [];
if options.CompareToSoftware && ~env.IsSimulated
    progress_(options.Progress, 'hw.benchmarkIO: timing the same calls on an in-memory Software twin (the floor) ...')
    [results.Floor, results.Software] = softwareFloor_(contract, results.Summary, options);
elseif options.CompareToSoftware
    vprintf(2, 'hw.benchmarkIO: Software floor skipped; the interface is itself simulated')
end

% The handles stay internal: a saved hw.Parameter drags its whole
% interface, device handle included, into the MAT file.
results.Contract = removevars(contract.Table, 'Param');
results.Unsupported = unsupported;
results.Problems = problems;
results.Environment = env;
results.Options = rmfield(options, intersect(fieldnames(options), ...
    {'ScalarWrite', 'ScalarRead', 'Trigger', 'Buffers', 'CancelFcn'}));
results.Figure = [];
results.Files = struct('Mat', '', 'Csv', '', 'SummaryCsv', '');

progress_(options.Progress, 'hw.benchmarkIO: done in %.1f s', toc(runTimer))

if options.Plot
    results.Figure = plot_(results);
end

if ~isempty(options.SaveTo)
    results.Files = save_(results, options.SaveTo);
end
end


% =====================================================================
function progress_(on, fmt, varargin)
% Operator-facing progress, one record per call. Level 1 so the command
% window shows it at the default verbosity; nothing here can throw.
if on
    vprintf(1, fmt, varargin{:})
end
end


function w = pathWords_(path)
% The call path in words: param is the pre-resolved hw.Parameter.
w = replace(string(path), ["param", "name"], ["by handle", "by name"]);
end


function s = sizeSuffix_(B)
% ", N=4096" for a buffer write; ", N=4096 requested" for a read, whose
% backend may return more (the line after it says what moved); nothing for
% a scalar.
s = '';
if B.Role == "BufferWrite"
    s = sprintf(', N=%d', B.NRequested);
elseif B.Role == "BufferRead"
    s = sprintf(', N=%d requested', B.NRequested);
end
end


% =====================================================================
function C = defaults_()
C.ROLES = ["ScalarWrite", "ScalarRead", "Trigger"];
C.DEFAULT_NAMES = {{'WScalar'}, {'RScalar'}, {'BenchTrig', '!BenchTrig'}};
% A single tag named Buf, or the older one-tag-per-size Buf_<N>.
% The one capture holds '_<N>' or nothing (MATLAB returns no token at all for
% a group nested inside an optional non-capturing one).
C.BUFFER_PATTERN = '^Buf(_\d+)?$';
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
% Two-sided rank-sum level at which a by-name/by-handle difference counts as
% resolved. Below it the difference is inside the spread of the calls.
C.LOOKUP_ALPHA = 0.05;
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
    rows = appendRow_(rows, contractRow_(role, P, source, NaN, NaN, NaN, 1, "scalar", nm, ""));
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
            "no parameter named Buf or Buf_<N>"));
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
    % What the buffer is known to hold, where something other than a read
    % said so; kept for the TargetSamples note, since N is reused below.
    holds = NaN;
    if ismember(sizeSource, ["parameterCapacity", "BufferSizes", "name"])
        holds = N;
    end

    % Sizes asks for several lengths on this one tag. A length is held to
    % what the backend or the caller said the tag holds; where the size came
    % from a read or is unknown, the request is trusted -- an hw.Software
    % buffer has no capacity, and a length of 1 read from its initial Value
    % is not a limit.
    sizes = N;
    if ~isempty(options.Sizes)
        sizes = unique(options.Sizes, 'stable');
        if ismember(sizeSource, ["parameterCapacity", "BufferSizes", "name"])
            limit = N;
            tooBig = sizes > limit;
            if any(tooBig)
                for s = sizes(tooBig)
                    unsupported = appendRow_(unsupported, issueTableRow_("Buffers", string(p.Name), "", ...
                        sprintf('size %d exceeds the %d samples this buffer holds', s, limit)));
                end
                sizes = sizes(~tooBig);
            end
            if isempty(sizes)
                continue
            end
        end
        sizeSource = "Sizes";
    end

    reason = bufferRequirement_(p, max(sizes));
    if reason ~= ""
        if explicit
            error('hw:benchmarkIO:RoleRequirement', ...
                'Role Buffers: parameter "%s" %s.', p.Name, reason);
        end
        unsupported = appendRow_(unsupported, issueTableRow_("Buffers", string(p.Name), "", reason));
        continue
    end

    [nm, nameReason] = namePath_(iface, p);
    readable = ~strcmp(p.Access, 'Write');
    for N = sizes
        data = randomPayload_(rs, N);
        rows = appendRow_(rows, contractRow_("Buffers", p, source, capacity, d, holds, N, sizeSource, nm, note));

        [blocks, unsupported] = addBlocks_(blocks, unsupported, "BufferWrite", "bufferwrite", p, nm, ...
            nameReason, {data}, N, options.IncludeLookup);

        if readable
            [blocks, unsupported] = addBlocks_(blocks, unsupported, "BufferRead", "read", p, nm, ...
                nameReason, [], N, options.IncludeLookup);
        end
        buffers = appendRow_(buffers, struct('Parameter', p, 'N', N, 'Readable', readable));
    end
    if ~readable
        unsupported = appendRow_(unsupported, issueTableRow_("BufferRead", string(p.Name), "", ...
            "write-only parameter"));
    end
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
function [t, nOut, ok] = timeBlock_(iface, kind, target, payload, nTotal, cancelFcn)
% Time nTotal calls of one kind, one call per tic/toc. Each kind has its own
% loop so nothing but the interface call sits between tic and toc. The cancel
% check runs between calls, outside the timed span, so a stop takes effect
% after the call in progress and never inside a measurement.
arguments
    iface (1,1) hw.Interface
    kind (1,1) string {mustBeMember(kind, ["scalarwrite", "bufferwrite", "read", "trigger"])}
    target
    payload
    nTotal (1,1) double {mustBeInteger, mustBePositive}
    cancelFcn
end
t = zeros(nTotal, 1);
nOut = zeros(nTotal, 1);
ok = true(nTotal, 1);

switch kind
    case "scalarwrite"
        % Alternate two values so a backend that skips an unchanged write
        % still does the work.
        for k = 1:nTotal
            checkCancel_(cancelFcn)
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
            checkCancel_(cancelFcn)
            t0 = tic;
            r = iface.set_parameter(target, payload);
            t(k) = toc(t0);
            ok(k) = writeAccepted_(r);
        end
        nOut(:) = numel(payload{1});

    case "read"
        for k = 1:nTotal
            checkCancel_(cancelFcn)
            t0 = tic;
            v = iface.get_parameter(target);
            t(k) = toc(t0);
            nOut(k) = transferredCount_(v);
        end

    case "trigger"
        for k = 1:nTotal
            checkCancel_(cancelFcn)
            t0 = tic;
            iface.trigger(target);
            t(k) = toc(t0);
        end
        nOut(:) = 1;
end
end


function checkCancel_(cancelFcn)
% Ends the run when the caller's CancelFcn says so. Thrown as an error so it
% unwinds through every loop at once; run_ lets this one identifier through
% its per-block catch, which would otherwise record it as a failed block.
if ~isempty(cancelFcn) && cancelFcn()
    vprintf(1, 'hw.benchmarkIO: stopped by the caller')
    error('hw:benchmarkIO:Cancelled', 'The benchmark was stopped by the caller.');
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

% The requested size is part of the key: one buffer tag is timed at several
% lengths, and pooling them would be a median over different transfers.
[g, keys] = findgroups(raw(:, {'Role', 'Parameter', 'Path', 'NRequested'}));
nG = height(keys);
NReq = keys.NRequested;
NTr = zeros(nG, 1);
nIt = zeros(nG, 1);
mn = zeros(nG, 1);
p5 = zeros(nG, 1);
med = zeros(nG, 1);
avg = zeros(nG, 1);
p95 = zeros(nG, 1);
mx = zeros(nG, 1);
for k = 1:nG
    m = g == k;
    s = raw.Seconds(m);
    NTr(k) = median(raw.NTransferred(m));
    nIt(k) = numel(s);
    mn(k) = min(s);
    med(k) = median(s);
    avg(k) = mean(s);
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
% The same rate as a line speed: TX is BufferWrite, RX is BufferRead.
mbitps = 8 * mbps;

S = [keys, table(NTr, nIt, mn, p5, med, avg, p95, mx, msps, mbps, mbitps, ...
    'VariableNames', {'NTransferred', 'Iterations', 'Min_s', 'P5_s', 'Median_s', ...
    'Mean_s', 'P95_s', 'Max_s', 'MSamplesPerSec', 'MBPerSec', 'MbitPerSec'})];
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
            f.PredictedTwoBuffers_s, f.Extrapolated, f.ExtrapolationFactor, f.Note, ...
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
    'ExtrapolationFactor', NaN, 'Note', "");
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
    % How far outside the sizes timed: TargetSamples over the largest, or
    % the smallest over TargetSamples; 1 inside the range.
    f.ExtrapolationFactor = max([1, T / f.NMax, f.NMin / T]);
end
if f.Overhead_s < 0
    f.Note = "negative overhead: the fixed cost is below what these sizes resolve";
end
end


function notes = targetNotes_(contractTable, target)
% One sentence per buffer timed at two or more sizes that holds at least
% TargetSamples but whose timed sizes do not bracket it, so its prediction
% is extrapolated needlessly.
% Read from the contract (Role, Parameter, Holds, N), so run_ and plot_ say
% the same thing.
arguments
    contractTable table
    target (1,1) double
end
notes = strings(0, 1);
rows = contractTable(contractTable.Role == "Buffers", :);
for name = unique(rows.Parameter, 'stable')'
    r = rows(rows.Parameter == name, :);
    holds = r.Holds(1);
    sizes = reshape(r.N, 1, []);
    % One size gives no fit and so no prediction to call extrapolated.
    if numel(unique(sizes)) < 2 || ~(isfinite(holds) && holds >= target) || ...
            (min(sizes) <= target && target <= max(sizes))
        continue
    end
    if max(sizes) < target
        fix = sprintf('time a size from %d up to the %d it holds', ceil(target), holds);
    else
        fix = sprintf('time a size of %d or less', floor(target));
    end
    notes = appendRow_(notes, string(sprintf(['%s holds %d samples, enough for ' ...
        'TargetSamples (%d), but the sizes timed (%s) do not bracket it, so the ' ...
        'prediction is extrapolated; to interpolate, %s'], ...
        name, holds, round(target), strjoin(string(sizes), ', '), fix)));
end
end


function F = annotateFit_(F, notes)
% Append the TargetSamples notes to every extrapolated Fit row's Note.
if isempty(notes) || isempty(F)
    return
end
txt = strjoin(notes, " ");
for k = find(F.Extrapolated)'
    F.Note(k) = strtrim(strjoin([F.Note(k), txt], " "));
end
end


% =====================================================================
function RT = verifyRoundTrip_(iface, buffers, cancelFcn)
% Untimed: write a vector the timed blocks never wrote, read it back through
% the pre-resolved parameter, compare at float32 precision. Where samples
% differ, say how many and how they are laid out: one contiguous run is
% what a buffer the device itself is writing into (a running write index)
% would leave; scattered samples point elsewhere. Only the length written
% is compared -- a whole-tag read returns more, whose contents are unknown.
C = defaults_();
RT = emptyRoundTrip_();
rs = RandStream('mt19937ar', 'Seed', C.SEED + 1);
for k = 1:numel(buffers)
    checkCancel_(cancelFcn)   % outside the try below, which logs what it catches
    if ~buffers(k).Readable
        continue
    end
    P = buffers(k).Parameter;
    N = buffers(k).N;
    data = randomPayload_(rs, N);
    nRead = NaN;
    n = 0;
    maxErr = NaN;
    tol = double(max(eps(abs(data))));
    pass = false;
    M = mismatchRuns_(false(1, 0));
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
            % ~(<=) rather than >, so a NaN read back counts as a mismatch.
            bad = ~(err <= double(eps(abs(data(1:n)))));
            if n > 0
                maxErr = max(err);
            end
            M = mismatchRuns_(bad);
            pass = nRead >= N && ~any(bad);

            parts = strings(0, 1);
            if nRead < N
                parts = appendRow_(parts, string(sprintf('read returned %d of %d samples', nRead, N)));
            elseif nRead > N
                parts = appendRow_(parts, string(sprintf('read returned %d samples; the first %d compared', nRead, N)));
            end
            if M.Count > 0
                parts = appendRow_(parts, string(sprintf('%d of %d samples differ (largest error %.3g), %s', ...
                    M.Count, n, maxErr, M.Text)));
            end
            if ~accepted
                parts = appendRow_(parts, "write reported failed");
            end
            note = "";
            if ~isempty(parts)
                note = strjoin(parts, "; ");
            end
        end
    catch ME
        vprintf(0, 1, ME)
        note = string(ME.message);
    end
    RT = appendRow_(RT, table(string(P.Name), N, nRead, n, M.Count, M.Runs, M.First, M.Last, ...
        maxErr, tol, pass, string(note), 'VariableNames', RT.Properties.VariableNames));
end
end


function M = mismatchRuns_(bad)
% Count and lay out the mismatched samples: how many, in how many contiguous
% runs, first and last index, and a phrase saying so. A run that reaches
% both ends of what was compared is reported as one that may wrap, since a
% circular write index passing the end of the buffer leaves exactly that.
arguments
    bad (1,:) logical
end
idx = find(bad);
M = struct('Count', numel(idx), 'Runs', 0, 'First', NaN, 'Last', NaN, 'Text', "");
if isempty(idx)
    return
end
breaks = find(diff(idx) > 1);
M.Runs = numel(breaks) + 1;
M.First = idx(1);
M.Last = idx(end);
if M.Count == 1
    M.Text = sprintf('at sample %d', M.First);
elseif M.Runs == 1
    M.Text = sprintf(['in one contiguous run (samples %d-%d), consistent with the ' ...
        'device writing into the buffer while the host does'], M.First, M.Last);
elseif M.Runs == 2 && M.First == 1 && M.Last == numel(bad)
    M.Text = sprintf(['in two runs touching both ends (samples 1-%d and %d-%d), ' ...
        'consistent with a write index wrapping round the buffer'], ...
        idx(breaks(1)), idx(breaks(1) + 1), M.Last);
else
    M.Text = sprintf('in %d separate runs, from sample %d to %d', M.Runs, M.First, M.Last);
end
M.Text = string(M.Text);
end


function T = roundTripProblems_(RT, isSimulated)
% One Problems row per failed round trip, logged as it is made. On a
% simulated interface the failure may be by design -- a backend that keeps
% nothing it is written cannot pass -- so it is said and logged at level 1.
T = emptyIssues_();
fails = RT(~RT.Pass, :);
for k = 1:height(fails)
    reason = "round trip failed at N=" + fails.NWritten(k) + ": " + fails.Note(k);
    if isSimulated
        reason = reason + " (the interface is simulated; one that does not keep " + ...
            "what it is written cannot pass this check)";
        vprintf(1, 'hw.benchmarkIO: "%s" %s', fails.Parameter(k), reason)
    else
        vprintf(0, 1, 'hw.benchmarkIO: "%s" %s', fails.Parameter(k), reason)
    end
    T = appendRow_(T, issueTableRow_("RoundTrip", fails.Parameter(k), "param", reason));
end
end


% =====================================================================
function [Floor, twinResults] = softwareFloor_(contract, S, options)
% The same contract, the same sizes, on an in-memory twin: the call into a
% backend's set_parameter/get_parameter/trigger with no transport under it.
% It is not all of what a real backend adds besides the transport: the twin
% logs nothing per write, makes no connection probe, and answers reads
% without resolving a name (see documentation/hw/hw_benchmarkIO.md).
arguments
    contract (1,1) struct
    S table
    options (1,1) struct
end
[twin, map] = buildTwin_(contract);
% A cancelled run unwinds through here; do not leave the twin behind.
twinGuard = onCleanup(@() delete(twin));

C = defaults_();
roles = C.ROLES;
args = cell(1, 2 * numel(roles));
for r = 1:numel(roles)
    args{2 * r - 1} = char(roles(r));
    args{2 * r} = twinFor_(map, contract.Table, roles(r));
end
bufRows = contract.Table(contract.Table.Role == "Buffers", :);
[bufNames, first] = unique(bufRows.Parameter, 'stable');
[~, loc] = ismember(bufNames, map.Name);
qb = reshape(map.Twin(loc), 1, []);

% The twin has no capacity to report, so it is told the sizes the device
% was actually timed at: the requested list when there was one (trimmed per
% buffer by what the device holds, hence the union), else each buffer's own.
if isempty(options.Sizes)
    sizeArgs = {'BufferSizes', reshape(bufRows.N(first), 1, [])};
else
    sizeArgs = {'Sizes', reshape(unique(bufRows.N), 1, [])};
end

twinResults = run_(twin, args{:}, sizeArgs{:}, 'Buffers', qb, ...
    'Repeats', options.Repeats, 'Warmup', options.Warmup, 'VerifyRoundTrip', false, ...
    'IncludeLookup', options.IncludeLookup, 'TargetSamples', options.TargetSamples, ...
    'Plot', false, 'CompareToSoftware', false, 'Progress', false, 'CancelFcn', options.CancelFcn);
twinResults.Figure = [];

T = twinResults.Summary;
Floor = emptyFloor_();
for k = 1:height(S)
    m = T.Role == S.Role(k) & T.Parameter == S.Parameter(k) & T.Path == S.Path(k) ...
        & T.NRequested == S.NRequested(k);
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
    options.Sizes (1,:) double {mustBeInteger, mustBePositive} = []
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
    nameN = str2double(strrep(tok{1}, '_', ''));
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
n = cellfun(@(c) str2double(strrep(c{1}, '_', '')), tok(hit));
n(isnan(n)) = 0;   % the bare Buf sorts first
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

% What the backend says the timings depend on (device model, link, the
% calls a buffer goes through, cycle usage), from the transferContext hook
% so nothing here has to know which backend this is. Read before any timing.
env.Transfer = hw.Interface.transferContextRecord();
try
    tc = iface.transferContext();
    if isstruct(tc)
        env.Transfer = tc;
    end
catch ME
    vprintf(2, 'hw.benchmarkIO: transfer context not available: %s', ME.message)
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
fig.Position(3:4) = [1100 660];
tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('%s (%s), %s', results.Environment.DisplayLabel, ...
    results.Environment.BackendClass, results.Environment.Date), 'Interpreter', 'none');

% ---- buffers: median with 5th-95th percentile bars, fit, prediction
ax = nexttile(tl, 1);
hold(ax, 'on')
grid(ax, 'on')
colors = lines(4);
ci = 0;
seriesColor = struct();   % one colour per series, shared with the bit-rate panel
for role = ["BufferWrite", "BufferRead"]
    for path = ["param", "name"]
        m = S.Role == role & S.Path == path;
        if ~any(m)
            continue
        end
        ci = ci + 1;
        c = colors(mod(ci - 1, size(colors, 1)) + 1, :);
        seriesColor.(char(role + "_" + path)) = c;
        x = fitAbscissa_(S.Role(m), S.NRequested(m), S.NTransferred(m));
        y = 1e3 * S.Median_s(m);
        errorbar(ax, x, y, y - 1e3 * S.P5_s(m), 1e3 * S.P95_s(m) - y, 'o', ...
            'Color', c, 'MarkerFaceColor', c, 'DisplayName', char(pathLabel_(role, path)));

        f = F(F.Role == role & F.Path == path, :);
        if ~isempty(f) && isfinite(f.PerSample_s(1))
            plotPrediction_(ax, x, f(1, :), c);
        end
    end
end
set(ax, 'XScale', 'log')
xlabel(ax, 'Samples per call')
ylabel(ax, 'Time per call (ms)')
title(ax, 'Buffers')
subtitle(ax, {'Dots: median; bars: 5th-95th percentile; line: linear fit (dashed outside the sizes timed);', ...
    'pentagram: predicted at TargetSamples (hollow: extrapolated).'})
if ci > 0
    xline(ax, results.Options.TargetSamples, ':', 'TargetSamples', 'HandleVisibility', 'off');
    lgd = legend(ax);
    lgd.Location = 'northwest';
    lgd.Interpreter = 'none';
else
    text(ax, 0.5, 0.5, 'No buffer measurements', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center')
end

% A size the buffer cannot hold is skipped, so its point is simply absent;
% say so here, or the plot reads as a measurement that failed silently.
skipped = skippedSizeNotes_(results.Unsupported);
if ~isempty(skipped)
    text(ax, 0.98, 0.03, [{'Sizes skipped (larger than the buffer holds):'}; cellstr(skipped)], ...
        'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
        'FontSize', 9, 'Interpreter', 'none', 'BackgroundColor', 'w', ...
        'EdgeColor', [0.85 0.33 0.1], 'Margin', 4);
end

% A buffer that could hold TargetSamples but was not timed either side of it.
notes = targetNotes_(results.Contract, results.Options.TargetSamples);
if ~isempty(notes)
    text(ax, 0.98, 0.97, cellstr(notes), 'Units', 'normalized', ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
        'FontSize', 8, 'Interpreter', 'none', 'BackgroundColor', 'w', ...
        'EdgeColor', [0.85 0.33 0.1], 'Margin', 4, 'Tag', 'benchmarkIO:targetNote');
end

% A failed round trip heads the whole figure: every buffer time on it may
% describe something other than a clean transfer.
failed = results.RoundTrip(~results.RoundTrip.Pass, :);
if ~isempty(failed)
    msg = ["ROUND TRIP FAILED -- the buffer times may not describe a clean transfer:"; ...
        failed.Parameter + ", N=" + failed.NWritten + ": " + failed.Note];
    st = subtitle(tl, cellstr(msg));
    st.Color = [0.75 0 0];
    st.FontWeight = 'bold';
    st.Interpreter = 'none';
end

% ---- bit rate: what the buffer times above come to as a line speed
plotBitRate_(nexttile(tl, 3), S, F, seriesColor);

% ---- scalars and triggers
ax = nexttile(tl, 2);
m = ismember(S.Role, ["ScalarWrite", "ScalarRead", "Trigger"]);
if any(m)
    % Every timed call, not a summary of them: call times are right-skewed
    % with occasional scheduler spikes, which a median bar hides. One box
    % (median, quartiles) per measurement with each call drawn over it, on a
    % log axis because the paths differ by decades.
    % Role by role, by handle first, so the two paths sit side by side.
    labels = strings(0, 1);
    for role = ["ScalarWrite", "ScalarRead", "Trigger"]
        for path = ["param", "name"]
            if any(S.Role == role & S.Path == path)
                labels(end+1, 1) = pathLabel_(role, path);
            end
        end
    end
    labels = cellstr(labels);
    R = results.Raw;
    key = pathLabel_(R.Role, R.Path);
    keep = ismember(key, string(labels)) & R.Seconds > 0;   % log axis cannot show 0
    grp = categorical(cellstr(key(keep)), labels, labels, 'Ordinal', true);
    ms = 1e3 * R.Seconds(keep);
    hold(ax, 'on')
    boxchart(ax, grp, ms, 'MarkerStyle', 'none', 'BoxFaceAlpha', 0.25, ...
        'BoxEdgeColor', [0.15 0.15 0.15], 'WhiskerLineColor', [0.15 0.15 0.15]);
    swarmchart(ax, grp, ms, 8, [0 0.447 0.741], 'filled', 'MarkerFaceAlpha', 0.45, ...
        'XJitterWidth', 0.5);
    set(ax, 'YScale', 'log', 'TickLabelInterpreter', 'none')
    ylabel(ax, 'Time per call (ms, log scale)')
    % The median above each group's slowest call, in whatever unit reads best.
    for k = 1:numel(labels)
        v = ms(grp == labels{k});
        if ~isempty(v)
            text(ax, k, max(v) * 1.25, formatTime_(1e-3 * median(v)), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                'FontSize', 9, 'Interpreter', 'none', 'Clipping', 'off');
        end
    end
    if ~isempty(ms)
        ylim(ax, [min(ms) / 1.5, max(ms) * 2.5])
    end
else
    text(ax, 0.5, 0.5, 'No scalar or trigger measurements', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center')
end
grid(ax, 'on')
title(ax, 'Scalars and triggers')
subtitle(ax, {'Box: quartiles; dots: every timed call; label: median.', ...
    'By handle: the call is given the hw.Parameter. By name: it is given the name.'})

% ---- what looking a parameter up by name adds
plotLookup_(nexttile(tl, 4), results.Lookup);
end


function plotPrediction_(ax, x, f, c)
% The fit line and the TargetSamples prediction for one series. The line is
% solid over the sizes timed and dashed beyond them; the pentagram is hollow
% and its label says by how much when the prediction is extrapolated.
a = max(1, min(x));
b = max(x);
T = f.TargetSamples;
fitMs = @(xx) 1e3 * (f.Overhead_s + f.PerSample_s * xx);
xs = logspace(log10(a), log10(b), 64);
plot(ax, xs, fitMs(xs), '-', 'Color', c, 'HandleVisibility', 'off');
if T > b
    xs = logspace(log10(b), log10(T), 32);
elseif T < a
    xs = logspace(log10(T), log10(a), 32);
else
    xs = [];
end
if ~isempty(xs)
    plot(ax, xs, fitMs(xs), '--', 'Color', c, 'HandleVisibility', 'off', ...
        'Tag', 'benchmarkIO:extrapolatedFit');
end

if f.Extrapolated
    face = 'w';
    where = "beyond the largest size timed";
    if T < f.NMin
        where = "below the smallest size timed";
    end
    label = sprintf('%s, EXTRAPOLATED %.1fx %s', formatTime_(f.Predicted_s), ...
        f.ExtrapolationFactor, where);
else
    face = c;
    label = sprintf('%s predicted', formatTime_(f.Predicted_s));
end
plot(ax, T, 1e3 * f.Predicted_s, 'p', 'MarkerSize', 12, 'Color', c, ...
    'MarkerFaceColor', face, 'LineWidth', 1.25, 'HandleVisibility', 'off', ...
    'Tag', 'benchmarkIO:prediction');
text(ax, T, 1e3 * f.Predicted_s, {'', label}, 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'top', 'FontSize', 8, 'Color', c, 'Interpreter', 'none', ...
    'Clipping', 'off', 'Tag', 'benchmarkIO:predictionLabel');
end


function plotBitRate_(ax, S, F, seriesColor)
% TX (BufferWrite) and RX (BufferRead) as bits per second against the samples
% moved, by handle: the transport, with no lookup in it. The rate is what the
% Summary's MbitPerSec says -- 32 bits per sample over the median call time --
% so it grows with size while a fixed per-call cost is amortized, and the fit
% gives the ceiling that curve approaches (1 / PerSample_s).
C = defaults_();
bitsPerSample = 8 * C.BYTES_PER_SAMPLE;
hold(ax, 'on')
grid(ax, 'on')
roles = ["BufferWrite", "BufferRead"];
names = ["TX (buffer write)", "RX (buffer read)"];
plotted = 0;
top = 0;
bottom = Inf;
for k = 1:2
    m = S.Role == roles(k) & S.Path == "param";
    if ~any(m)
        continue
    end
    plotted = plotted + 1;
    x = fitAbscissa_(S.Role(m), S.NRequested(m), S.NTransferred(m));
    y = S.MbitPerSec(m);
    c = seriesColor.(char(roles(k) + "_param"));
    plot(ax, x, y, '-o', 'Color', c, 'MarkerFaceColor', c, 'DisplayName', char(names(k)));
    for j = 1:numel(x)
        text(ax, x(j), y(j), formatRate_(y(j)), 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'FontSize', 9, 'Interpreter', 'none', 'Clipping', 'off');
    end
    top = max([top; y(isfinite(y))]);
    bottom = min([bottom; y(isfinite(y) & y > 0)]);
end

if plotted == 0
    axis(ax, 'off')
    text(ax, 0.5, 0.5, 'No buffer measurements', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center')
    return
end

% The ceiling the fit implies, where it exists and is on the scale of the data.
% A fit with no measurable per-sample cost (an in-memory backend) has an
% unbounded one, which would only flatten the axis.
for k = 1:2
    f = F(F.Role == roles(k) & F.Path == "param", :);
    if isempty(f) || ~isfinite(f.PerSample_s(1)) || f.PerSample_s(1) <= 0
        continue
    end
    limit = bitsPerSample / f.PerSample_s(1) / 1e6;
    if limit > 10 * top
        continue
    end
    c = seriesColor.(char(roles(k) + "_param"));
    yline(ax, limit, ':', ['limit ' formatRate_(limit)], 'Color', c, ...
        'LabelHorizontalAlignment', 'right', 'HandleVisibility', 'off', 'Interpreter', 'none');
    top = max(top, limit);
end

% Log both ways: TX and RX routinely differ by decades, and on a linear axis
% the slower direction is a line on the floor.
set(ax, 'XScale', 'log', 'YScale', 'log')
if top > 0 && isfinite(bottom)
    ylim(ax, [bottom / 2, top * 4])
end
xlabel(ax, 'Samples moved per call')
ylabel(ax, 'Bit rate (Mbit/s)')
title(ax, 'Throughput')
subtitle(ax, {sprintf('Bit rate = %d bits x samples moved / median call time, by handle.', bitsPerSample), ...
    'Dotted: ceiling implied by the fit (1 / per-sample cost).'})
lgd = legend(ax);
lgd.Location = 'southeast';
lgd.Interpreter = 'none';
end


function txt = formatRate_(mbit)
% A bit rate in the unit that keeps three significant figures readable.
arguments
    mbit (1,1) double
end
if ~isfinite(mbit)
    txt = 'n/a';
elseif abs(mbit) >= 1e3
    txt = sprintf('%.3g Gbit/s', mbit / 1e3);
elseif abs(mbit) >= 1
    txt = sprintf('%.3g Mbit/s', mbit);
elseif abs(mbit) >= 1e-3
    txt = sprintf('%.3g kbit/s', 1e3 * mbit);
else
    txt = sprintf('%.3g bit/s', 1e6 * mbit);
end
end


function notes = skippedSizeNotes_(U)
% One line per buffer that had requested sizes skipped, naming the sizes and
% what the buffer holds: "Buf: 4096, 65536 (holds 1024)". Read from the
% Unsupported rows resolveContract_ writes, so plot and status agree.
notes = strings(0, 1);
if isempty(U)
    return
end
rows = U(U.Role == "Buffers" & contains(U.Reason, "exceeds"), :);
for name = unique(rows.Parameter, 'stable')'
    % cellstr: regexp wraps a cell input per element, but returns a scalar
    % string's tokens bare, which would make one skipped size a different shape.
    r = cellstr(rows.Reason(rows.Parameter == name));
    sz = regexp(r,'^size (\d+) exceeds the (\d+) samples', 'tokens', 'once');
    sz = vertcat(sz{:});
    notes(end+1, 1) = sprintf('%s: %s (holds %s)', name, strjoin(sz(:, 1), ', '), sz{1, 2});
end
end


function plotLookup_(ax, L)
% By-name median minus by-handle median, per measurement, from the Lookup
% table. Only a resolved difference is drawn as a bar: one inside the spread
% of the calls, or a negative one (drift between the two measurements, since
% a lookup cannot make a call faster), is written at zero instead, with why.
if isempty(L)
    axis(ax, 'off')
    text(ax, 0.5, 0.5, {'Lookup cost not measured.', 'Run with IncludeLookup=true.'}, ...
        'Units', 'normalized', 'HorizontalAlignment', 'center')
    return
end

resolved = L.Status == "resolved";
lab = lookupLabels_(L);
cost = L.Cost_s;
shown = cost;
shown(~resolved) = NaN;
ref = max(abs(cost(resolved)));
if isempty(ref) || ~isfinite(ref) || ref == 0
    ref = max(abs(cost));
end
[scale, unit] = timeUnit_(ref);
x = categorical(cellstr(lab), cellstr(lab), cellstr(lab), 'Ordinal', true);
bar(ax, x, scale * shown, 0.6, 'FaceColor', [0.85 0.33 0.1])
hold(ax, 'on')
set(ax, 'TickLabelInterpreter', 'none')
ylabel(ax, sprintf('Added by name lookup (%s)', unit))
for k = 1:numel(cost)
    if resolved(k)
        txt = formatTime_(cost(k));
        y = scale * cost(k);
        clr = [0 0 0];
    elseif L.Status(k) == "below resolution"
        txt = {'below resolution', sprintf('(%s, p = %.2g)', formatTime_(cost(k)), L.PValue(k))};
        y = 0;
        clr = [0.4 0.4 0.4];
    else
        txt = {sprintf('by name %s faster:', formatTime_(-cost(k))), 'not a cost'};
        y = 0;
        clr = [0.4 0.4 0.4];
    end
    text(ax, k, y, txt, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', 9, 'Interpreter', 'none', 'Clipping', 'off', 'Color', clr, ...
        'Tag', 'benchmarkIO:lookupLabel');
end
yl = ylim(ax);
ylim(ax, [min(yl(1), 0) - 0.08 * diff(yl), yl(2) + 0.25 * diff(yl)])
grid(ax, 'on')
title(ax, 'Lookup cost')
C = defaults_();
subtitle(ax, {'By-name median minus by-handle median: what find_parameter adds per call.', ...
    sprintf(['Drawn only where a rank-sum test resolves it (p < %.2g). ' ...
    'A session dispatches handles, so it does not pay this.'], C.LOOKUP_ALPHA)})
ax.Subtitle.Interpreter = 'none';   % find_parameter is not a subscript
end


function lab = lookupLabels_(L)
% "ScalarWrite"; "BufferWrite, 4096 samples": a buffer row is labelled by
% the samples the call moved, which for a read is what came back, not the
% length requested. The parameter is added where that alone is ambiguous.
lab = L.Role;
isBuf = ismember(L.Role, ["BufferWrite", "BufferRead"]);
lab(isBuf) = L.Role(isBuf) + ", " + L.NMoved(isBuf) + " samples";
[~, ~, g] = unique(lab);
dup = accumarray(g, 1) > 1;
lab(dup(g)) = lab(dup(g)) + " (" + L.Parameter(dup(g)) + ")";
end


function L = lookupTable_(raw, S)
% One row per measurement timed both ways, scalars first: the by-handle and
% by-name medians, their difference, a two-sided Wilcoxon rank-sum p-value
% over the two sets of timed calls, and a Status:
%   "resolved"         p < LOOKUP_ALPHA and the by-name calls were slower
%   "below resolution" p >= LOOKUP_ALPHA: inside the spread of the calls
%   "negative"         p < LOOKUP_ALPHA but the by-name calls were FASTER,
%                      which a lookup cannot cause: the two blocks ran at
%                      different moments and the device drifted between them
C = defaults_();
L = emptyLookup_();
if isempty(S)
    return
end
byHandle = S(S.Path == "param", :);
roleOrder = ["ScalarWrite", "ScalarRead", "Trigger", "BufferWrite", "BufferRead"];
[~, order] = sortrows([double(arrayfun(@(r) find(roleOrder == r, 1), byHandle.Role)), ...
    byHandle.NRequested]);
byHandle = byHandle(order, :);
for k = 1:height(byHandle)
    h = byHandle(k, :);
    j = find(S.Path == "name" & S.Role == h.Role & S.Parameter == h.Parameter & ...
        S.NRequested == h.NRequested, 1);
    if isempty(j)
        continue
    end
    inBlock = @(path) raw.Seconds(raw.Role == h.Role & raw.Parameter == h.Parameter & ...
        raw.NRequested == h.NRequested & raw.Path == path);
    p = ranksum(inBlock("param"), inBlock("name"));
    cost = S.Median_s(j) - h.Median_s;
    if p >= C.LOOKUP_ALPHA
        status = "below resolution";
    elseif cost > 0
        status = "resolved";
    else
        status = "negative";
    end
    L = appendRow_(L, table(h.Role, h.Parameter, h.NRequested, h.NTransferred, ...
        h.Median_s, S.Median_s(j), cost, p, status, ...
        'VariableNames', L.Properties.VariableNames));
end
end


function [scale, unit] = timeUnit_(seconds)
% The multiplier and unit name that put seconds in a readable range.
if seconds >= 1
    scale = 1;
    unit = 's';
elseif seconds >= 1e-3
    scale = 1e3;
    unit = 'ms';
elseif seconds >= 1e-6
    scale = 1e6;
    unit = [char(181) 's'];
else
    scale = 1e9;
    unit = 'ns';
end
end


function lab = pathLabel_(role, path)
% "ScalarRead, by handle" / "ScalarRead, by name": the call path in words.
% param is the pre-resolved hw.Parameter; name is the text the interface has
% to look up first.
lab = role + ", by " + replace(path, "param", "handle");
end


function txt = formatTime_(seconds)
% Seconds as text in the unit that keeps three significant figures readable:
% ns, us (micro), ms or s. The micro sign is built from its code point so the source
% file stays ASCII.
arguments
    seconds (1,1) double
end
a = abs(seconds);
if a >= 1
    txt = sprintf('%.3g s', seconds);
elseif a >= 1e-3
    txt = sprintf('%.3g ms', 1e3 * seconds);
elseif a >= 1e-6
    txt = sprintf('%.3g %cs', 1e6 * seconds, char(181));
else
    txt = sprintf('%.3g ns', 1e9 * seconds);
end
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
    '  Buffers:     Buf (or Buf_<N>) -- writable, preferably readable buffer; timed at each of Sizes\n' ...
    'Or name them: hw.benchmarkIO(iface, ScalarWrite="X", Buffers=["A" "B"], Sizes=[1024 4096])']);
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
    strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', {'Role', 'Parameter', 'Param', 'Source', 'Type', 'Access', ...
    'Capacity', 'DeclaredSize', 'Holds', 'N', 'SizeSource', 'NamePath', 'Note'});
end


function row = contractRow_(role, P, source, capacity, declared, holds, N, sizeSource, nm, note)
% holds: what the buffer is known to hold (capacity, declared size or the N
% in its name), NaN when only a read or nothing said.
arguments
    role (1,1) string
    P (1,1) hw.Parameter
    source (1,1) string
    capacity (1,1) double
    declared (1,1) double
    holds (1,1) double
    N (1,1) double
    sizeSource (1,1) string
    nm (1,1) string
    note (1,1) string
end
row = table(string(role), string(P.Name), P, string(source), string(P.Type), ...
    string(P.Access), capacity, declared, holds, N, string(sizeSource), string(nm), string(note), ...
    'VariableNames', {'Role', 'Parameter', 'Param', 'Source', 'Type', 'Access', ...
    'Capacity', 'DeclaredSize', 'Holds', 'N', 'SizeSource', 'NamePath', 'Note'});
end


function T = emptyRaw_()
C = defaults_();
T = table(strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), true(0, 1), 'VariableNames', C.RAW_VARIABLES);
end


function T = emptySummary_()
T = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), ...
    'VariableNames', {'Role', 'Parameter', 'Path', 'NRequested', 'NTransferred', ...
    'Iterations', 'Min_s', 'P5_s', 'Median_s', 'Mean_s', 'P95_s', 'Max_s', ...
    'MSamplesPerSec', 'MBPerSec', 'MbitPerSec'});
end


function T = emptyFit_()
T = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    false(0, 1), zeros(0, 1), strings(0, 1), ...
    'VariableNames', {'Role', 'Path', 'NumSizes', 'NMin', 'NMax', 'Overhead_s', ...
    'PerSample_s', 'RSquared', 'TargetSamples', 'Predicted_s', ...
    'PredictedTwoBuffers_s', 'Extrapolated', 'ExtrapolationFactor', 'Note'});
end


function T = emptyRoundTrip_()
T = table(strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    false(0, 1), strings(0, 1), ...
    'VariableNames', {'Parameter', 'NWritten', 'NRead', 'NCompared', 'NMismatched', ...
    'MismatchRuns', 'FirstMismatch', 'LastMismatch', 'MaxAbsError', ...
    'Tolerance', 'Pass', 'Note'});
end


function T = emptyLookup_()
T = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    'VariableNames', {'Role', 'Parameter', 'NRequested', 'NMoved', 'ByHandle_s', ...
    'ByName_s', 'Cost_s', 'PValue', 'Status'});
end


function T = emptyFloor_()
T = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), ...
    'VariableNames', {'Role', 'Parameter', 'Path', 'NRequested', 'Backend_s', ...
    'Floor_s', 'AboveFloor_s'});
end
