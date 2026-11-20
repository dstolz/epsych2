function [T, info] = diag_rpcox_buffer_transfer(iface, tag, options)
% [T, info] = diag_rpcox_buffer_transfer(iface, tag)
% [T, info] = diag_rpcox_buffer_transfer(iface, tag, Sizes=[1024 65536], Repeats=10, SaveTo="D:\bench\")
%
% Raw-transport diagnostic for one RPvds buffer tag: time the RPcoX array
% calls directly, below the HAL, at several lengths up to the tag's
% capacity, so the cost of the call EPsych makes (TDTRP.write ->
% WriteTagVEX 'F32') can be held against the alternatives:
%
%   WriteTagVEX(tag, 0, 'F32', single)   the current path (TDTRP.write)
%   WriteTagV(tag, 0, single)
%   WriteTagV(tag, 0, double)
%   WriteTagVEX(tag, 0, 'I16', int16)
%   ReadTagVEX(tag, 0, n, 'F32', 'F32', 1)   n = each size, and the whole tag
%   ReadTagV(tag, 0, n)                      n = each size, and the whole tag
%
% Every write is then verified over its FULL length by an untimed read-back
% (hw.benchmarkIO only checks the first N of a whole-tag read). Every RPcoX
% return value is checked: a write returning 0, or a read returning the wrong
% count, marks its row rather than being timed as a success.
%
% This is a companion to hw.benchmarkIO, not part of it: hw.benchmarkIO calls
% nothing below hw.Interface and stays backend-agnostic. Nothing here changes
% TDTRP; a faster path found by this script is a recommendation to make
% after reading the table, not something the script acts on.
%
% RUN IT AT THE RIG, BETWEEN SESSIONS, ON A CONNECTED INTERFACE.
%   - It never connects or loads a circuit: iface must already be connected
%     (e.g. Utilities > Hardware > I/O Benchmark leaves it so, or
%     RUNTIME.Interfaces(1) after a session, or iface.connect() by hand).
%   - It writes random data into the tag, including int16 data that the
%     circuit will read as meaningless floats. The next Run reloads the
%     circuit (hw.TDT_RPcox.resetSession), which clears it.
%   - If the circuit writes its own input into the tag (an RPvds SerialBuf
%     with Write enabled, see documentation/hw/hw_benchmarkIO.md), every
%     verification will fail with one contiguous run of mismatches. Fix the
%     circuit first, or the write times are of a buffer the DSP is also using.
%   - It is COM work: in a persistent MATLAB session (the MCP server) restart
%     MATLAB afterwards, per CLAUDE.md.
%
% Parameters:
%   iface - connected hw.TDT_RPcox.
%   tag   - the buffer: parameter name (text) or hw.Parameter.
%
% Name=Value options:
%   Sizes   - element counts to time; those above the tag's capacity are
%             dropped (and said). Default [1024 4096 65536 262144 capacity].
%   Repeats - timed calls per measurement. Default 10.
%   Warmup  - calls discarded before them. Default 1.
%   SaveTo  - folder (a timestamped stem is chosen) or file stem; writes
%             <stem>.mat (T and info) and <stem>.csv (T). Default: the
%             current folder. '' does not save.
%
% Returns:
%   T    - one row per call, data class and length: Call, Data, N,
%          DeviceBytesPerSample, Repeats, CallsOK, Min_s, P5_s, Median_s,
%          P95_s, Max_s, MSamplesPerSec, MBPerSec, CycUse, Verified,
%          NMismatched, Note. MBPerSec counts the bytes per sample in the
%          DEVICE format (4 for F32, 2 for I16), not what MATLAB passed.
%   info - Date, MATLAB release, device type, interface, device number,
%          sample rate (GetSFreq), status, tag, tag type and capacity, and
%          GetCycUse before and after the run.
%
% Example (at the rig):
%   P = RUNTIME.Interfaces(1);           % or the protocol's hw.TDT_RPcox
%   T = diag_rpcox_buffer_transfer(P, "Buf", Sizes=[1024 4096 65536 1000000]);
%
% See also: hw.benchmarkIO, TDTRP, documentation/hw/hw_benchmarkIO.md
arguments
    iface (1,1) hw.TDT_RPcox
    tag
    options.Sizes (1,:) double {mustBeInteger, mustBePositive} = []
    options.Repeats (1,1) double {mustBeInteger, mustBePositive} = 10
    options.Warmup (1,1) double {mustBeInteger, mustBeNonnegative} = 1
    options.SaveTo (1,:) char = pwd
end

if ~iface.IsConnected
    error('diag_rpcox_buffer_transfer:NotConnected', ...
        'The interface is not connected. Connect it first; this script never connects.');
end

if isa(tag, 'hw.Parameter')
    P = tag;
else
    P = iface.find_parameter(char(tag), includeInvisible = true);
end
if ~isscalar(P)
    error('diag_rpcox_buffer_transfer:Tag', 'Give exactly one buffer parameter.');
end
tagName = iface.getHardwareParameterName(P);
idx = double(P.Module.Index);
h = iface.HW(idx);
RP = h.RP;

% ---- what the device is and how it is connected, before anything is timed
info = struct();
info.Date = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
info.MATLABRelease = version('-release');
info.DeviceType = char(string(h.DEVICETYPE));
info.Interface = char(string(h.INTERFACE));
info.DeviceNumber = double(h.NUMBER);
info.Module = P.Module.Name;
info.Status = double(RP.GetStatus);
info.Fs = double(RP.GetSFreq);
info.Tag = tagName;
info.TagType = double(RP.GetTagType(tagName));
info.Capacity = double(RP.GetTagSize(tagName));
info.CycUseStart = double(RP.GetCycUse);
info.CycUseEnd = NaN;

if bitget(info.Status, 1) ~= 1 || bitget(info.Status, 2) ~= 1
    error('diag_rpcox_buffer_transfer:Status', ...
        'GetStatus = %d: the device is not connected with a circuit loaded.', info.Status);
end
if ~(isfinite(info.Capacity) && info.Capacity > 1)
    error('diag_rpcox_buffer_transfer:Capacity', ...
        'GetTagSize("%s") = %g: not a buffer tag.', tagName, info.Capacity);
end
cap = info.Capacity;

sizes = options.Sizes;
if isempty(sizes)
    sizes = [1024 4096 65536 262144 cap];
end
tooBig = sizes > cap;
if any(tooBig)
    vprintf(1, 'diag: sizes %s exceed the %d samples "%s" holds; dropped', ...
        mat2str(sizes(tooBig)), cap, tagName)
end
sizes = unique(sizes(~tooBig));
if isempty(sizes)
    error('diag_rpcox_buffer_transfer:Sizes', 'No requested size fits in the %d-sample tag.', cap);
end

vprintf(1, ['diag: %s #%d over %s, "%s" (type %d, %d samples), Fs %.6g Hz, cycle usage %g%%, ' ...
    'status %d; sizes %s, %d timed calls each'], info.DeviceType, info.DeviceNumber, ...
    info.Interface, tagName, info.TagType, cap, info.Fs, info.CycUseStart, info.Status, ...
    mat2str(sizes), options.Repeats)

rs = RandStream('mt19937ar', 'Seed', 20261120);
nTotal = options.Warmup + options.Repeats;
keep = (options.Warmup + 1):nTotal;

writes = { ...
    'WriteTagVEX F32', 'single', 4, @(d) RP.WriteTagVEX(tagName, 0, 'F32', d); ...
    'WriteTagV',       'single', 4, @(d) RP.WriteTagV(tagName, 0, d); ...
    'WriteTagV',       'double', 4, @(d) RP.WriteTagV(tagName, 0, d); ...
    'WriteTagVEX I16', 'int16',  2, @(d) RP.WriteTagVEX(tagName, 0, 'I16', d)};
readSizes = unique([sizes cap]);
reads = { ...
    'ReadTagVEX F32', @(n) RP.ReadTagVEX(tagName, 0, n, 'F32', 'F32', 1); ...
    'ReadTagV',       @(n) RP.ReadTagV(tagName, 0, n)};
rows = cell(size(writes, 1) * numel(sizes) + size(reads, 1) * numel(readSizes), 1);
nRow = 0;

% ---- writes, each verified over its full length
for w = 1:size(writes, 1)
    [call, cls, bps, fcn] = writes{w, :};
    for n = sizes
        data = payload_(rs, cls, n);
        vprintf(1, 'diag: %s (%s), N=%d ...', call, cls, n)
        cyc = cycUse_(RP);
        t = NaN(nTotal, 1);
        ok = false(nTotal, 1);
        note = "";
        try
            for k = 1:nTotal
                t0 = tic;
                r = fcn(data);
                t(k) = toc(t0);
                ok(k) = isequal(double(r), 1);
            end
            [verified, nBad, vnote] = verifyWrite_(RP, tagName, fcn, payload_(rs, cls, n), cls);
            note = vnote;
        catch ME
            vprintf(0, 1, ME)
            verified = false;
            nBad = NaN;
            note = "threw: " + string(ME.message);
        end
        if ~all(ok(keep))
            note = strtrim(note + sprintf(" %d of %d calls returned 0", sum(~ok(keep)), numel(keep)));
        end
        nRow = nRow + 1;
        rows{nRow} = row_(call, cls, n, bps, t(keep), ok(keep), cyc, verified, nBad, note);
        report_(rows{nRow})
    end
end

% ---- reads, at each size and the whole tag
for r = 1:size(reads, 1)
    [call, fcn] = reads{r, :};
    for n = readSizes
        vprintf(1, 'diag: %s, N=%d ...', call, n)
        cyc = cycUse_(RP);
        t = NaN(nTotal, 1);
        ok = false(nTotal, 1);
        note = "";
        cls = "";
        try
            for k = 1:nTotal
                t0 = tic;
                v = fcn(n);
                t(k) = toc(t0);
                ok(k) = numel(v) == n;
            end
            cls = string(class(v));
            if n == cap
                note = "whole tag";
            end
        catch ME
            vprintf(0, 1, ME)
            note = "threw: " + string(ME.message);
        end
        if ~all(ok(keep))
            note = strtrim(note + sprintf(" %d of %d calls returned the wrong count", ...
                sum(~ok(keep)), numel(keep)));
        end
        nRow = nRow + 1;
        rows{nRow} = row_(call, cls, n, 4, t(keep), ok(keep), cyc, NaN, NaN, note);
        report_(rows{nRow})
    end
end

info.CycUseEnd = cycUse_(RP);
T = vertcat(rows{:});

vprintf(1, 'diag: %s #%d over %s, cycle usage %g%% at start, %g%% at end', ...
    info.DeviceType, info.DeviceNumber, info.Interface, info.CycUseStart, info.CycUseEnd)
vprintf(1, char(formattedDisplayText(T, 'SuppressMarkup', true)))

if ~isempty(options.SaveTo)
    save_(T, info, options.SaveTo);
end
end


% =====================================================================
function d = payload_(rs, cls, n)
% Random row data of the class the call is given: floats in [-1 1), int16
% over most of its range.
switch cls
    case 'single'
        d = 2 * rand(rs, 1, n, 'single') - 1;
    case 'double'
        d = 2 * rand(rs, 1, n) - 1;
    case 'int16'
        d = int16(randi(rs, [-32000 32000], 1, n));
end
end


function [verified, nBad, note] = verifyWrite_(RP, tagName, fcn, data, cls)
% Untimed: write fresh data with the same call, read the same length back
% in the matching device format, compare every sample. Floats are compared
% at float32 precision (the device stores F32); int16 exactly.
n = numel(data);
note = "";
if ~isequal(double(fcn(data)), 1)
    verified = false;
    nBad = NaN;
    note = "verification write returned 0";
    return
end
if strcmp(cls, 'int16')
    % The I16 read-back convention (packing of two samples per 32-bit word)
    % is RPcoX's and is not confirmed here; a mismatch on this row may be the
    % convention rather than the write.
    v = RP.ReadTagVEX(tagName, 0, n, 'I16', 'I16', 1);
    expected = double(data);
    got = double(v);
    tol = zeros(1, n);
else
    v = RP.ReadTagVEX(tagName, 0, n, 'F32', 'F32', 1);
    expected = double(single(data));
    got = double(single(v));
    tol = double(eps(single(abs(expected))));
end
if numel(got) ~= n
    verified = false;
    nBad = NaN;
    note = sprintf("read-back returned %d of %d samples", numel(got), n);
    return
end
bad = ~(abs(reshape(got, 1, []) - expected) <= tol);
nBad = nnz(bad);
verified = nBad == 0;
if ~verified
    idx = find(bad);
    runs = 1 + nnz(diff(idx) > 1);
    note = sprintf("%d of %d samples differ, in %d run(s), samples %d-%d", ...
        nBad, n, runs, idx(1), idx(end));
    if strcmp(cls, 'int16')
        note = note + " (I16 read-back convention unconfirmed)";
    end
end
end


function c = cycUse_(RP)
% Cycle usage now, or NaN when the call fails.
try
    c = double(RP.GetCycUse);
catch ME
    vprintf(2, 'diag: GetCycUse failed: %s', ME.message)
    c = NaN;
end
end


function R = row_(call, cls, n, bps, t, ok, cyc, verified, nBad, note)
pr = prctile(t, [5 95]);
med = median(t);
R = table(string(call), string(cls), n, bps, numel(t), all(ok), min(t), pr(1), med, ...
    pr(2), max(t), n / med / 1e6, bps * n / med / 1e6, cyc, verified, nBad, string(note), ...
    'VariableNames', {'Call', 'Data', 'N', 'DeviceBytesPerSample', 'Repeats', 'CallsOK', ...
    'Min_s', 'P5_s', 'Median_s', 'P95_s', 'Max_s', 'MSamplesPerSec', 'MBPerSec', ...
    'CycUse', 'Verified', 'NMismatched', 'Note'});
end


function report_(R)
vprintf(1, 'diag:   median %.4g ms (p5 %.4g, p95 %.4g), %.3g MB/s, calls ok %d, verified %g%s', ...
    1e3 * R.Median_s, 1e3 * R.P5_s, 1e3 * R.P95_s, R.MBPerSec, R.CallsOK, R.Verified, ...
    char(" " + R.Note))
end


function save_(T, info, saveTo)
[folder, stem] = fileparts(saveTo);
if isfolder(saveTo) || endsWith(saveTo, {'/', '\'})
    folder = saveTo;
    stem = sprintf('diag_rpcox_buffer_transfer_%s', char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss')));
end
if isempty(folder)
    folder = pwd;
end
if ~isfolder(folder)
    mkdir(folder);
end
matFile = fullfile(folder, [stem '.mat']);
csvFile = fullfile(folder, [stem '.csv']);
save(matFile, 'T', 'info');
writetable(T, csvFile);
vprintf(1, 'diag: saved %s and %s', matFile, csvFile)
end
