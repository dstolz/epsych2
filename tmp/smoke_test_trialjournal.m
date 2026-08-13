function smoke_test_trialjournal
% smoke_test_trialjournal
% Fitness tests for epsych.TrialJournal, the append-only crash-safe journal
% that replaced the per-trial save('-append') in ep_TimerFcn_RunTime.
%
% Covers the properties the journal exists to provide:
%   1. Round-trip fidelity for a realistic DATA payload (datetime, cell,
%      string, logical, uint32, arrays).
%   2. mergeToMat parity: the merged .mat matches what the legacy
%      save('-append') loop produced, byte-for-byte at the variable level.
%   3. Torn-tail tolerance: a file truncated at ANY byte offset class
%      (mid-signature, mid-length-prefix, mid-payload, clean boundary)
%      yields every complete record and the correct torn flag. This is the
%      deterministic proxy for the hard-kill test; the real one lives in
%      tmp/crash_test_trialjournal.m.
%   4. Fallback latch: a failed journal write latches Faulted, reroutes the
%      record to save('-append') on FallbackMatFile, and never throws.
%   5. Flat cost: per-append time must not grow with file size the way
%      save('-append') does.
%
% Run headless: matlab -batch "addpath('c:\src\epsych2'); epsych_startup('c:\src\epsych2'); run('c:\src\epsych2\tmp\smoke_test_trialjournal.m')"

scratch = fullfile(tempdir, sprintf('trialjournal_smoke_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);
cleanupScratch = onCleanup(@() localRmdir(scratch));

fprintf('\n=== smoke_test_trialjournal ===\n');

% Representative trial record, matching the shapes ep_TimerFcn_RunTime harvests.
proto = struct( ...
    'Freq', 1000, ...
    'Levels', {{10, 20, 'catch'}}, ...
    'Name', "tone", ...
    'computerTimestamp', datetime('now'), ...
    'isTest', false, ...
    'Bits', uint32(7), ...
    'Buffer', rand(1, 100));
info = struct('Subject', struct('Name', 'SmokeSubj', 'BoxID', 1), ...
    'CompStartTimestamp', datetime('now'), 'isTest', true);

% 1. Round-trip fidelity ---------------------------------------------------
jfn = fullfile(scratch, 'roundtrip.epj');
J = epsych.TrialJournal(jfn);
J.append('info', info);
N = 25;
for k = 1:N
    d = proto; d.TrialIndex = k;
    J.append(sprintf('data_%04d', k), d);
end
[S, torn] = epsych.TrialJournal.read(jfn);
assert(~torn, 'a cleanly written journal must not read as torn');
assert(isequaln(S.info, info), 'info record must round-trip exactly');
for k = 1:N
    d = proto; d.TrialIndex = k;
    assert(isequaln(S.(sprintf('data_%04d', k)), d), 'record %d did not round-trip', k);
end
fprintf('PASS: 1 %d records round-trip with full type fidelity\n', N + 1);

% 2. mergeToMat parity with the legacy save(-append) artifact ---------------
refMat = fullfile(scratch, 'reference.mat');
save(refMat, 'info', '-v6');
for k = 1:N
    d = proto; d.TrialIndex = k;
    Sk = struct(); Sk.(sprintf('data_%04d', k)) = d;
    save(refMat, '-struct', 'Sk', '-append', '-v6');
end
mergedMat = fullfile(scratch, 'merged.mat');
save(mergedMat, 'info', '-v6'); % seed .mat, as ep_TimerFcn_Start creates it
epsych.TrialJournal.mergeToMat(jfn, mergedMat);
ref = load(refMat);
mrg = load(mergedMat);
assert(isequaln(ref, mrg), 'merged .mat must equal the legacy save(-append) artifact');
fprintf('PASS: 2 mergeToMat reproduces the legacy artifact exactly\n');

% 3. Torn-tail tolerance at every truncation class --------------------------
raw = localReadBytes(jfn);
bounds = localRecordBoundaries(raw); % byte offset after magic and after each record
cuts = struct('offset', {}, 'nExpected', {}, 'tornExpected', {});
cuts(end+1) = struct('offset', 2, 'nExpected', 0, 'tornExpected', true);            % mid-signature
for k = [0 1 floor(numel(bounds)/2) numel(bounds)-1]
    b = bounds(k+1); % boundary after k records
    if k < numel(bounds)-1
        recLen = bounds(k+2) - b;
        cuts(end+1) = struct('offset', b+3, 'nExpected', k, 'tornExpected', true);   % mid length prefix
        cuts(end+1) = struct('offset', b+8+floor((recLen-8)/2), 'nExpected', k, 'tornExpected', true); % mid payload
    end
    cuts(end+1) = struct('offset', b, 'nExpected', k, 'tornExpected', false);        % clean boundary
end
for c = cuts
    tfn = fullfile(scratch, 'torn.epj');
    localWriteBytes(tfn, raw(1:c.offset));
    [St, tornt] = epsych.TrialJournal.read(tfn);
    got = numel(fieldnames(St));
    assert(got == c.nExpected, ...
        'cut at byte %d: expected %d records, read %d', c.offset, c.nExpected, got);
    assert(tornt == c.tornExpected, ...
        'cut at byte %d: expected torn=%d, got %d', c.offset, c.tornExpected, tornt);
end
fprintf('PASS: 3 %d truncation points all yield complete records + correct torn flag\n', numel(cuts));

% 4. Fallback latch ----------------------------------------------------------
doomedDir = fullfile(scratch, 'doomed');
mkdir(doomedDir);
fbMat = fullfile(scratch, 'fallback.mat');
Jf = epsych.TrialJournal(fullfile(doomedDir, 'doomed.epj'), FallbackMatFile=fbMat);
Jf.append('data_0001', proto);
rmdir(doomedDir, 's'); % journal's directory vanishes mid-run
ok = Jf.append('data_0002', proto); % must not throw
assert(~ok && Jf.Faulted, 'a failed write must latch Faulted and report failure');
ok = Jf.append('data_0003', proto);
assert(~ok, 'a faulted journal must stay on the fallback path');
fb = load(fbMat);
assert(isfield(fb, 'data_0002') && isfield(fb, 'data_0003') && ~isfield(fb, 'data_0001'), ...
    'fallback .mat must hold exactly the records written after the fault');
fprintf('PASS: 4 write failure latches, falls back to save(-append), never throws\n');

% 5. Flat cost ----------------------------------------------------------------
pfn = fullfile(scratch, 'perf.epj');
Jp = epsych.TrialJournal(pfn);
M = 400;
t = zeros(1, M);
for k = 1:M
    d = proto; d.TrialIndex = k;
    tk = tic;
    Jp.append(sprintf('data_%04d', k), d);
    t(k) = toc(tk);
end
early = median(t(1:100)); late = median(t(end-99:end));
fprintf('     append cost: first-100 median %.2f ms, last-100 median %.2f ms, max %.2f ms\n', ...
    1000*early, 1000*late, 1000*max(t));
assert(median(t) < 0.050, 'journal append is pathologically slow (median %.1f ms)', 1000*median(t));
assert(late < 4*early + 0.005, ...
    'append cost grew with file size (%.2f -> %.2f ms); the journal exists to prevent exactly this', ...
    1000*early, 1000*late);
fprintf('PASS: 5 append cost stays flat as the file grows\n');

fprintf('=== smoke_test_trialjournal: ALL PASS ===\n');
end

function b = localReadBytes(fn)
fid = fopen(fn, 'r'); c = onCleanup(@() fclose(fid));
b = fread(fid, inf, 'uint8=>uint8')';
end

function localWriteBytes(fn, b)
fid = fopen(fn, 'w'); c = onCleanup(@() fclose(fid));
fwrite(fid, b, 'uint8');
end

function bounds = localRecordBoundaries(raw)
% Byte offsets at which the file ends cleanly: after the 4-byte signature,
% then after each length-prefixed record.
bounds = 4;
pos = 4;
while pos + 8 <= numel(raw)
    len = typecast(raw(pos+1:pos+8), 'uint64');
    pos = pos + 8 + double(len);
    bounds(end+1) = pos;
end
end

function localRmdir(d)
try
    if isfolder(d), rmdir(d, 's'); end
catch
end
end
